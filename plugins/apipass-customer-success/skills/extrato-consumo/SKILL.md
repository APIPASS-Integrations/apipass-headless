---
name: extrato-consumo
description: Gera o extrato mensal de consumo de um cliente de faturamento por consumo da APIPASS a partir do account_name — autentica no ambiente, coleta execuções via MCP, calcula tier e faturamento, monta o PPT e atualiza a planilha de controle. Use quando CS pedir "extrato de consumo do mês", "extrato do cliente X", "fecha o consumo de [mês]" ou o relatório mensal de faturamento por execuções.
---

# Extrato de Consumo Mensal — motor genérico

## O que esta skill faz

Recebe um `account_name` e um mês de referência, autentica no ambiente do cliente, coleta as execuções pelo MCP da APIPASS, calcula o faturável e o tier, e monta o PPT no layout já usado com o cliente.

Substitui um processo que era 100% manual: ~11 prints, três planilhas e aritmética na mão (mapeado na reunião "Agenda interna - Skills Claude - CS", 30/07/2026, Fathom 767320050). **Prioridade Alta** da automação de CS.

Antes de qualquer coisa, carregue a config do cliente em `configs/<cliente>.md`. Tiers, custos fixos, vigências e o projeto a descontar são **específicos de contrato** e nunca ficam neste arquivo.

## Passo 1 — Autenticar

`apipass_auth_status`. Se não estiver autenticado no realm certo, chame `apipass_login` com o `account_name` da config e **entregue a URL para o usuário autorizar**. A skill para e espera aqui — não existe caminho headless. Token dura ~12h.

## Passo 2 — Resolver o período

**Esta é a armadilha que mais importa** — erra o número da fatura sem dar nenhum sinal de erro.

`startDate`/`endDate` são **instantes UTC**, não datas locais, **e `endDate` é inclusivo**. Para `America/Sao_Paulo` (UTC−3):

```
startDate = <1º dia do mês>T03:00:00.000Z
endDate   = <1º dia do mês seguinte>T02:59:59.999Z
```

Junho/2026 com essa janela reproduz o extrato entregue **exatamente**: 1.355.319. Compare com os erros possíveis: datas simples (`2026-06-01`/`2026-06-30`) dão 1.316.535, 2,9% a menos; fechar em `T03:00:00.000Z` dá 1.355.635, capturando um resíduo do dia 1º do mês seguinte.

Dois diagnósticos rápidos na série diária:
- primeiro bucket muito menor que a média (1.613 num dia de ~45.000) → janela deslocada para trás;
- um bucket **a mais** que os dias do mês, com valor pequeno → `endDate` está pegando o mês seguinte.

## Passo 3 — Coletar

Detalhes chamada-a-chamada em `references/mcp-coleta.md`. Resumo:

| Dado | Chamada |
|---|---|
| Execuções totais | `get_usage_summary(metric="total", …)` |
| Projeto a descontar | `list_projects(name=…)` — nome **exato** da config |
| Execuções descontadas | `get_execution_summary(period="flow", projectId, …)` → somar |
| Linhas das lâminas | `get_execution_summary(period="flow", projectId, …)` **projeto a projeto** |

**Nunca chame `period="flow"` sem `projectId`**: na conta inteira a resposta estoura o limite do MCP e volta **truncada no meio de um registro**, sem aviso claro. Itere `list_projects` e agregue.

Cada linha vem com `flowName`, `projectName`, `stageName`, `requests`, `executions`, `throughputSize`. Uma linha é um par **fluxo × stage**, não um fluxo: em junho/2026 eram 172 linhas para 151 fluxos distintos (143 Prod + 29 Dev). O total faturado **inclui Dev**.

## Passo 4 — Calcular

1. **Total faturável** = execuções totais − execuções do projeto descontado.
2. **Tier**: faixa do total faturável na tabela da **vigência correta**. A regra de virada está na config (na Conta D: reajuste entra no consumo de agosto / faturamento de setembro).
3. **R$ do período** = faturável × unitário do tier.
4. **Custos fixos** da mesma vigência.
5. **Chamados**: categorizar e checar SLA; se algum estourar, calcular a multa da config.

**Não confie na coluna de R$ unitário da linha mensal da planilha de controle** — mai/2026 e jun/2026 estão com preço de Tier 2 num mês de Tier 3 (fórmula arrastada). A fonte autoritativa é o bloco "Modelo de tabela de faturamento".

Se o valor calculado destoar do mês anterior, **sinalize em vez de aplicar em silêncio**.

## Passo 5 — Gerar o PPT

Monte o JSON de dados e rode o script. Ele faz tudo: renderiza as lâminas, a tabela de faturamento e a de chamados, ajusta a quantidade de slides, troca os textos e exporta PNGs para revisão.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/extrato-consumo/scripts/New-ExtratoPptx.ps1" -DataJson "<dados.json>" -TemplatePptx "<extrato do mes anterior.pptx>" -OutPptx "<extrato do mes.pptx>" -WorkDir "<scratchpad/work>" -ExportReview
```

O schema do JSON está em `references/render-lamina.md`, junto com a especificação visual e as armadilhas de COM que o script já resolve. **Escreva o JSON em UTF-8** — todo texto acentuado vem dele, nunca hardcoded no `.ps1`.

O script imprime uma seção `--- PENDENCIAS ---` no final. Repasse-a ao usuário na íntegra.

### Slides 2 e 3 — print automatizado do dashboard

Esses dois slides são o **dashboard inteiro da plataforma** (nav bar, filtro, 5 cards de KPI, gráfico diário), não uma tabela. Não são replicáveis de forma confiável: o KPI "PUBLICADOS" não sai de `list_flows` (verificado — o objeto não traz estado de publicação) e exigiria uma chamada por fluxo, ~324 por execução.

Então em vez de replicar, **capturamos a tela de verdade**:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/extrato-consumo/scripts/Get-DashboardPrint.ps1" -Url "<url do dashboard com o filtro>" -OutPng "<work>/dash-total.png" -MonitorIndex 1 -CropTop 32 -WaitSeconds 12
```

O script abre a URL numa janela Chrome `--app` (sem barra de endereço nem abas), posiciona no monitor escolhido, espera, captura a área de conteúdo e fecha o navegador. Depois é só passar o PNG para o `New-ExtratoPptx.ps1`.

A URL segue o padrão **`https://<account_name>.app.apipass.com.br/dashboard`** — o `account_name` é o subdomínio, o mesmo usado no `apipass_login`.

### Receita validada em 04/08/2026 (julho/2026, Conta D)

O print é **automatizável de ponta a ponta**, combinando a extensão Claude in Chrome (para operar os filtros) com o script Win32 (para gravar o PNG em disco). Requisitos: extensão instalada e logada na mesma conta, e a pessoa logada na plataforma no Chrome uma vez.

**Passo a passo:**

1. `navigate` para `https://<conta>.app.apipass.com.br/dashboard`. A extensão cria uma aba nova e **a sessão sobrevive** — é cookie, não `sessionStorage`.
2. Abrir o seletor de **Período** e escolher o preset **"Mês passado"**. Como o extrato é sempre gerado no mês seguinte, esse preset é o mês de referência. Mais confiável que digitar datas: `form_input` nos campos de data não dispara o recálculo do Angular.
3. **Clicar na lupa** (`button "search"`). Sem isso o rótulo muda mas os números não — o app só recarrega ao aplicar.
4. Esperar o **banner de debug** da extensão (`"Claude" começou a depurar esse navegador`) desaparecer. Ele soma ~48 px no topo e **desloca a página**, quebrando qualquer `-CropTop` fixo.
5. Ativar a aba da extensão e capturar:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/extrato-consumo/scripts/Set-LastTabActive.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/extrato-consumo/scripts/Get-DashboardPrint.ps1" -Url x -UseExistingWindow -WindowTitleMatch "APIPASS" -OutPng "<work>/print-01-total.png" -MonitorIndex 1 -CropTop 100
```

6. Selecionar **Projeto = `<projeto a descontar>`** (atenção ao nome exato), clicar na lupa de novo, capturar como `print-02-<projeto>.png`.

Saída: dois PNG 1920×932, prontos para o `New-ExtratoPptx.ps1`.

**Armadilhas, todas medidas:**
- **A captura Win32 renderiza a aba VISÍVEL da janela, não a que a extensão controla.** A extensão abre uma aba nova que não fica em foco, então sem ativar a última aba (`Ctrl+9`) você captura a aba antiga — e o print sai com o mês errado, silenciosamente. Foi o que aconteceu no primeiro teste: capturou "Este mês / 171.737" em vez de julho.
- **`save_to_disk` do `computer` da extensão não grava no filesystem local** — vai para o store da conversa. Não serve para alimentar o PPT; por isso a captura é Win32.
- **`browser_batch` falha em `screenshot`/`get_page_text`/`form_input`** com `permission_required` na primeira vez de cada tipo: chame standalone uma vez para o usuário aprovar, depois batche.
- **Nunca digite as credenciais** pelo script nem pela automação — quem faz o login é a pessoa. Se a captura pegar o diálogo "Salvar senha?" do Chrome, **descarte o PNG**: ele contém usuário e campo de senha.
- Um `--app` com `--profile-directory` **não** funciona: cai na tela de login (provavelmente o modo app quebra o redirect do SSO). Use a extensão.

Pontos que custaram um ciclo de teste:
- **Use o perfil padrão do Chrome.** É o que carrega a sessão. `--user-data-dir` cai na tela de login.
- **`--app` desenha a barra de título dentro da área de cliente**, então `GetClientRect` não a exclui. Corte com `-CropTop 32`.
- **`-MonitorIndex 1`** joga a janela no monitor secundário para não atrapalhar quem estiver usando a máquina. A captura rouba o foco por alguns segundos de qualquer forma.
- **O script tem duas validações e sai com código de erro em ambas.** Contagem de cores distintas pega tela em branco (exit 2). Fração de pixels claros pega **tela de login** (exit 3): o dashboard é predominantemente branco, a tela de login é azul-marinho em quase toda a área — medido 12,7% de pixels claros contra o limite de 40%.
  > A segunda validação existe porque a primeira não bastava: uma tela de login tem conteúdo de sobra e passava como `OK`. Sem esse guard, uma sessão expirada põe a tela de login dentro do extrato que o TI do cliente repassa ao financeiro. **Se o script falhar, não use o PNG.**

Se o print não puder ser gerado, o `New-ExtratoPptx.ps1` **apaga a imagem antiga e deixa um aviso vermelho no lugar**. Nunca deixar a imagem do mês anterior nesses slides: um print de junho num extrato de julho é pior que um espaço vazio.

## Passo 6 — Atualizar a planilha de controle

Nova linha no padrão existente. O rótulo `tíer N` fica na linha **acima** do cabeçalho `Ref.`.

**Não corrija inconsistências antigas da planilha por conta própria** (R$ unitário de mai/jun 2026, duplicidade de outubro sob "Novembro", anos digitados como 2014). Reporte e deixe a decisão com a CS.

## Guardrails

- **Nunca enviar ao cliente sem conferência humana.** A skill entrega para revisão.
- **Mês fechado não se recalcula em silêncio.** O dado em si é estável — junho/2026 reproduz exato. Justamente por isso, se um mês já emitido der número diferente, **é erro de parâmetro, não flutuação**: pare e investigue a janela antes de sobrescrever qualquer coisa.
- **Não travar.** Se uma fonte não existe (o Clock não tem MCP), gere o que der e liste o que falta. Regra explícita da Vanessa.
  - ⚠️ **Mas confirme que a fonte realmente não existe.** O exemplo que estava aqui era "Movidesk não tem MCP" — **premissa falsa desde 13/08/2026**: os chamados são consultáveis no Dashboard CS - Métricas Suporte da própria APIPASS. O mesmo valeu para o "Grafana". **Antes de declarar fonte indisponível, procure um fluxo nosso que já sirva o dado.**
- Uma instância COM por arquivo; sempre `Close`/`Quit` em `finally`. Processos `wps`/`wpp` órfãos travam o arquivo de saída — antes de matar, confira `MainWindowTitle`: vazio é instância headless de automação, preenchido é documento aberto por alguém.
  - **Um PID com janela pode segurar VÁRIOS arquivos.** O WPS é instância única com abas: em 27/08/2026 uma janela intitulada com um PDF travava outros dois. Sintoma: o `.docx`/`.pptx` grava e só a exportação falha. **Peça para a pessoa fechar**, não mate o processo.
- **Arquivamento de entregável é `Copy-Item`, nunca `Move-Item`.** Aprendido no report estratégico em 27/08/2026: o move tirou os arquivos da pasta de entrega, o build seguinte falhou e a pasta ficou sem entregável. **Build que falha não pode destruir o que já estava entregue.** O `New-ExtratoPptx.ps1` não tem etapa de arquivamento hoje — se ganhar, nasça com cópia.
