---
name: build-agent-flow
description: |
  Construir ou modificar fluxos de AGENTE DE IA na APIPASS (Agent Builder). Use quando o pedido envolve um agente de IA, RAG ou base de conhecimento — "crie um agente de IA que...", "agente que analisa/responde...", "chatbot com base de conhecimento", "fluxo de RAG", "ingestao para vector store", "agente que consulta o banco e responde".

  Ponto de entrada para fluxos com `.service.ai.AiAgent`, modelos LLM, memoria, tools, embeddings, vector store, document loaders e splitters. Carregue ANTES de montar os steps de IA. A mecanica compartilhada (trigger, stop, auth, versao, publish) e delegada à skill `build-flow`.
disable-model-invocation: false
---

# Construir Fluxo de Agente de IA na APIPASS

Fluxos de agente tem uma topologia **diferente** da cadeia linear de um fluxo comum. Este guia cobre SO o que e
especifico de agente. Para o resto (autenticacao, trigger, stop/`responses`/OAS, contadores, posicoes,
save → version → publish, autorizacoes por referencia), siga a skill `build-flow` e
a skill `apipass-patterns`. A anatomia de cada acao de IA esta na skill `apipass-agent-actions`.

## 0. Quando usar esta skill
- **Agente de IA** (decide, usa tools/memoria, base de conhecimento) → esta skill (`.service.ai.AiAgent`).
- **Completion simples** ("chame o ChatGPT para gerar/classificar X", sem tools) → passo linear `CHATGPT_CREATE_COMPLETION` na `build-flow` comum. NAO precisa de agente.
- **Fluxo de integracao comum** (sem IA) → a skill `build-flow`.

## 1. O conceito central: hub-and-spoke
O agente e um **hub**. Modelo, memoria e tools sao **satelites** que NAO entram na cadeia `nextSteps` —
eles "penduram" no agente por campos de id (`*RouteConfigId`) e ficam posicionados ABAIXO dele no canvas.

```
trigger → [ … pre-processamento … ] → AGENTE (a0) → a999
                                          │  (ligacoes por *RouteConfigId, sem nextSteps)
                          ┌───────────────┼───────────────┐
                       modelo (a1)     memoria (a2)     tool(s) (a3…)
                                                          │ (se for retriever RAG)
                                                      embedding (a4)
```

Apenas o agente participa do `nextSteps` (vem do pre-processamento, vai pro stop). Os satelites se ligam assim
(detalhe e shape de `inputData` em `apipass-agent-actions`):

| De → Para | Campo no pai | Back-ref no filho |
|---|---|---|
| Agente → Modelo (1) | `llmModelRouteConfigId` | `aiAgentRouteConfigId` |
| Agente → Memoria (1, opcional) | `memoryRouteConfigId` | `aiAgentRouteConfigId` |
| Agente → Tools (N) | `toolRouteConfigs: [{ id, state: "LINKED" }]` | `aiAgentRouteConfigId` (opcional) |
| Retriever → Embedding | `embeddingModelRouteConfigId` (em `inputData`) | `vectorStoreRouteConfigId` |
| Ingestor → Loader → Splitter | `documentLoaderRouteConfigId` / `documentSplitterRouteConfigId` (em `inputData`) | `vectorStoreRouteConfigId` / `documentLoaderRouteConfigId` |

## 2. Regras que mudam em relacao ao fluxo comum
- **Saida do agente via `.response`**: leia `{{$.a0.response}}` no stop/interpolacoes — NAO `.body`. (Satelites — modelo, memoria, embedding, loader, splitter — se ligam via `*RouteConfigId` e nao tem saida referenciada por interpolacao; a excecao e `CHATGPT_CREATE_COMPLETION`, passo linear fora do agente, que usa `.body` como qualquer step HTTP.)
- **Satelites fora do `nextSteps`**: se voce ligar modelo/memoria/tool por `nextSteps`, o designer quebra e o agente aparece "sem modelo". O vinculo e SO por `*RouteConfigId`.
- **`endpointDefinitions` faz o designer DESENHAR as arestas** (o `*RouteConfigId` faz EXECUTAR — sozinho NAO renderiza). Hub e ingestor precisam de `endpointDefinitions.bottomEndpoints` (as portas de saida); cada satelite precisa de `endpointDefinitions.targetPosition: "Top"`. **Sem isso o canvas fica quebrado / "sem modelo" mesmo com a execucao funcionando** — e a falha de render mais comum em fluxos com tool/embedding (um agente so-com-modelo as vezes renderiza sem, mas multi-satelite nao). Shapes exatos por no em `apipass-agent-actions`.
- **`label` de porta = chave i18n REAL ou texto literal**: portas do agente usam `AI_AGENT.MODEL`/`.MEMORY`/`.TOOLS`; loader usa `DOCUMENT_LOADER.TEXT_SPLITTER`. Para portas sem chave conhecida (ex. embedding de vector store) use texto literal (`"Embedding"`) — uma chave i18n inexistente aparece **crua** no canvas.
- **Ligacoes simetricas**: todo forward (`llmModelRouteConfigId`) tem um back-ref (`aiAgentRouteConfigId`). Mantenha os dois lados.
- **`toolRouteConfigs` deduplicado**: uma entrada por tool (o JSON exportado as vezes repete ids).
- **Tools dinamicas**: parametros que o LLM preenche usam `{{$fromAI('nome','descricao','tipo')}}` no `inputData` da tool; o `label` da tool e o nome que o LLM ve.
- **Posicoes**: o agente e `nodeSize: "large"`; os satelites ficam ABAIXO (mesmo `positionX` aproximado, `positionY` ~210-500 maior). Todo step precisa de `positionX/Y` (ver `build-flow`).

## 3. Receita A — Agente conversacional / analitico (com tools)
1. Trigger (REST para chatbot/webhook; ver `build-flow`). Pre-processamento opcional (ler arquivo, etc.).
2. Agente `.service.ai.AiAgent`: `systemMessage` (instrucoes), `userMessage` (ex. `{{$.trigger.body.text}}`), `nextSteps` → `a999`.
3. Modelo (`OPENAI`/`ANTHROPIC`/…): `inputData.modelName` etc.; ligue via `llmModelRouteConfigId`/`aiAgentRouteConfigId`.
4. Memoria (`SIMPLE_MEMORY`) se for multi-turno: `memoryRouteConfigId`/`aiAgentRouteConfigId`.
5. Tools: cada acao (SQL/HTTP/custom/retriever) entra em `toolRouteConfigs`; use `$fromAI(...)` nos parametros que o LLM decide.
6. Stop lendo `{{$.a0.response}}` (com `responses[]` + `oas` — ver `build-flow`/`apipass-patterns`).

## 4. Receita B — Agente com base de conhecimento (RAG retrieval)
Igual a Receita A, com uma **tool retriever** de vector store:
- Tool `MONGODB_READ_DOCUMENT` em `toolRouteConfigs`, com `inputData.embeddingModelRouteConfigId` → step de embedding.
- Embedding (`OPENAI_EMBEDDING`…) com back-ref `vectorStoreRouteConfigId` apontando para o retriever.
- A base precisa estar populada — veja a Receita C (normalmente um fluxo separado de ingestao).

## 5. Receita C — Pipeline de ingestao para vector store (popular a base)
Fluxo (frequentemente um child flow / agendado) que indexa documentos. Cadeia linear ate o ingestor:
1. (Opcional) limpar a colecao (`MONGODB_REMOVE`) → listar arquivos (`AFS_LIST_FILES`/`LIST_FILES`) → `LoopCanvas` por arquivo (ver loop em `build-flow`).
2. Dentro do loop: baixar/identificar o arquivo, depois o **ingestor** `MONGODB_INSERT_DOCUMENT` (`coreRouteType: "AI_VECTOR_STORE_INGESTOR"`).
3. O ingestor amarra os satelites por `inputData`: `embeddingModelRouteConfigId` → embedding; `documentLoaderRouteConfigId` → `FILE_DOCUMENT_LOADER`; e o loader aponta `documentSplitterRouteConfigId` → `DOCUMENT_SPLITTER_BY_PARAGRAPH`/`_WORD`/`_CHARACTER`. Back-refs simetricos (`vectorStoreRouteConfigId`, `documentLoaderRouteConfigId`).
   - **O splitter e OBRIGATORIO** — todo `FILE_DOCUMENT_LOADER`/`URL_DOCUMENT_LOADER` precisa de um splitter ligado (nao e opcional). Sem ele a ingestao fica incompleta.
   - **Ingerir TEXTO PURO (sem arquivo)**: nao existe loader de string. Grave o texto com `WRITE_FILE` (`coreRouteType: "WRITE_FILE_UTILITY"`; saida em `{{$.aX.filename}}`) e aponte o `FILE_DOCUMENT_LOADER.filePath` para esse arquivo com `documentType: "TEXT"`. Padrao util tambem para indexar resolucao de chamado vinda de webhook.

## 6. Construir, validar, publicar (delegado)
Pesquise o catalogo de IA com `list_actions(group)` e confirme shapes com `get_action_struct(id)` ou lendo um fluxo
existente (`get_flow_development`) — nunca invente campos.

> **Caveat de descoberta:** `list_actions` pode **truncar** (~40 de N) e **nao aplicar o filtro `group`** — os grupos de IA (`AI`/`VECTOR_STORE`/`CHAT_MEMORY`) podem nem aparecer. Para os shapes de IA, prefira **ler um fluxo real** (`list_flows(projectId)` → `get_flow_development(flowId)`) ou `get_action(groupId, id)` com o id conhecido. A descoberta dependente de MCP deve ficar **na thread principal**: subagentes (Explore/researcher) rodam em sessao de auth separada e caem em `login_necessario` — eles nao compartilham o token.

Depois siga o ciclo padrao de `build-flow`:
`create_flow` → montar steps → `save_flow_development` (valida automatico) → `create_version` → `publish_flow`
(tudo com `confirm: true` e confirmacao do usuario). Autorizacoes (`authId`/`authProvider`) por provider via `list_authorizations`.

## Principios
- A topologia e hub-and-spoke: satelites NUNCA na cadeia `nextSteps`, so por `*RouteConfigId` (simetrico).
- Saida do agente sempre por `.response`; satelites (modelo/memoria/embedding/loader/splitter) nao tem saida interpolavel; `CHATGPT_CREATE_COMPLETION` (fora do agente) usa `.body`.
- Nunca invente `type`/`actionId`/campos de `inputData` — pesquise (`apipass-agent-actions`, `get_action_struct`, fluxo real).
- Credenciais sempre por referencia; nunca embuta chave de provider de IA no step.

## Skills relacionadas
- skill `apipass-agent-actions` — anatomia das acoes de IA e do agente (referencia)
- skill `build-flow` — mecanica compartilhada (trigger, stop, auth, save/version/publish)
- skill `apipass-patterns` — estrutura do fluxo, contadores, publicacao, OAS
- skill `apipass-gotchas` — erros comuns e debug de execucao
