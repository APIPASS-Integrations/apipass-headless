---
name: analyze-dashboard
description: |
  Analisar uma dashboard do Monitor APIPASS e gerar um relatorio de negocio — KPIs, tendencias, anomalias, erro x volume, latencia p95, riscos, recomendacoes e metricas que faltam. Compara com o periodo anterior equivalente. Use quando o usuario pedir "analise essa dashboard", "como estamos indo no fluxo X essa semana", "tem algo estranho nessas metricas", "compara com o periodo anterior", "faz um relatorio dessa dashboard".

  Carregue ANTES de chamar run_dashboard_queries.
disable-model-invocation: false
---

# Analisar uma Dashboard do Monitor APIPASS

Executa todos os widgets de uma dashboard ja existente e devolve um relatorio de negocio, comparando com o periodo anterior equivalente.

## 0. Autenticacao
Se alguma tool retornar `status: "login_necessario"`, rode `apipass_login`, mostre a URL ao usuario e refaca.

## 1. Resolver a dashboard e o periodo
- Dashboard: nome/id informado, ou `list_dashboards(search)` se ambiguo.
- Periodo: o que o usuario pediu (ex. "essa semana" → `thisWeek`, "mes passado" → `lastMonth`) ou o periodo padrao da dashboard se nao especificado.
- **Para comparar com o periodo anterior de forma correta**, prefira presets FECHADOS (`yesterday`, `lastWeek`, `lastMonth`, `lastYear`) a presets "ate agora" (`today`, `last7d`, `last30d`, `thisWeek`, `thisMonth`, `thisYear`) — nestes ultimos o periodo anterior calculado nao cobre o mesmo trecho de tempo (ex. `today` as 9h compara com ontem das 15h a meia-noite). Se o usuario pedir um preset "ate agora" e a comparacao importar, avise dessa limitacao antes de rodar (ou sugira o preset fechado equivalente).

## 2. Executar
`run_dashboard_queries(dashboardId, period/startDate+endDate, projectId?/flowId?/environmentId?/variables?, compareWithPrevious: true, ...)`. Isso roda TODOS os widgets da dashboard numa so chamada e devolve o resumo por widget (atual e, com `compareWithPrevious`, anterior) — nunca chame widget por widget.

## 3. Analisar por widget
- **Poucos widgets** (ate ~5-6): analise direto, sem subagente.
- **Muitos widgets**: delegue a analise de cada widget a um subagente `apipass-widget-analyst` (se a sua ferramenta suportar subagentes), em paralelo, passando no prompt o resumo (`current`/`previous`) daquele widget especifico — ele devolve o achado de negocio sem voce precisar processar o JSON bruto de todos os widgets na conversa principal. Sem suporte a subagentes, analise sequencialmente seguindo o mesmo roteiro do agente (ver abaixo).

Para cada widget, extraia:
- **KPI atual**: valor agregado (soma para counters, media/ultimo para gauges) com uma frase de negocio.
- **Tendencia**: `current` vs `previous` (quando houver) em %, sinalizando se e esperado ou um desvio.
- **Anomalias**: picos/quedas no `sample` do periodo atual, ou series novas que nao existiam no periodo anterior.
- **Erro x volume**: quando ha widget de erro e de volume, calcule a TAXA (erros/execucoes) em vez de comparar valores absolutos — um aumento de erros pode ser so aumento de volume.
- **Latencia p95**: se houver widget de percentil (`flow_duration_milliseconds` ou um HISTOGRAM customizado), destaque a variacao do p95, nao so a media.
- **Risco**: so quando o dado sustenta (ex. erro subindo enquanto volume cai).

## 4. Consolidar o relatorio
Produza o relatorio em markdown:

```markdown
# Analise da Dashboard: {nome}
**Periodo:** {inicio} – {fim} | **Comparado com:** {periodo anterior ou "sem comparacao"}

## KPIs
- {metrica}: {valor} ({variacao vs anterior, se houver})
...

## Tendencias
- {achado}
...

## Anomalias
- {achado, ou "nenhuma anomalia identificada"}

## Erro x Volume
- {achado, ou "sem widgets de erro/volume na dashboard"}

## Latencia (p95)
- {achado, ou "sem widget de latencia na dashboard"}

## Riscos
- {achado, ou "nenhum risco identificado no periodo"}

## Recomendacoes
- {acao sugerida, ligada a um achado concreto acima}

## Metricas que faltam
- {evento de negocio sem metrica/widget nesta dashboard — candidato a `suggest-metrics`/`build-dashboard`, ou "cobertura adequada para o objetivo da dashboard"}
```

Na secao "Metricas que faltam", olhe o objetivo provavel da dashboard (nome/descricao, `get_dashboard`) e aponte lacunas reais — nao liste toda metrica possivel, so o que faria diferenca para o objetivo dela.

## 5. Oferecer o proximo passo
Se o relatorio apontou metricas faltando ou uma dashboard sem widget pra um KPI importante, ofereça rodar `suggest-metrics` (para novas metricas) ou voltar a `build-dashboard` (para novos widgets) — nao execute nenhum dos dois sem o usuario pedir.

## Principios
- Nunca invente tendencia/anomalia sem dado — se uma serie vier vazia ou com erro, diga isso explicitamente em vez de preencher a secao.
- Seja especifico com numeros; evite frases genericas ("as metricas estao estaveis") sem o valor por tras.
- Para presets "ate agora", sempre mencione a limitacao de `compareWithPrevious` (ver passo 1) quando ela afetar a leitura do relatorio.

## Skills relacionadas
- skill `build-dashboard` — criar/ajustar a dashboard e seus widgets
- skill `suggest-metrics` — sugerir metricas novas para as lacunas encontradas
- skill `apipass-patterns` — os 5 tipos de metrica customizada e o nome final no Prometheus
- skill `set-account` — definir a conta/realm
