# Dashboard CS — Métricas Suporte (fonte da seção de Suporte)

Descoberto e verificado em 13/08/2026. **Isto destrava a seção de Suporte**, que estava suspensa por "Movidesk sem MCP": a fonte não é o Movidesk direto, é um dashboard da própria APIPASS que já consolida os chamados.

```
https://core.apipass.com.br/api/263aa242-3da8-4108-9c98-3fd7a79f42bf/prod/dashboard-movidesk
```

Mesma URL serve a página (GET) e os dados (POST) — é um fluxo único, publicado no environment `prod` da conta `apipass`.

## Autenticação — o login é da pessoa, não da automação

A tela pede um único campo, **CHAVE DE ACESSO**, com botão Entrar. **Não preencher pela automação.** É a mesma regra já registrada no `extrato-consumo`: quem digita credencial é a pessoa. Peça para a pessoa autenticar e só então dirija os filtros.

A chave também **fica no JS da página**, então qualquer tentativa de ler o conteúdo dos `<script>` volta bloqueada pelo guard de credencial. Se precisar inspecionar a página, peça **contagens ou nomes de campo**, nunca trechos de script.

## Filtros

`CLIENTE` · `CATEGORIA (MOVIDESK)` · `SERVICO` · `DATA INÍCIO` · `DATA FIM` → botão **Filtrar**.

- **Filtrar SEMPRE por cliente.** Sem isso a tela mostra a base inteira — no teste, **453 chamados de mais de uma dezena de contas diferentes** no mesmo gráfico. Um print desses num report de cliente **expõe dados de terceiros**.
- **As fronteiras de data são inclusivas** — verificado filtrando `22/05 → 22/05`, que devolveu os 2 chamados daquele dia. Então `01/04 → 30/06` é o trimestre fechado correto.
- Há um botão **Exportar PDF**. É download, portanto exige autorização explícita da pessoa.

## O que a API devolve

Chaves do topo:

```
totalFiltrado · abertos · encerrados
byCliente · byCategoria · byServico · byServicoTier · byStatus · byDay
medianaHoras · medianaNovaFeature · medianaPorServico
amostraSuporte · amostraNovaFeature
categoriasDisponiveis · servicosDisponiveis · clientesDisponiveis
listaTickets · listaTotal · listaLimite · filtros
```

Cada item de `listaTickets`:

```
id · subject · cliente · categoria · servico · status · createdDate · horasResolucao
```

## 🔴 O QUE O REPORT LEVA — e o que NÃO leva

**Regra da Elisama, 27/08/2026, que substitui o que esta referência dizia antes:**

> "Não utilize dias corridos, e nenhuma referencia relacionado a dias por hora. Mantenha a quantidade de chamados e filtre por serviços."

| Entra | Não entra |
|---|---|
| **Quantidade de chamados** (total, em aberto, encerrados) | ❌ tempo de resolução em **qualquer** unidade — dias corridos, dias úteis, horas |
| **Corte por SERVIÇO** — `byServico` / `servico` de cada ticket | ❌ **mediana** e "tempo médio", em qualquer forma |
| Categoria Movidesk, quando agrega leitura | ❌ os cards `medianaHoras` / `medianaNovaFeature` |

Formato do corte, no exemplo dela: *"tive 3 chamados, 2 foram N1 e 1 foi N3"*. No JSON é `suporte.porServico` (`servico` + `quantidade`); o script renderiza a linha "Por serviço: 3 N1 · 1 Manutenção de Fluxo · …". **Há guard:** o script emite pendência se o texto de suporte casar com `dia corrido|dias úteis|mediana|tempo médio|horas de resolução`, ou se vier campo de tempo no JSON.

Os **17 serviços** do seletor (é a lista canônica, conferida em 27/08/2026): `N1` · `N2` · `N3` · `BUG` · `Infra` · `Projetos` · `Arquitetos` · `Nova Feature` · `Dúvidas Gerais` · `Manutenção de Fluxo` · `Análise de Erros de Fluxo` · `Criação/Alteração de Ambientes` · `Criação/Alteração de Usuários` · `Plataforma - Autorizações/Conectores` · `Instalação ZTNA` · `Liberação de Addons de Serviço`.

Note que os serviços **não** são só níveis de atendimento: N1/N2/N3 convivem com frentes especializadas. Então "todos em N1" e "seguiu por frente especializada" são leituras diferentes e úteis — é isso que o corte entrega.

## 🔴 RETENÇÃO DE 3 MESES — colete perto do fechamento do trimestre

Descoberto em 27/08/2026, e muda o planejamento da skill: a tela avisa **"Histórico disponível apenas dos últimos 3 meses (a partir de 27/05/2026). Tickets encerrados mais antigos são expurgados automaticamente."** O campo DATA INÍCIO tem `min`, e o formulário **recusa a submissão** com data anterior — a validação nativa mostra *"O valor deve ser 27/05/2026 ou posterior"* e o clique em Filtrar simplesmente não faz nada, sem mensagem de erro na página.

**Consequência prática:** o 2026Q2 (01/04–30/06) **já não é consultável por inteiro**. Em 13/08/2026 eu li chamados de 20/04 da Conta A; hoje isso é impossível. Ou seja:

- **O que já foi coletado é insubstituível.** A tabela de chamados em `configs/<cliente>.md` deixou de ser conveniência e passou a ser **a única fonte** do trimestre depois de 3 meses. Sempre tabular ticket a ticket, com **serviço**, na coleta.
- **Gere o report perto do fechamento do trimestre.** Um report de Q2 feito em setembro não tem como apurar abril e maio.
- A conclusão de "zero chamados desde 2023" da Conta B foi apurada em 19/08/2026, quando ainda não havia esse limite, e **não é mais reproduzível**.

## Os dois fatos que mais importam — HISTÓRICOS, não usar no report

> Os dois blocos abaixo continuam **corretos sobre a fonte** e explicam os cards da tela, mas **não vão mais ao report**: por decisão de 27/08/2026 o bloco de Suporte não leva tempo de resolução. Mantidos porque quem olhar a tela vai ver os cards e perguntar.

**1. Os tempos são em DIAS CORRIDOS.** A API entrega `horasResolucao` — no chamado #7329, `80.34034722222222` — e a tela divide por 24, resultando nos `3.3d`. Precisão de subsegundo é diferença de timestamps, ou seja tempo de relógio. Se fosse dia útil, dividir por 24 não faria sentido (seria por 8 ou 9).

> ~~**Escreva "dias corridos" no report.**~~ **REVOGADO em 27/08/2026 — não escreva tempo nenhum no report.** A instrução original era: dizer "dias corridos" porque é a primeira pergunta do gestor. Não vale mais; a decisão dela foi tirar tempo do bloco inteiro. Este parágrafo fica só para explicar de onde vem o `3.3d` da tela.

**2. O card é MEDIANA, não média** — a chave é `medianaHoras`. O rótulo na tela diz "TEMPO MÉDIO DE RESOLUÇÃO (SUPORTE)", o que é impreciso.

Reconcilia exato quando testado como mediana:

| Filtro | Valores (dias) | Mediana | Card |
|---|---|---|---|
| Trimestre, sem a Nova Feature | 3,2 · 3,3 · 5,0 · 7,0 · 8,7 · 90,9 | (5,0+7,0)/2 = **6,0** | 6.0d ✓ |
| Só 22/05 | 7,0 · 90,9 | (7,0+90,9)/2 = **48,95** | 49.0d ✓ |

A Nova Feature sai da mediana de suporte porque tem card próprio (`medianaNovaFeature`).

> **Erro registrado para não se repetir:** numa primeira análise eu testei o card como **média**, encontrei `(3,3+5,0+7,0+8,7)/4 = 6,0` — coincidência aritmética exata — e concluí que o dashboard tinha "critério inconsistente" e não devia ser usado. **Estava errado.** O cálculo está correto. Antes de acusar uma fonte de inconsistência, teste também mediana, e prefira ler os nomes dos campos da API a inferir a definição pelo rótulo da tela.

**Para o time dono:** o único ajuste real é o rótulo do card (média → mediana).

## Como ler os nomes de campo sem tocar em credencial

O guard bloqueia devolver trechos de script. O que funciona é interceptar a resposta e devolver **só os nomes das chaves**:

```js
window.__cap = null;
const orig = window.fetch;
window.fetch = async function(...a){
  const r = await orig.apply(this, a);
  try { window.__cap = await r.clone().json(); } catch(e) {}
  return r;
};
```

Depois clique em Filtrar e leia `Object.keys(window.__cap)`. Encerre com `location.reload()` para desfazer o patch.

## Print da tela — cuidado

A captura Win32 (`Get-DashboardPrint.ps1`) saiu **escurecida** nesta máquina: `FRACAO_CLARA=0`, e o guard rejeitou com exit 3 alegando "tela de login". O conteúdo estava correto e autenticado — a causa provável é HDR do monitor, que faz `CopyFromScreen` capturar SDR escuro. **O diagnóstico do guard erra nesse caso**; o guard acertou em barrar, mas a mensagem aponta para o motivo errado.

Para imagem limpa, o caminho é o **Exportar PDF** da própria tela.

⚠️ **Mas não leve print da tela ao report.** A tela carrega os dois cards de tempo, e tempo de resolução **não entra** no documento (regra de 27/08/2026, no topo desta referência). A orientação anterior aqui era "explique que são medianas em dias corridos" — **revogada**: não há explicação a dar, porque o número não vai. Entregue a análise em texto, com quantidade e corte por serviço.

Além disso, um print sem filtro de cliente expõe nomes de terceiros. Se algum dia um print for necessário, filtre por cliente **e** confirme que os cards de tempo estão fora do recorte.

**Para automação, use Chrome headless em vez da captura Win32** — ele renderiza fora da tela e não sofre o escurecimento por HDR. Receita em `render-report.md`, seção de rasterização.
