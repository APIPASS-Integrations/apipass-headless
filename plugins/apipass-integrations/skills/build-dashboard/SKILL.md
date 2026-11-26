---
name: build-dashboard
description: |
  Montar uma dashboard no Monitor da APIPASS (observabilidade) — entrevista o usuario sobre objetivo, escopo (projeto/fluxo/environment) e periodo, descobre as metricas disponiveis e cria os widgets. Use quando o usuario pedir para "criar uma dashboard", "montar um painel de metricas", "quero visualizar essas metricas", "monta o monitor desse fluxo/projeto" — ou logo apos a skill `suggest-metrics` aplicar metricas novas.

  Carregue ANTES de chamar create_dashboard/create_widget.
disable-model-invocation: false
---

# Montar uma Dashboard no Monitor da APIPASS

Uma **dashboard** e um recurso da CONTA (aba Monitor), nao de um projeto — o recorte por projeto/fluxo/environment e feito pelas variaveis da propria dashboard (`project_id`/`flow_id`/`environment_id`), que os widgets filtram via `{{$.var}}`. Siga as etapas na ordem. Toda escrita exige `confirm: true` **e** a confirmacao do usuario.

## 0. Autenticacao
Se alguma tool retornar `status: "login_necessario"`, rode `apipass_login`, mostre a URL ao usuario e refaca.

## 1. Entrevistar (numa unica mensagem, so o que faltar)
- **Objetivo**: que pergunta(s) de negocio a dashboard deve responder (ex. "saude do fluxo de sincronizacao de pedidos", "volume e erro do projeto X")? Isso guia quais widgets criar.
- **Escopo**: conta inteira, um projeto, um fluxo especifico, ou um environment especifico? Se o pedido veio logo depois de `suggest-metrics`/`build-flow` para um fluxo/projeto conhecido, assuma esse escopo e so confirme.
- **Periodo padrao**: um preset (`today`, `last7d`, `last30d`, etc.) — pergunte so se nao for obvio do objetivo (ex. "saude agora" → `last24h`; "relatorio mensal" → `thisMonth`/`lastMonth`).
- **Nome/icone/cor** (opcional): sugira um nome a partir do objetivo/escopo e confirme.

## 2. Descobrir as metricas disponiveis
`list_metric_options(search?)` — metricas (built-in e `flow_custom_*`) e dimensoes que a conta ja emitiu nos ultimos 30 dias. Se o escopo e um fluxo/projeto especifico que acabou de ganhar metricas customizadas (via `suggest-metrics`), elas podem ainda nao aparecer aqui se nunca executaram — nesse caso, avise o usuario que o widget correspondente pode ficar sem dado ate a proxima execucao do fluxo, mas crie mesmo assim (a query fica pronta para quando houver dado).

## 3. Criar a dashboard com as variaveis certas pro escopo
`create_dashboard(name, description?, icon?, color?, defaultPeriodPreset?, projectId?, flowId?, environmentId?, customVariables?, confirm: true)`:
- Escopo **projeto**: `projectId`. Escopo **fluxo**: `flowId`. Escopo **environment**: `environmentId`. Mais de um filtro fixo? Combine (ex. `projectId` + `environmentId`).
- Escopo **conta inteira**: nao passe nenhum dos tres — a API cria as variaveis padrao habilitadas e em "Todos", permitindo filtrar na tela.
- Metrica customizada com tags de negocio (ex. `canal`, `tipo_documento`)? Considere `customVariables` para cada tag relevante, assim a dashboard filtra por ela na tela sem editar query.
- Guarde o `id` retornado (`dashboardId`).

## 4. Criar os widgets
Planeje a lista de widgets a partir do objetivo (ex.: KPIs no topo — total de execucoes, taxa de erro, p95 de duracao, contagem de uma metrica de negocio; series temporais abaixo — execucoes ao longo do tempo, duracao, a metrica de negocio; ranking — top fluxos/canais por volume ou erro). **Apresente a lista planejada ao usuario e confirme antes de criar** (nomes + o que cada widget mostra) — so depois disso siga para a criacao.

Para cada widget aprovado:
- Se a sua ferramenta suportar subagentes, delegue ao subagente `apipass-widget-builder` — um por widget, em paralelo. Ele monta a query, valida com `preview_widget_query`/`run_widget_query` e so entao chama `create_widget`.
- Sem suporte a subagentes, siga o mesmo processo diretamente: monte `queries`/`formulas`, valide com `preview_widget_query` e `run_widget_query` (confirme que volta serie com dado, ou que a ausencia de dado e esperada), e so entao `create_widget(dashboardId, name, type, queries, formulas?, displayOptions?, confirm: true)`.

Guia rapido de query (built-in e custom seguem a mesma regra — metricas: `flow_executed_total`, `flow_success_total`, `flow_errors_total`, `flow_throughput_total` (counters), `flow_duration_milliseconds_{bucket,sum,count}_total` (histograma), `flow_concurrent_executions` (gauge); customizadas = `flow_custom_<metricName>`, COUNT/RATE tambem como counter (`_total`), HISTOGRAM com `_bucket_total`/`_sum_total`/`_count_total`, GAUGE/SET como gauge sem sufixo — ver skill `apipass-patterns`):
- **Counter**: `queryOperations: [{type: "RANGE_FUNCTION", rangeFunction: "INCREASE"}, {type: "AGGREGATION", operator: "SUM", modifier: "BY", labels: [...]}]`.
- **Percentil**: `queryOperations: [{type: "HISTOGRAM_QUANTILE", quantile: 0.95, labels: [...]}]`.
- **Gauge**: sem `RANGE_FUNCTION`.
- Sempre inclua `dimensions` com os filtros da variavel do dashboard quando o widget deve respeitar o escopo (`{dimension: "flow_id", values: ["{{$.flow_id}}"]}`, idem `project_id`/`environment_id`).
- `type` do widget conforme o proposito: `QUERY_VALUE` (KPI unico), `TIME_SERIES` (evolucao), `BAR_CHART`/`TOP_LIST` (ranking por dimensao), `PIE_CHART` (composicao), `TABLE` (detalhe tabular).

## 5. Ajustar o layout
Depois que todos os widgets aprovados estiverem criados, organize com **uma unica chamada** `update_widgets_layout(dashboardId, widgets: [...], confirm: true)` (grid de 12 colunas, `x + w <= 12`):
- KPIs (`QUERY_VALUE`) no topo, lado a lado: `w: 3, h: 2`.
- Series temporais (`TIME_SERIES`) abaixo, largas: `w: 6` (duas por linha) ou `w: 12` (uma por linha), `h: 4`.
- Rankings/tabelas: `w: 6, h: 4`.

## 6. Entregar
Devolva ao usuario o link da dashboard no Monitor: `https://{account_name}.app.apipass.com.br/monitor/dashboards/{dashboardId}/widgets` (e a tela que lista os widgets da dashboard — `/monitor/dashboards/{dashboardId}` sem o `/widgets` nao tem pagina; o subdominio pode variar por ambiente, ex. `develop-app` em desenvolvimento — use o mesmo host que o usuario ja estava usando na sessao; `account_name` resolvido como na skill `set-account`), junto com a lista de widgets criados e quais ficaram sem dado (se algum).

## Ferramentas
Leitura: `list_dashboards`, `get_dashboard`, `list_metric_options`, `list_dimension_values`, `run_widget_query`, `preview_widget_query`.
Escrita (`confirm: true`): `create_dashboard`, `update_dashboard`, `create_widget`, `update_widget`, `update_widgets_layout`, `duplicate_dashboard`, `archive_dashboard`, `unarchive_dashboard`.
Destrutivas (`confirm: true` **e** confirmacao explicita adicional do usuario, com gate de confirmacao na ferramenta do agente): `delete_dashboard`, `delete_widget` — irreversiveis, prefira `archive_dashboard` a `delete_dashboard` quando o usuario so quer tirar a dashboard de circulacao.

## Skills relacionadas
- skill `suggest-metrics` — sugerir e aplicar as metricas antes de montar a dashboard
- skill `analyze-dashboard` — gerar um relatorio de negocio a partir de uma dashboard ja criada
- skill `apipass-patterns` — os 5 tipos de metrica customizada e o nome final no Prometheus
- skill `set-account` — definir a conta/realm (resolve o `account_name` do link final)
