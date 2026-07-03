---
name: apipass-usage
description: Analise de consumo/uso da APIPASS — execucoes e requisicoes por periodo, totais/medias da conta e uso do flow-engine. Carregue quando o usuario perguntar sobre "consumo", "uso", "quanto consumi", "uso do mes", "consumo por fluxo/projeto", "uso do flow engine", quota ou custo de execucoes.
disable-model-invocation: false
---

# Consumo e uso na APIPASS

## Regra de roteamento (importante)
Perguntas de **contagem/listagem agregada** (quantos fluxos, quais fluxos, quantas execucoes) usam os **SUMARIOS**, NUNCA execution-logs:

| Pergunta | Ferramenta |
|---|---|
| "quantos fluxos executaram no periodo" / "quais fluxos rodaram" | `get_execution_summary(period: "flow", startDate, endDate, timezone)` — retorna um item por fluxo com a contagem |
| "quantas execucoes por dia/hora/mes" | `get_execution_summary(period: "daily"\|"hourly"\|"monthly", ...)` |
| "quantas execucoes no total" / "uso da conta" / "uso do flow engine" | `get_usage_summary(metric: "total"\|"average"\|"flow-engine-usage")` |

Os **execution-logs** (`list_flow_execution_logs`, `get_flow_execution_log`, etc.) sao para **inspecionar/depurar execucoes especificas** — NAO para contar ou listar quais fluxos rodaram. Listar logs e paginado e pesado; para volume/quais-fluxos, o sumario ja vem agregado.


Duas ferramentas cobrem consumo, com formatos diferentes — escolha pela pergunta:

## 1. Serie temporal: `get_execution_summary`
Consumo ao longo do tempo (para tendencias/graficos). **Obrigatorios:** `period`, `startDate`, `endDate`, `timezone`.
- `period`: `daily` | `hourly` | `monthly` | `flow` (agrupa por fluxo no periodo).
- Filtros opcionais: `projectId`, `flowId`, `environmentId`.
- Ordenacao opcional: `order`, `sortBy`.

Use para: "consumo por dia do ultimo mes", "execucoes por hora ontem", "consumo mensal do ano", "consumo por fluxo no projeto X".

## 2. Agregado da conta: `get_usage_summary`
Numeros consolidados da conta (para "quanto consumi" / cobranca / quota). Todos os params sao **opcionais** — sem `startDate/endDate` retorna o consumo corrente/total.
- `metric`: `total` (total de requisicoes/execucoes) | `average` (media) | `flow-engine-usage` (uso do flow-engine — relevante para cobranca/limites).
- Opcionais: `startDate`, `endDate`, `accountId`, `timezone`.

Use para: "quanto consumi este mes", "uso total da conta", "uso do flow engine", "media de execucoes".

## Boas praticas
- **Sempre defina o `timezone`** nas series temporais (ex. `America/Sao_Paulo`) — os buckets de dia/hora dependem dele.
- Datas em ISO (`YYYY-MM-DD` ou ISO completo). Para "este mes", calcule o primeiro e o ultimo dia.
- Para comparar periodos, faca duas chamadas (ex. mes atual vs anterior) e compare os totais.
- A conta efetiva vem do token (login). `accountId` so e necessario se o usuario quiser olhar outra conta a que tenha acesso.
- Apresente numeros de consumo de forma objetiva; se o usuario quiser grafico, os dados da serie temporal ja vem prontos para plotar.

## Relacao com logs
Consumo (quantos/quanto) e diferente de **depurar uma execucao** (por que falhou) — para investigar falhas use `/apipass-integrations:apipass-gotchas` (list_flow_execution_logs, etc.). Use consumo para volume/uso; logs para diagnostico.
