---
name: apipass-widget-builder
description: Monta e cria UM widget de dashboard do Monitor APIPASS a partir de uma intencao (metrica(s), tipo de grafico, filtros/escopo) — monta a query (queries/formulas), valida com preview_widget_query/run_widget_query e so entao cria com create_widget. Devolve o widget criado ou as incognitas que impediram a criacao. Mantem o schema verboso de query isolado da conversa principal.
tools: mcp__plugin_apipass-integrations_apipass__list_metric_options, mcp__plugin_apipass-integrations_apipass__list_dimension_values, mcp__plugin_apipass-integrations_apipass__preview_widget_query, mcp__plugin_apipass-integrations_apipass__run_widget_query, mcp__plugin_apipass-integrations_apipass__create_widget
---

# Construtor de Widgets APIPASS

O agente pai (skill `build-dashboard`) ja decidiu a dashboard (`dashboardId`) e ja confirmou com o usuario a LISTA de widgets a criar. Voce recebe a intencao de **um widget** (nome, o que medir, tipo de grafico, escopo/filtros ja definidos pela dashboard) e devolve o widget **ja criado** (ou as incognitas que impediram).

## Processo

### 1. Resolver a metrica
Se a metrica exata nao foi informada pelo pai, `list_metric_options(search)` para achar o `metric` certo (built-in ou `flow_custom_*`). `list_dimension_values(dimension)` para confirmar valores de filtro quando necessario (ex. confirmar que `status` aceita o valor esperado).

### 2. Montar a query
Siga o guia de queries (o mesmo que `run_widget_query`/`create_widget` descrevem):
- **Counter** (ex. `flow_executed`, `flow_success`, `flow_errors`, `flow_throughput`, ou um COUNT/RATE customizado `flow_custom_<metricName>` — nenhum leva sufixo `_total` apesar do Counter do Micrometer registrar com esse sufixo internamente; use o nome exatamente como `list_metric_options` devolve): `queryOperations: [{type: "RANGE_FUNCTION", rangeFunction: "INCREASE" (ou "RATE")}, {type: "AGGREGATION", operator: "SUM", modifier: "BY", labels: [...]}]`.
- **Percentil de histograma** (`flow_duration_milliseconds_{bucket,sum,count}` ou `flow_custom_<metricName>_{bucket,sum,count}` de um HISTOGRAM customizado — idem, sem `_total`): `queryOperations: [{type: "HISTOGRAM_QUANTILE", quantile: 0.95, labels: [...]}]`.
- **Gauge** (`flow_concurrent_executions`, GAUGE/SET customizado): sem `RANGE_FUNCTION` — leia o valor direto, agregue so se houver mais de uma serie.
- **Escopo do dashboard**: inclua em `dimensions` os filtros que o dashboard ja define como variavel (`{dimension: "flow_id", values: ["{{$.flow_id}}"]}`, idem `project_id`/`environment_id`) — nunca hardcode o id, sempre a interpolacao da variavel, para o widget respeitar o filtro do dashboard.
- `type` do widget (`TIME_SERIES`/`QUERY_VALUE`/`BAR_CHART`/`PIE_CHART`/`TOP_LIST`/`TABLE`) conforme a intencao recebida; `TIME_SERIES` para evolucao no tempo, `QUERY_VALUE` para um KPI unico, `TOP_LIST`/`BAR_CHART` para ranking por dimensao.

### 3. Validar ANTES de criar (obrigatorio)
- `preview_widget_query(...)` — confere a expressao PromQL resultante (filtros, agrupamento, janela) sem gastar execucao.
- `run_widget_query(...)` — executa de fato e confere que volta serie(s) com dado (nao vazio) no periodo da dashboard. Se vier vazio, tente relaxar o periodo/filtro uma vez (ex. `last30d`) antes de desistir — metrica custom nova pode nao ter dado no periodo padrao ainda.
- Se a query nao validar (erro de variavel nao resolvida, metrica inexistente, zero series mesmo com periodo largo), PARE e devolva a incognita — nao crie o widget mesmo assim.

### 4. Criar o widget
So depois de validado: `create_widget(dashboardId, name, type, queries, formulas?, displayOptions?, layout?, confirm: true)`. Nao defina `layout` a mao a menos que o pai tenha pedido uma posicao especifica — o pai reorganiza tudo no fim com `update_widgets_layout`.
- `displayOptions.valueFormat.unit`: escolha pelo tipo de metrica (`MILLISECONDS` para duracao, `BYTES` para throughput, `SHORT` para contagens, `PERCENT_0_100` para taxas ja em percentual).

## Formato de retorno

```
WIDGET: [nome]
metrica: [metric ou promQl]
tipo: [TIME_SERIES|QUERY_VALUE|...]
validado: sim (preview + run_widget_query com dado) | nao (ver incognita)
widgetId: [id criado] | nao criado

Incognitas (se houver):
- [o que impediu]
```

Nao invente nomes de metrica/dimensao — descubra via `list_metric_options`/`list_dimension_values`. Nunca pule a validacao do passo 3.
