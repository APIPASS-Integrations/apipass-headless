---
name: suggest-metrics
description: |
  Sugerir metricas customizadas de negocio (COUNT/RATE/GAUGE/HISTOGRAM/SET) para um fluxo ou para todos os fluxos de um projeto APIPASS. Use quando o usuario pedir "quais metricas eu deveria adicionar nesse fluxo", "sugira metricas para esse projeto", "esse fluxo tem observabilidade suficiente?", "monta as metricas de negocio" — ou apos um `review-flow` apontar falta de metrica customizada (regra S9).

  Aceita escopo de UM fluxo (flowId/nome) ou de um PROJETO INTEIRO (projectId/nome — todos os fluxos do projeto). Ao final, oferece montar a dashboard com as metricas aplicadas (handoff para a skill `build-dashboard`).
disable-model-invocation: false
---

# Sugerir Metricas Customizadas

Analisa um fluxo (ou todos os fluxos de um projeto) e propoe metricas customizadas de negocio, consolidando as sugestoes antes de aplicar qualquer coisa. Pressupoe a skill `apipass-patterns` (secao "Metricas customizadas") — carregue-a antes se ainda nao tiver.

## 0. Autenticacao
Se alguma tool retornar `status: "login_necessario"`, rode `apipass_login`, mostre a URL ao usuario e refaca.

## 1. Resolver o escopo
- **Um fluxo**: o usuario deu um nome/id de fluxo, ou ja esta numa conversa sobre um fluxo especifico (ex. logo apos um `build-flow`/`review-flow`). Resolva com `list_flows`/busca por nome, como as demais skills.
- **Um projeto inteiro**: o usuario pediu para o projeto todo, ou deu so o nome do projeto. `list_projects` → `list_flows(projectId)` para a lista completa de fluxos do projeto.
- Ambiguo? Pergunte numa unica mensagem (fluxo especifico vs. projeto inteiro) antes de prosseguir.

## 2. Analisar cada fluxo
Para CADA fluxo no escopo (um so, ou todos do projeto), obtenha as sugestoes:
- Se a sua ferramenta suportar subagentes, delegue ao subagente `apipass-metrics-advisor` — um por fluxo, em paralelo se o escopo for um projeto com varios fluxos. Ele le a estrutura do fluxo e devolve sugestoes prescritivas (metricName, tipo, value, tags, apos qual step, pergunta de negocio) sem aplicar nada.
- Sem suporte a subagentes, siga o mesmo processo descrito no agente diretamente: `get_flow_development(flowId)` + `get_flow_info(flowId)`, identifique eventos de negocio nao cobertos pelas metricas built-in e monte as sugestoes seguindo os sinais e o formato de `apipass-metrics-advisor` (ver skill `apipass-patterns`, secao "Metricas customizadas", para os 5 tipos e o shape do step).

## 3. Consolidar
Junte as sugestoes de todos os fluxos analisados num relatorio unico:
- Uma secao por fluxo, com a lista de sugestoes (metricName, tipo, pergunta de negocio, apos qual step).
- Verifique nomes duplicados entre fluxos do mesmo projeto (dois fluxos sugerindo o mesmo `metricName` para eventos diferentes) — avise e peca para o usuario escolher nomes distintos, ou confirme que e intencional (mesmo evento de negocio emitido por fluxos diferentes, ex. dois fluxos que processam o mesmo tipo de pedido).
- Remova sugestoes que dupliquem uma metrica customizada ja existente na conta (os subagentes/voce ja checaram via `list_metric_options`) — mantenha so a nota de reaproveitamento.
- Se nenhum fluxo tiver candidato, diga isso claramente — nao force sugestoes.

## 4. Confirmar e aplicar
Apresente o relatorio consolidado e pergunte quais sugestoes aplicar — por fluxo, por metrica, ou todas. **Nunca aplique sem confirmacao explicita do usuario**, mesmo que ele diga algo como "parece bom" de forma generica — confirme a lista final antes de escrever.

Para cada fluxo com sugestoes aprovadas:
1. `get_flow_development(flowId)` para pegar os steps atuais (a numeracao `a<n>` pode ter mudado desde a analise).
2. Insira o(s) step(s) de metrica no array, ajustando `id` (proximo `a<n>` livre), `nextSteps`/`previousSteps` dos steps vizinhos para encadear o novo step na posicao indicada (`afterStepId`), e `positionX`/`positionY` (ver convencao de layout na skill `build-flow`).
3. `save_flow_development(flowId, steps, confirm: true)`.
4. Confira o resultado com `get_flow_development(flowId)`.

Nao crie versao nem publique automaticamente — isso fica para o fluxo normal de `build-flow`/`review-flow` (o usuario decide quando versionar).

## 5. Oferecer a dashboard
Ao final, se alguma metrica foi aplicada, pergunte se o usuario quer montar uma dashboard no Monitor com elas agora. Se sim, prossiga com a skill `build-dashboard` (escopo ja conhecido: o(s) fluxo(s)/projeto deste pedido; metricas ja conhecidas: as que acabaram de ser aplicadas).

## Principios
- Nunca aplique uma metrica sem a aprovacao explicita do usuario.
- Nao invente `actionId`/`coreRouteType`/shape de tags — siga a skill `apipass-patterns`.
- Metrica de negocio, nao tecnica: eventos ja cobertos pelas built-in (`flow_executed` etc.) nao viram sugestao.
- Projeto inteiro pode gerar muitas sugestoes — priorize clareza (agrupe por fluxo) em vez de uma lista unica longa.

## Skills relacionadas
- skill `apipass-patterns` — os 5 tipos de metrica, shape do step, tags reservadas
- skill `build-flow` — como inserir/reencadear um step num fluxo existente
- skill `review-flow` — regra S9 aponta aqui quando falta observabilidade de negocio
- skill `build-dashboard` — montar a dashboard do Monitor com as metricas aplicadas
- skill `set-account` — definir a conta/realm
