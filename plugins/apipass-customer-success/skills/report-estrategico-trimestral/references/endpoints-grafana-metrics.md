# Endpoints do projeto "Grafana Metrics" — métricas que o MCP não expõe

Descoberto em 10/08/2026. **"Grafana" aqui é só a camada de renderização.** O projeto `af2e1748-5760-4685-8584-ea70b04da7a1` da conta **`apipass`** contém 15 fluxos REST que leem o MongoDB direto e são publicados no environment **`grafana`** (`e1de3286-1a43-48a6-a4b4-b05a41ff62bc`). O Grafana só consome esses endpoints — nós podemos consumir também.

Consequência para o report: a decisão de 05/08 de cortar "Grafana" do escopo não implica cortar as métricas. **A fonte é endpoint da plataforma, não Grafana.**

## Como chamar

Todos os paths publicados são prefixados por `grafana/`. Método `GET`, `authProvider: ENDPOINT`.

> **A base URL do environment `grafana` ainda não está registrada aqui.** O `get_environment` devolve as publicações e as variáveis, mas não o host. Preencher assim que confirmado — sem ela nenhum dos endpoints abaixo pode ser chamado, apenas lido na definição.

Vantagem arquitetural: os endpoints recebem `accountId` e leem o Mongo direto, então **um login na conta `apipass` + o `accountId` do cliente** pode servir o report inteiro, sem um login por realm de cliente. Também contorna o token curto (~5 min) observado nas contas de cliente. `accountId` da Conta A: `153ed3b7-6d1d-4cfb-9ca7-6e110654114f`.

## Os que interessam ao report

### `grafana/usage-metrics/flow-engine-summaries` — a fonte do bloco de capacidade
Params: `accountId`, `family`, `startDate`, `endDate` (todos obrigatórios).

`family` seleciona o tipo de engine, e cada um devolve quota + percentual:

| `family` | campos |
|---|---|
| `f` | `name`, `implementedFlows`, `flowsQuota`, `flowUsagePercentage`, `throughputQuota`, `throughputSize` |
| `e` | `name`, `totalExecutions`, `executionsQuota`, `executionsUsagePercentage`, … |
| `r` | `name`, `totalRequests`, `requestsQuota`, `requestsUsagePercentage`, … |

`*Quota` sai de `instance.quotas.capacity` do documento `flow-engines`. **É o plano contratado** — resolve a pendência que hoje depende do SharePoint, e no eixo de capacidade (fluxos), que é o enquadramento seguro.

`implementedFlows` conta `flowId` distintos em `deployments`, **excluindo** deployments cujo `routes.0.type` é `.childflow.ChildFlowTriggerRouteConfig` ou `.ams.AMSConsumeMessageRouteConfig`. Ou seja, **conta só pontos de entrada, não subfluxos** — número bem mais honesto para o gestor que o `totalItems` do `list_flows`. Na Conta A, dos 55 fluxos ativos boa parte é `subfluxo-*`.

### `grafana/users-metrics/users-login-by-account` — Usuários Ativos
Param: `accountId`. Devolve `[{ id, username, loginsCount }]`, **incluindo usuários com zero logins** — então dá o denominador, e a seção sai como "11 dos 18 usuários acessaram", não um número solto.

Dois impedimentos para uso trimestral:
1. **A janela é fixa em 30 dias**, calculada no step `a1` (`startDate.setDate(endDate.getDate() - 30)`). Não há parâmetro de período. Para trimestre, o fluxo precisa aceitar `dateFrom`/`dateTo`.
2. **Retenção de eventos do Keycloak.** O step `a2` consulta `/admin/realms/{realm}/events?type=LOGIN`, que só devolve o que o realm guarda. Se a retenção for menor que 90 dias, nenhuma mudança de código viabiliza o trimestre. **Verificar antes de prometer a seção.**

### `grafana/cs-metrics/account-consumption-monthly` — consumo mensal multi-conta
Params: `startDate`, `endDate`, `key` (obrigatórios), `accountIds` (opcional, separado por vírgula).

Agrega `execution-summaries` por conta × mês com `$dateTrunc` em `America/Sao_Paulo` — o mês sai correto no servidor. Devolve `accountId`, `accountName`, `month`, `totalExecutions`, `totalExecutionsWithError`, `totalRequests`, `totalRequestsWithError`, `throughputGB`.

Uma chamada substitui as ~20 chamadas MCP feitas na coleta da Conta A, e o `totalExecutionsWithError` alimenta o bloco de confiabilidade. Sem `accountIds` vira visão de portfólio.

**A descrição do fluxo promete "quota" e o pipeline não projeta quota nenhuma.** Não usar como fonte de plano contratado — para isso é o `flow-engine-summaries`.

### Outros, ainda não explorados
`grafana/usage-metrics/execution-summaries` (tem `timeUnit` e `flowId`), `grafana/usage-metrics/active-flows`, `grafana/list-account-flows`, `grafana/accounts/active-accounts`, `grafana/users-metrics/active-accounts`, `grafana/general-summaries/flow-engine-summaries` (todas as contas). Os `grafana/jira-metrics/*` são DORA/issues do time de desenvolvimento da APIPASS — **métrica interna, não vai para report de cliente.**

## `grafana/usage-metrics/implemented-flows-percentage` — NÃO USAR

Está quebrado: o step `a10` referencia a variável `summaries`, que nunca é definida (`usedSteps` = `a7`, `a9`). Lança `ReferenceError` em toda chamada. Os params `startDate`/`endDate` são obrigatórios no trigger e nenhum step os consome.

Diagnóstico: é uma **cópia parcial do branch `family='f'` do `flow-engine-summaries`**, que perdeu a linha `const summaries = $.a0.document || []` no caminho. O pipeline dele também é a versão antiga, sem a exclusão de childflow/AMS.

Portanto **não é um bug a corrigir, é um endpoint redundante a descontinuar** — o completo já existe, funciona e é melhor. Recomendação registrada para o time dono.

## Achados de segurança — reportados, não corrigidos

Regra de review-then-fix, e estes fluxos alimentam o dashboard de CS de outras pessoas.

1. **Credencial de administração do Keycloak em texto plano.** `users-login-by-account`, step `a0`: password grant contra o realm **master** com usuário e senha literais no `rawData`. É controle total do IdP, gravado no fluxo. Agrava: o environment `grafana` **já tem** `KEYCLOAK_API_AUTH` e `KEYCLOAK_BASE_URL` — o encanamento correto existe e não está sendo usado.
2. **Token Atlassian exposto.** A variável `JIRA_BASIC_TOKEN` do environment `grafana` é `type: string` comum, e **o valor volta em texto plano** no `get_environment`. Outras secretas do mesmo environment estão corretas (`secure: true`, sem valor). Tratar como credencial vazada: rotacionar no Atlassian e recriar como `authorization`/`secure`.
3. **Chave estática como autenticação.** `cs-metrics/account-consumption-monthly` compara uma chave literal num switch. Segredo no corpo do fluxo, e rotacionar exige editar e republicar. Sem `accountIds`, o endpoint devolve consumo de **todas as contas**.
4. **Higiene:** o environment que serve dashboards de produção acumula dezenas de variáveis de teste (`teste`, `teste123`, `Teste2111`, `anderson`, `everton_teste`, `senha`, `token`, `credencial`, `webhooksite`).

Últimos editores, para abrir o ticket: **Everton de Oliveira Ribeiro** no `cs-metrics` (10/08/2026), **Eliezer Ávila Cardoso** no de logins (27/04) e nos de flow engine (29/04), **Raphael Santos Custódio** nos de Jira e nas publicações.

## Achado lateral do MCP

`get_usage_summary(metric="flow-engine-usage", accountId=<outra conta>)` **funciona entre contas**: autenticado no realm `apipass`, devolveu dado da Conta A. A `../../extrato-consumo/references/mcp-coleta.md` registrava isso como "não testado" — agora está testado. Devolve `totalRequests`, `totalExecutions`, `traceSize`, `requestSize`, `logSize`, `throughputSize`, **sem quota alguma**, e sem período retorna consumo corrente/total (não o trimestre).
