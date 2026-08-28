# Coleta no MCP da APIPASS — chamada a chamada

Tudo aqui foi verificado em 03/08/2026 contra o realm `sebraers` e conferido com o extrato de junho/2026 já entregue ao cliente. Não é suposição.

## Autenticação

```
apipass_auth_status                      -> { authenticated, expiresInSeconds, realm }
apipass_login(account_name="sebraers")   -> { authorizeUrl }
```

- `account_name` resolve o **realm no Keycloak**. É o gancho de acesso ao ambiente do cliente.
- O login é OAuth: devolve uma URL que **alguém precisa abrir e autorizar**. Sem caminho headless.
- Token válido ~12h (`expiresInSeconds` ~43200).
- `get_execution_summary`, `list_projects` e `list_flows` **não têm** parâmetro de conta — são escopados ao token. Logo: **um login por conta**, e trocar de cliente exige novo login.
- `get_usage_summary` **tem** `accountId`. Não testado entre contas; se funcionar, permitiria consolidar vários clientes sem relogar.

## Janela de datas — a armadilha nº 1

`startDate`/`endDate` são **instantes UTC**. O parâmetro `timezone` só governa como os buckets são rotulados, não como a janela é interpretada.

**E `endDate` é INCLUSIVO.** Fechar o mês no primeiro instante do mês seguinte captura um resíduo do dia 1.

Evidência (junho/2026, conta Conta D — referência da tela: 1.355.319 execuções e 8.292.753 requisições):

| startDate → endDate | executions |
|---|---|
| `2026-06-01` → `2026-06-30` | 1.316.535 ❌ (−2,9%) |
| `2026-06-01` → `2026-07-01` | 1.356.491 ❌ |
| `2026-06-01T03:00:00.000Z` → `2026-07-01T03:00:00.000Z` | 1.355.635 ❌ (+316) |
| `2026-06-01T03:00:00.000Z` → `2026-07-01T02:59:59.999Z` | **1.355.319** ✅ exato |

O último também casa nas requisições (8.292.753), então não é coincidência de arredondamento.

**Regra:** converta as fronteiras do mês local para UTC e use o **último instante** do mês, não o primeiro do seguinte:

```
startDate = <primeiro dia do mês>T03:00:00.000Z
endDate   = <primeiro dia do mês seguinte>T02:59:59.999Z
```

Guarde o offset na config — não presuma −3 se o horário de verão voltar.

Confirmação independente em julho/2026: com fim em `2026-08-01T03:00:00.000Z` o total foi 1.938.051 e a série diária trouxe **32 buckets**, incluindo um de `2026-08-01` com 864 execuções. Com fim em `T02:59:59.999Z`: 1.937.187 = 1.938.051 − 864. O resíduo é exatamente o bucket extra.

**Diagnóstico:** buckets são dias locais rotulados na meia-noite local convertida para UTC (`...T03:00:00.000Z`). Se o primeiro bucket vier muito menor que a média (1.613 num dia de ~45.000), a janela está deslocada — é uma fração de dia.

## Chamadas

### Execuções totais da conta
```
get_usage_summary(metric="total", startDate, endDate, timezone)
  -> { requests, executions }
```
`metric` também aceita `average` e `flow-engine-usage`.

### Série diária (para diagnóstico e para o gráfico)
```
get_execution_summary(period="daily", startDate, endDate, timezone)
  -> [ { date, totalExecutions, totalRequests, totalExecutionsWithError, totalRequestsWithError, throughput } ]
```
Traz o split sucesso/erro — é a mesma série do gráfico de barras do dashboard. `period` aceita `daily`, `hourly`, `monthly`, `flow`.

### Projetos
```
list_projects(pageSize=100)
  -> { data: [ { id, name, accountId, lastUpdate, info: { flowsAmount }, archived } ], totalItems }
```
- Paginado, `page` 1-based. Itere até cobrir `totalItems`.
- `lastUpdate` responde "criou algo novo no período?" sem esforço extra.
- Conta D tem 35 projetos ativos; a soma de `flowsAmount` dá ~324 (o dashboard mostra 320 — contagens divergem um pouco).

### Execuções por fluxo — as linhas das lâminas
```
get_execution_summary(period="flow", projectId, startDate, endDate, timezone)
  -> [ { flowId, flowName, projectId, projectName, stageName, requests, executions, throughput: { throughputSize } } ]
```

**Sempre com `projectId`.** Sem ele, a resposta na conta inteira passa de 60 KB, estoura o limite do MCP e volta **truncada no meio de um registro** — sem erro de parsing evidente. Itere os projetos e agregue.

Isto **não** é preciosismo. Medido em junho/2026: a chamada da conta inteira devolveu 172 das 174 linhas e perdeu **8.670 execuções** (0,64%), porque as linhas cortadas eram fluxos de "Job"/"Controlador" com `requests = 0` — e uma delas, `Eventos / Controlador de Envio de Aprovação`, tinha **8.640 execuções**. Volume alto com zero requisições é o padrão de fluxo agendado, e é exatamente o que fica no fim da resposta.

`sortBy`/`order` existem mas **não são confiáveis**: pedir `order="asc"` devolveu o mesmo conjunto de linhas do `desc`. Ordene do lado do cliente.

**Um mesmo `flowId` pode aparecer em dois projetos diferentes** (caso real: `Projeto X -> Importar Escolas PNEE` responde tanto em `Integrações - PROJETO X` quanto em `Desenvolvimento`). A chamada da conta inteira e a chamada por projeto atribuem as execuções a projetos diferentes — 145 execuções em junho/2026. O total da conta não muda, só a atribuição. Ao agregar projeto a projeto, **deduplique por `flowId` + `stageName`** ou o total infla.

> ⚠️ **A dedupe NÃO é regra universal — corrigido em 05/08/2026, reconfirmado em 26/08/2026.** Na Conta D ela é necessária; em **três outras contas ela subnotifica**. Medido: `conta-a` Q2/2026 → soma **direta** 30.800 = `get_usage_summary` exato, e com dedupe daria 30.512 (−288). `conta-b` → 18.175 direta, exato. `conta-c` → 40.438 direta, exato.
>
> O motivo: quando o mesmo subfluxo é chamado por **projetos diferentes**, os pares repetidos são **fatias distintas**, não cópias — `master-rest-gera-token|qas` deu 71 sob um projeto e 81 sob outro, e as duas linhas são reais.
>
> **Procedimento:** rode as **duas** somas e fique com a que reproduz o `get_usage_summary` da mesma janela. Se **nenhuma** reproduzir, é a **janela** que está errada, não a agregação. Registre na config do cliente qual das duas vale — os `configs/<cliente>.md` da skill `report-estrategico-trimestral` já fazem isso.
>
> **O teste de consistência é o árbitro, não a regra escrita aqui.** Foi assim que esta própria linha foi corrigida.

## Semântica dos dados

- **Uma linha = par fluxo × stage**, não um fluxo. Junho/2026: 172 linhas para 151 fluxos distintos.
- **`stageName`** é `Prod` ou `Dev`. Junho/2026: 143 linhas Prod (1.352.136 exec) + 29 Dev (3.498 exec). **O total faturado inclui Dev** — confirmado porque a tela do dashboard sem filtro de stage mostra 1.355.319.
  > Vale confirmar com a Vanessa se isso é intencional: existe histórico de chamado por "execuções indevidas na base de DEV" (ticket 6349). Hoje o comportamento é incluir; **não exclua Dev por conta própria**, senão o extrato deixa de casar com a tela.
- **`throughputSize`** em bytes. GB = bytes ÷ 1024³ com 2 decimais (conferido: 13.007.684.154 → "12.11 GB"; 2.586.434.228 → "2.41 GB"). Abaixo de 1 GiB, MB.
- A tela do dashboard lista os fluxos **ordenados por `requests` desc**, não por execuções.

## Consistência

Os três endpoints concordam entre si: `get_usage_summary.executions` = soma da série `daily` = soma das linhas `flow`.

**O dado é estável — não há drift.** Com a janela correta, junho/2026 reproduz exatamente o extrato entregue: 1.355.319 totais, 177.753 no projeto Serviços, 1.177.566 faturáveis, 8.292.753 requisições.

> Correção de um erro anterior desta doc: uma versão anterior afirmava que o dado "se move com o tempo", com base em diferenças fluxo a fluxo (`Agendas/Atualizar agendas` 272.676 vs 272.680; `Lemontech Aprovações de PC` 56.207 vs 56.291). **Aquilo era a janela errada**, capturando um resíduo de 1º de julho — não execuções tardias. Com `endDate` no último instante do mês, as diferenças desaparecem. O projeto Serviços casava mesmo com a janela errada apenas porque não teve execuções naquele resíduo.

Ainda assim, ao regerar um mês já faturado, **compare com o que foi emitido antes de sobrescrever**. Não por instabilidade do dado, mas porque uma divergência aí indica erro de parâmetro — exatamente como este.
