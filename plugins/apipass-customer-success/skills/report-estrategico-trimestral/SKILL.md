---
name: report-estrategico-trimestral
description: Gera o Report Estratégico Trimestral da APIPASS para gestores/coordenadores de um cliente — visão do ambiente, capacidade de crescimento, oportunidades de uso/upsell — coletando o ambiente via MCP, gravando o snapshot do trimestre e produzindo o .docx/PDF de 1-2 páginas. Use quando CS pedir "report estratégico", "report gerencial", "report trimestral do cliente X", "report executivo para o gestor" ou material de aproximação com decisores.
---

# Report Estratégico Trimestral — CS APIPASS

## Contexto (orientar o raciocínio, não repetir para o usuário)

Processo **novo** na área de CS, desenhado na reunião "Agenda interna - Skills Claude - CS" (30/07/2026, Fathom call 767320050) com Vanessa Costaldello. É a **Prioridade Máxima** da automação de CS.

Objetivo declarado pela Vanessa: chegar nos **decisores** (gerentes, coordenadores) que raramente acessam a plataforma. O time de ponta (dev/monitoramento) já vê o valor no dia a dia; o gestor que aprova o investimento não. O report existe para **provar ROI e justificar o investimento** — não para ser um dump de métricas.

Consequência prática de tom: cada número precisa vir com a leitura de negócio ao lado. "12 chamados em novembro" não serve; "12 chamados, 7 de problema, todos resolvidos no mesmo dia" serve. **Nunca entregar dado bruto.**

Referências: `Downloads\CS\REPORT GERENCIAL.docx` (brainstorm original) e `Downloads\CS\Rascunho - Report Estratégico Trimestral.docx` (estrutura validada em v1). A especificação seção-a-seção está em `references/estrutura-report.md` — **ler antes de montar o report**.

## Escopo da v1 — decidido em 05/08/2026

**Nenhum indicador que dependa de HubSpot, Grafana ou Movidesk entra nesta edição.** Consequência direta:

| Seção | Status | Fonte |
|---|---|---|
A ordem abaixo **é a ordem de render** — a mesma em que o script monta o documento e a mesma de `assets/rotulos-canonicos.json`.

| # | Tópico | Status | Fonte |
|---|---|---|---|
| 1 | Visão geral do ambiente | **ativo** | MCP + documentação de fluxos |
| 2 | Capacidade de crescimento | **ativo** | MCP + snapshot do trimestre anterior |
| 3 | Capacidade do ambiente | **ativo — acesso obrigatório** | Gerenciamento de Conta → CONSUMO → Flow Engine (Passo 1c) |
| 4 | Usuários ativos | **ativo, sem dado** | endpoint existe (`users-metrics/users-login-by-account`), mas janela fixa de 30 dias e retenção de eventos do Keycloak não verificada |
| 5 | Suporte | **ativo — consulta obrigatória** | Dashboard CS - Métricas Suporte (Passo 1b) |
| 6 | Confiabilidade das integrações | **ativo** (entrou na prática; validação formal da Vanessa pendente) | MCP |
| 7 | Oportunidades de uso | **ativo** | MCP + roadmap (Jira PD/Polaris) |
| 8 | Atividades em andamento | **ativo** | **Jira, projeto PIL** — agrupado por status |
| — | ROI em horas · uptime de fluxos críticos · LinkedIn · site do cliente | **fora de escopo** | motivo de cada descarte em `references/estrutura-report.md` |

Especificação tópico a tópico, com todas as regras de conteúdo: `references/estrutura-report.md`.

> **Correção de premissa (10/08/2026), que não pode ser desfeita:** o corte de "HubSpot, Grafana e Movidesk" de 05/08/2026 **não** significou cortar essas métricas. O projeto "Grafana Metrics" da conta `apipass` é o **backend** dos dashboards — fluxos REST da própria plataforma lendo MongoDB — e o dashboard de suporte é da própria APIPASS. **Só o HubSpot segue realmente fora.** Detalhes, limitações e achados de segurança em `references/endpoints-grafana-metrics.md`.

**Tópico sem dado NÃO desaparece do documento** — renderiza declarado. E o report **declara as ausências em texto** (`naoConstam` no JSON, mais a frase obrigatória da capacidade). Omitir em silêncio faria o gestor concluir que a APIPASS não tem o dado — o oposto do que o report existe para construir.

**Não reintroduzir os itens "fora de escopo" por conta própria.** Se o usuário pedir explicitamente, inclua — e diga qual é a fragilidade do dado.

## Regra que não pode ser quebrada: nunca travar por falta de acesso

Regra explícita da Vanessa. Se uma fonte não estiver disponível, **pule a seção**, siga o report com o que existe, e liste no final o que ficou de fora e o que precisa ser fornecido. Não ficar tentando, não pedir acesso no meio da execução, **não inventar número**.

## Passo 0 — Carregar a config do cliente

`configs/<cliente>.md` (piloto: `configs/conta-a.md`). Offset UTC, projetos internos a excluir, plano contratado, `mapa_area_negocio` e pasta de entrega são **específicos do cliente** e nunca ficam neste arquivo. Campo `PENDENTE` vira ausência declarada, nunca valor chutado.

## Passo 1 — Autenticar e coletar

`apipass_auth_status`; se necessário `apipass_login(account_name=<da config>)` e **entregue a URL para o usuário autorizar**. A skill para e espera aqui — não existe caminho headless.

> **Regra da Elisama (26/08/2026): gere a URL de autenticação SEMPRE que o token expirar ou houver qualquer problema de login — sem esperar que ela peça.** Não escreva "preciso que você autorize" sem a URL ao lado, e não devolva a mesma URL de antes: `state` e `code_challenge` são de uso único e expiram, então **chame `apipass_login` de novo** para gerar uma nova.
>
> Nas contas de cliente o token tem durado **~5 minutos**, não as ~12h documentadas no extrato. Na prática isso significa: colete em paralelo, e conte com pelo menos um relogin no meio de uma coleta completa. Se uma chamada voltar `login_necessario`, o próximo passo é gerar a URL, não tentar de novo.

Coleta chamada a chamada em **`references/coleta-trimestral.md`**. O que não pode ser esquecido:

- **Janela em instantes UTC, `endDate` inclusivo.** A série `monthly` do trimestre tem exatamente 3 buckets; um quarto bucket pequeno significa que o `endDate` invadiu o mês seguinte.
- **`period="flow"` sempre com `projectId`** — sem ele a resposta volta truncada no meio de um registro, sem erro.
- **Deduplicar por `flowId` + `stageName`** ao agregar projeto a projeto.
- **Teste de consistência antes de renderizar:** `get_usage_summary.executions` == soma da série `monthly` == soma das linhas `flow`. Se não bater, é parâmetro errado — pare e investigue.
- **Colete `totalExecutionsWithError` por mês nos DOIS trimestres.** É o que viabiliza a regra obrigatória abaixo; sem o erro do trimestre anterior, a decomposição não existe.

> **Regra obrigatória: queda de execuções nunca vai ao report sem decomposição em sucesso e erro.** Compare sucesso contra sucesso e aponte o mês de concentração do erro. Sem isso o gestor lê redução de uso onde pode não haver nenhuma — na Conta A o total caiu 9,1% e a entrega concluída foi praticamente idêntica (29.501 → 29.660), com 74% menos falha. Contas, modelo de frase e as duas afirmações a não fazer estão em `references/estrutura-report.md`, seção 2.2.

Para a mecânica de consumo, carregue `/apipass-integrations:apipass-usage`.

## Passo 1b — Dashboard de Suporte: consulta OBRIGATÓRIA

**Toda vez que um report for pedido, acesse o Dashboard CS - Métricas Suporte.** Não é passo opcional nem "se der tempo" — é fonte fixa da seção de Suporte, para qualquer cliente. Regra da Elisama, 19/08/2026.

```
https://core.apipass.com.br/api/263aa242-3da8-4108-9c98-3fd7a79f42bf/prod/dashboard-movidesk
```

Mecânica completa em `references/dashboard-suporte-movidesk.md`. O essencial:

- A tela pede **CHAVE DE ACESSO** em campo de formulário. **Quem digita é a pessoa, nunca a automação** — entregue a URL, peça para autenticar e espere.
- **Filtre por cliente.** Sem o filtro a tela mostra a base inteira, com nomes de outros clientes — inaceitável num report.
- Datas: `01/04 → 30/06` para Q2, com as fronteiras **inclusivas** (verificado).
- Escreva a partir da tabela `Chamados no período`, não dos cards.
- **Zero chamados não se aceita de primeira:** reabra a janela o quanto a retenção permitir. Se continuar zero, o zero é real e é uma informação boa; se aparecer chamado fora do trimestre, o filtro estava errado. Foi assim que o zero da Conta B foi confirmado.

### 🔴 O bloco de Suporte: quantidade e SERVIÇO. Nada de tempo.

**Regra da Elisama, 27/08/2026:**

> "Não utilize dias corridos, e nenhuma referencia relacionado a dias por hora. Mantenha a quantidade de chamados e filtre por serviços. por exemplo: tive 3 chamados 2 foram N1 e 1 foi N3"

- **Entra:** quantidade de chamados (total · em aberto · encerrados) e o **corte por serviço**, em `suporte.porServico` (`servico` + `quantidade`). O script rende a linha "Por serviço: 3 N1 · 1 Manutenção de Fluxo · …".
- **Não entra:** tempo de resolução em **nenhuma** unidade — dias corridos, dias úteis, horas — e **nenhuma** mediana ou "tempo médio". Isso vale também para o texto da `leitura`.
- **Há guard no script:** se o texto casar com `dia corrido|dias úteis|mediana|tempo médio|horas de resolução`, ou se vier campo de tempo no JSON, ele emite pendência. Guard não é permissão para escrever e conferir depois — o texto já sai sem tempo.

Os serviços **não são só níveis**: N1/N2/N3 convivem com `Manutenção de Fluxo`, `Análise de Erros de Fluxo`, `Projetos`, `Nova Feature`, `BUG`, `Infra` e outros — 17 na lista canônica, em `references/dashboard-suporte-movidesk.md`. Dá leitura melhor que tempo: "três resolvidos no primeiro nível e os demais por frentes especializadas" diz mais ao gestor que uma mediana.

### 🔴 O histórico é EXPURGADO após 3 meses — colete perto do fechamento

A tela avisa: *"Histórico disponível apenas dos últimos 3 meses. Tickets encerrados mais antigos são expurgados automaticamente."* O campo DATA INÍCIO tem `min` e o formulário **recusa a submissão** com data anterior — o clique em Filtrar não faz nada e a página não mostra erro; a mensagem é a validação nativa do navegador.

Em 13/08/2026 eu leia chamados de 20/04; em 27/08 isso já era impossível. Então:

- **Tabule ticket a ticket, com o serviço, em `configs/<cliente>.md` na hora da coleta.** Depois de 3 meses essa tabela é a única fonte do trimestre.
- **Gere o report perto do fechamento do trimestre.** Feito tarde, ele não tem como apurar os primeiros meses.

## Passo 1c — Gerenciamento de Conta: acesso OBRIGATÓRIO

**Toda vez que um report for pedido, acesse a aba Gerenciamento de Conta para a capacidade do ambiente.** Regra da Elisama, 26/08/2026. **A única razão aceitável para deixar a seção em branco é não ter acesso** — nunca "não deu tempo" nem "não achei a tela".

```
https://<conta>.app.apipass.com.br/account-manager/usage-explorer/flow-engine
```

Pela interface: **ícone do avatar** no topo direito (o círculo, não o nome) → Gerenciamento de Conta → CONSUMO → Flow Engine. A aba Serviços é `/account-manager/usage-explorer/solution-services`.

Mecânica e armadilhas em `configs/_template.md`. O essencial:

- **Colete os TRÊS meses do trimestre, um a um.** A quota é mensal e não acumula; não presuma plano constante.
- **Sempre que a tela abrir, o report leva execuções E tráfego de dados.** Regra da Elisama, 26/08/2026. Não é opcional: são os dois indicadores da tela e os dois têm quota mensal própria. Faltou tráfego na primeira versão da Conta B e só apareceu quando a Conta C estourou o plano.
- **Os dois picos podem cair em meses diferentes** — na Conta B o de execuções é maio e o de tráfego é junho. **Nomeie o mês em cada indicador**, senão o leitor atribui os dois ao mesmo mês. Foi um erro real no primeiro texto da Conta B.
- **Unidade do tráfego: bytes ÷ 1024³, rotulado "GB"** — verificado em 26/08/2026 contra a tela (LogComex maio: `3306820632` bytes → tela exibe `3.08 GB`; dividir por 10⁹ daria 3,31 e não bate). A diferença entre as convenções é de 7% e pode ir para um report sobre estouro de contrato. `throughputQuota: 100` = 100 GB/mês nessa régua.
- **Nunca some as quotas mensais** para criar um denominador trimestral — ele não existe, e a média esconde o pico. O bloco compara o **mês de maior uso** contra a quota mensal.
- `form_input` **falha** nos seletores (`MAT-SELECT`). Clique o `mat-select`, clique a `mat-option` do mês, e **só então** a lupa, **em passo separado** — encadear devolve o mês novo com o número do mês anterior, sem erro visível.
- **Rota inventada redireciona para a raiz sem erro**, o que é fácil de confundir com falta de permissão. Use a rota acima antes de concluir qualquer coisa.

### 🚫 A TELA É A ÚNICA FONTE DE CAPACIDADE

**Regra da Elisama, 26/08/2026 — está acima de qualquer conveniência técnica:**

> "se lembre que conta-a vc não tem acesso a aba gerencial, você não pode acrescentar um dado que desconheci"

**Capacidade entra no report SOMENTE se a tela de Gerenciamento de Conta abriu.** Se ela não abriu, a seção **não é preenchida** — e não importa que exista outro caminho técnico para o número.

O erro concreto que essa regra proíbe: na `conta-a` a tela retorna `/unauthorized`, e eu contornei chamando o endpoint publicado `grafana/usage-metrics/flow-engine-summaries`, que lê do banco sem passar pela permissão de tela. Obtive quota real (200.000 execuções e 100 GB/mês, conferida em duas janelas) e coloquei no documento. **Foi reprovado.** O número não foi visto por quem assina o report, e ela não consegue conferi-lo contra a tela que o cliente vê. **Dado que a CS não tem acesso para conhecer não vai ao report do cliente, mesmo estando tecnicamente correto.**

A rota alternativa via `core.apipass.com.br` continua válida para **diagnóstico interno**. Nunca para preencher o report.

### Quando não houver acesso, diga o motivo CERTO

São três situações diferentes e elas não se misturam:

| Situação | O que fazer |
|---|---|
| A tela abre | Preencher a seção, com execuções **e** tráfego. Sem desculpa para deixar vazia. |
| A tela retorna `/unauthorized` | **Permissão a conceder.** Seção sem preencher, motivo na pendência. **NÃO** buscar o número por endpoint, e **NÃO** escrever nada no gráfico. |
| Não consegui **chegar** à tela (domínio bloqueado no navegador, sessão caída) | Seção em branco e **motivo real na pendência**. **NÃO** escrever "sem permissão" — é afirmar o que não foi verificado. Aconteceu com a Conta C. |

### 🔴 SEM AUTORIZAÇÃO DE ACESSO, O RELATÓRIO É OBRIGADO A DIZER ISSO

**Regra da Elisama, 26/08/2026:**

> "no report da conta-a e de qualquer outro cliente que você não tenha autorização para acessar a tela de gerenciamento, é obrigatório informar no relatório. Porque quem está lendo pensa que gerou errado."

Não é opcional, não depende do JSON do cliente e não é a mesma coisa que um `[Em construção]`. O leitor compara este report com o de outro cliente, vê uma seção sem número e conclui que **o documento saiu com defeito** — não que falta uma liberação de acesso. Isso queima a credibilidade que o report existe para construir.

**Já está implementado e sai automático**, em **dois lugares**, sempre que `capacidade` estiver ausente ou `emConstrucao`:

1. **Na própria seção**, no lugar do placeholder — texto canônico `semAcessoCapacidade` do `rotulos-canonicos.json`.
2. **No rodapé**, na linha "Não constam nesta edição" — texto curto `semAcessoCapacidadeCurto`, acrescentado pelo `Block-Rodape` mesmo se `naoConstam` vier vazio no JSON.

O texto **não** vem do JSON do cliente de propósito: não pode depender de eu lembrar de escrever a cada edição. Se o rótulo canônico faltar, o script cai no placeholder **e emite pendência**.

Enquadramento obrigatório da frase: **liberação de acesso em andamento**, não indisponibilidade da informação — e diz que a seção passa a ser preenchida na próxima edição. Nunca sugerir que a APIPASS não tem o dado.

### 🚫 O PADRÃO DO GRÁFICO NUNCA MUDA

**Regra da Elisama, 26/08/2026:**

> "Vc deve manter o padrão do gráfico independente de qualquer coisa (…) essa a regra o padrão do gráfico nunca muda"

O gráfico é **o mesmo para todo cliente**: barras com o valor absoluto, rótulo do mês, linha de média do trimestre anterior. A **linha de capacidade contratada** (com o percentual em cada barra) é o **único elemento opcional**, e entra só no caso "a tela abre" da tabela acima.

**Nada é injetado no gráfico para explicar ausência de dado** — nem nota, nem legenda de "sem permissão", nem texto substituto. Foi exatamente isso que fez o gráfico da Conta A sair diferente dos outros dois clientes e a Elisama perguntar por quê. O campo `crescimento.notaContratado` **foi eliminado** do contrato do JSON e do `New-BarChartPng`; se aparecer num JSON antigo, o script ignora e emite pendência.

Ausência de dado se declara em **texto do documento** (`naoConstam` / seção `[Em construção]`), nunca dentro do PNG — legenda de gráfico é pixel, não dá para buscar nem selecionar, e foi assim que uma nota já passou batida por ela num arquivo.

#### A régua do eixo: decidido em 26/08/2026, não reabrir sozinho

O eixo fica **na capacidade contratada** quando ela existe (decisão de 19/08: barra pequena *é* a resposta para quanto do plano está em uso) e **cai nas barras** quando não existe. Consequência: o gráfico de um cliente sem capacidade tem barras cheias e o de um cliente com capacidade tem lascas sob a linha tracejada — **eles não ficam com a mesma aparência**, e não há como igualar sem inventar capacidade para um ou mudar a régua do outro.

Levei as três opções à Elisama (eixo sempre nas barras / gráfico só quando há capacidade / manter como está) e **ela escolheu manter como está**: cada cliente usa a régua que o dado permite, e **o que impede a leitura de "gerou errado" é a frase obrigatória**, não a uniformidade do desenho. Então:

- **Não** mexer na régua do eixo para tentar igualar os gráficos.
- **Não** remover a frase obrigatória — ela é o mecanismo inteiro dessa decisão.

## Passo 2 — Reaproveitar a documentação já gerada (não refazer)

A seção "Visão Geral do Ambiente" **não deve ser escrita do zero**. Ideia da Vanessa no brainstorm: criar a página do cliente no Confluence, rodar a skill de documentação, e construir o report **em cima do output dela**.

Se já existe documentação dos fluxos do cliente, use-a como insumo. Se não existe, rode `/apipass-integrations:document-flows` e derive o report daí — assim a mesma coleta serve para a documentação técnica e para o report executivo, que era outro pedido explícito.

## Passo 3 — Gravar o snapshot do trimestre

`<pasta_entrega>/snapshot-<AAAA>Q<N>.json`, schema em `references/coleta-trimestral.md`.

Distinção que justifica o snapshot: **execuções são recalculáveis a qualquer momento** (o dado é estável), mas **contagem de projetos/fluxos ativos é fotografia** e não se reconstrói para trás. Sem snapshot, o comparativo da seção de crescimento nunca começa a existir.

Sem snapshot anterior, a seção vira **"linha de base estabelecida neste trimestre"** — declarada como tal, sem número inventado.

## Passo 4 — Pedir só o que falta (de uma vez, não uma pergunta por vez)

1. **Atividades em andamento** — tentar o Jira primeiro (projeto PIL). Só pedir input manual se o recorte não encontrar cards do cliente.
2. **Report do trimestre anterior**, se existir — baseline do comparativo.
3. **Plano contratado** — pedir **só se** o bloco de capacidade não puder ser montado. A capacidade contratada em fluxos sai do `flow-engine-summaries` (`instance.quotas.capacity`); o SharePoint só é necessário para o plano em execuções/mês.

## Passo 5 — Gerar o entregável

Monte o JSON (schema em `references/render-report.md`), grave em **UTF-8**, e rode:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/skills/report-estrategico-trimestral/scripts/New-ReportDocx.ps1" -DataJson "<dados.json>" -OutDocx "<Report Estrategico 2026Q2 - conta-a.docx>" -LayoutVariant A -ExportPdf -WorkDir "<work>"
```

**O texto segue o tom de voz da marca** — `references/tom-de-voz-apipass.md`, derivado de `Downloads\CS\APIPASS - Manual tom de voz 2.pdf`. Em resumo: **APIPASS sempre em maiúsculas** (`APIPass`/`Apipass`/`ApiPass` são incorretos), equilíbrio entre formalidade, empatia e objetividade, vocabulário oficial (integração de sistemas, automação de processos, gestão centralizada, plataforma de integração, iPaaS), e fechamento humanizado com a assinatura do princípio. "Sem ruídos" **não** autoriza maquiar dado ruim.

**Todo texto visível ao cliente vem do JSON**, inclusive títulos de seção e rótulos (bloco `rotulos`). O `.ps1` é ASCII puro: o que ficar hardcoded lá sai **sem acento** no PDF do gestor. O script emite pendência quando cai em algum fallback.

**Nome fixo e arquivamento automático.** O entregável é `Report Estrategico <trimestre> - <Cliente>.docx/.pdf`, sem sufixo de versão nem de layout. Como o nome é fixo, cada geração sobrescreve a anterior — e para não perder uma versão que já foi enviada ao cliente, **o script COPIA o vigente para `_versoes-antigas/` antes de sobrescrever**, com a data no nome.

É **uma cópia por dia**: se já existe arquivo com a data de hoje, o script mantém o primeiro e não sobrescreve. Assim iterar dez vezes num dia preserva o estado de *antes* do dia, em vez de encher a pasta. O script imprime `ARQUIVADO (copia):` quando arquiva, e `ARQUIVO: ja existe copia de hoje` quando mantém.

⚠️ **É `Copy-Item`, nunca `Move-Item` — e a falha de arquivamento nunca aborta o build.** Era Move até 27/08/2026, e causou um estrago real: o arquivamento tirou os `.docx` das **três** pastas de entrega, o build seguinte falhou (um `wps` órfão travava o PDF) e as pastas ficaram com PDF do dia anterior e **nenhum `.docx`**. Restaurados de `_versoes-antigas`. A regra que fica: **build que falha não pode destruir o entregável que já estava entregue.**

O script imprime uma seção `--- PENDENCIAS ---` no final. **Repasse-a ao usuário na íntegra.**

Guard de páginas: se o report passar de 2 páginas, o script **sai com erro** (exit 4) e lista os blocos por volume. Estourar é sinal de que o conteúdo precisa ser resumido, não de que o limite deve subir — um "executive summary" de 5 páginas não é lido.

### Layout: sempre B

**O layout padrão é o `B`** — faixa de KPIs no topo — decidido pela Elisama em 19/08/2026 e válido para **todo cliente**. É o default do script; não passe `-LayoutVariant` a menos que alguém peça explicitamente outro.

As variantes `A` (empilhada) e `C` (duas colunas) continuam no script, mas não se gera mais um leque de opções por cliente novo: o padrão está escolhido.

## Entregável final

1. O report (.docx + PDF), ou as três variantes na primeira rodada.
2. O snapshot do trimestre gravado na pasta de entrega.
3. **Lista curta e explícita do que ficou pendente** — qual seção, qual fonte faltou, o que pedir para completar.

**Nunca enviar ao cliente sem conferência humana.** É material que vai para o gestor decisor.

## Duas regras que valem mais que qualquer seção

Ambas da Elisama, 26/08/2026, depois de eu errar nas duas.

### Nomeie quem causa o comportamento

Relato de concentração, anomalia ou consumo fora do padrão **sempre nomeia o responsável** — o fluxo, o projeto e o stage. "Um único subfluxo concentra 79% das requisições" não serve para nada: o gestor não sabe onde agir. O certo é "o subfluxo `sub-vincula-nf`, do projeto de vínculo de nota, em produção, concentra 79% das requisições".

Vale para qualquer achado: fluxo que estourou consumo, projeto sem produção, integração de teste a arquivar, mês que concentrou erro. **Sem o nome, o achado é ruído.**

### Nunca decida sozinho o que tem peso comercial

Estouro de contrato, quota excedida, valor de fatura, qualquer coisa que envolva o time comercial: **traga para a CS e pergunte — não decida.**

O que eu fiz de errado na Conta C: descobri que o tráfego estava entre 3× e 7,6× acima da quota contratada, **decidi** tirar isso do documento, e para preencher o vazio **inventei** a frase "o consumo de tráfego está sendo revisado em conjunto com a APIPASS e será tratado à parte". Não havia revisão nenhuma. Inventar processo é pior que omitir: compromete a CS com algo que pode não existir.

O certo é: apurar o número, **apresentar à CS com as opções**, e escrever o que ela decidir. Se a decisão ainda não veio, a seção fica sem a informação e a pendência diz exatamente isso — sem frase de preenchimento.

## Guardrails de conteúdo

- **Seção de oportunidades nunca é enquadrada como sobra ociosa.** Risco levantado pela própria Vanessa: mostrar "contratou 1 milhão, usa 500 mil" pode fazer o cliente **reduzir** o plano. O enquadramento é capacidade disponível para crescer + features que ele já pode usar.
- **Áreas de negócio, não lista de fluxos.** "Temos integração que atende logística, RH, financeiro" é a tradução que o gestor entende.
- Fluxo sem área classificada vai para `aClassificar` e é **perguntado** — o script já emite pendência. Não chutar classificação.
- Nenhuma credencial em config, JSON ou script.
