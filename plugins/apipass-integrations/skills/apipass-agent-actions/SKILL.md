---
name: apipass-agent-actions
description: Referencia do catalogo de acoes de IA da APIPASS (Agent Builder) e a anatomia do step de Agente. Carregue ao montar um fluxo com `.service.ai.AiAgent`, modelo LLM, memoria, tools, embeddings, vector store, document loader ou splitter.
disable-model-invocation: false
---

# Catalogo de Acoes de IA e Anatomia do Agente

A familia de IA da APIPASS (Agent Builder) tem uma topologia **hub-and-spoke**: o step `.service.ai.AiAgent`
e o hub; modelo, memoria e tools sao **satelites** que NAO entram na cadeia `nextSteps` — eles se ligam ao
agente por campos `*RouteConfigId`. O processo de montagem fica em `/apipass-integrations:build-agent-flow`;
este arquivo e a **referencia** de cada acao (type/actionId, papel, campo de ligacao, auth, `inputData`).

> Descubra/confirme os types e schemas pelo catalogo, nunca invente: `list_actions(group)` lista a familia,
> `get_action_struct(id)` traz o schema de `inputData`, e `get_flow_development(flowId)` mostra um fluxo real.
> Grupos de IA: `LANGUAGE_MODELS`, `CHAT_MEMORY`, `VECTOR_STORE`, `EMBEDDING`, `DOCUMENT_LOADER`,
> `DOCUMENT_SPLITTER`, `CHATGPT` (+ o tipo core `.service.ai.AiAgent`).
>
> **Caveat:** `list_actions` pode **truncar** (~40 de N) e **nao aplicar `group`** — os grupos de IA podem nao
> aparecer na listagem. Para descobrir/confirmar shapes de IA, leia um **fluxo real**
> (`list_flows(projectId)` → `get_flow_development(flowId)`) ou use `get_action(groupId, id)` com o id conhecido.

## Renderizacao no canvas: `endpointDefinitions` (gotcha critico)
Os campos `*RouteConfigId` fazem o fluxo **EXECUTAR**, mas o designer so **DESENHA** as arestas de configuracao se
cada no tiver `endpointDefinitions`. Sem isso o canvas fica quebrado / agente "sem modelo" (mesmo executando ok).
- **Hub (agente) e ingestor**: `endpointDefinitions: { hasSource: true, targetPosition: "Left", bottomEndpoints: [...] }` — as portas de saida (modelo/memoria/tools, ou embedding/loader).
- **Satelites** (modelo, memoria, embedding, splitter, retriever): `endpointDefinitions: { targetPosition: "Top" }` (mais `bottomEndpoints` proprio se tiverem sub-no, ex. retriever→embedding, loader→splitter).
- **`label` de porta**: use chave i18n REAL (`AI_AGENT.MODEL`/`.MEMORY`/`.TOOLS`, `DOCUMENT_LOADER.TEXT_SPLITTER`) ou texto literal. Uma chave inventada (ex. `VECTOR_STORE.EMBEDDING`) aparece **crua** no canvas — nesse caso prefira literal (`"Embedding"`).
- Os shapes canonicos de cada `endpointDefinitions` vem do proprio catalogo (`list_actions` traz `endpointDefinitions` por acao para os grupos de IA) — copie de la quando disponivel.

## Regra de saida (gotcha critico)
- **A saida do AGENTE e lida via `.response`**: `{{$.a0.response}}` — NAO `.body`. (Vale no stop e em interpolacoes.)
- **Satelites (embedding, vector store, loader, splitter) nao tem saida referenciada por interpolacao**: eles se ligam ao hub via `*RouteConfigId`, fora da cadeia `nextSteps`, e nao geram output consumido por outros steps.
- A unica acao de IA fora do agente que produz saida usada downstream e o `CHATGPT_CREATE_COMPLETION` (completion simples, nao-agentica) — e um step baseado em HTTP por baixo, entao usa `.body` como qualquer step HTTP/NodeJS. Nao ha uma regra universal de `.body` para todo step (ver `apipass-actions`/`build-flow`: actions de catalogo com shape proprio, ex. `SQL_QUERY`, ou o `.data` do `LoopCanvas`, nao usam `.body`).

## Mapa de ligacoes (`*RouteConfigId`)
Os satelites se conectam por campos de id (sem `nextSteps`). As ligacoes sao **simetricas** (forward no pai, back-ref no filho):

| De → Para | Campo no pai | Back-ref no filho | Onde mora |
|---|---|---|---|
| Agente → Modelo | `llmModelRouteConfigId` | `aiAgentRouteConfigId` | topo do step |
| Agente → Memoria | `memoryRouteConfigId` | `aiAgentRouteConfigId` | topo do step |
| Agente → Tools (N) | `toolRouteConfigs: [{ id, state: "LINKED" }]` | `aiAgentRouteConfigId` (opcional na tool) | topo do step |
| Vector store → Embedding | `embeddingModelRouteConfigId` | `vectorStoreRouteConfigId` | em `inputData` (pai); topo (filho) |
| Ingestor → Document loader | `documentLoaderRouteConfigId` | `vectorStoreRouteConfigId` | em `inputData` (pai); topo (filho) |
| Loader → Splitter | `documentSplitterRouteConfigId` | `documentLoaderRouteConfigId` | em `inputData` (pai); topo (filho) |

> `toolRouteConfigs` pode vir com ids repetidos no JSON exportado — **deduplique** para uma entrada por tool ao montar.
> O back-ref `aiAgentRouteConfigId` na tool foi observado presente (retriever de vector store) e ausente (tool SQL);
> a lista `toolRouteConfigs` do agente e a fonte autoritativa do vinculo.

## `.service.ai.AiAgent` — o hub
- `type: ".service.ai.AiAgent"`, `image: "aiagent"`, `nodeSize: "large"`, `authProvider: ""` (a auth fica no modelo/tools).
- `systemMessage` (string): o system prompt / instrucoes do agente.
- `userMessage` (string): a mensagem do usuario, normalmente interpolada — ex. `"{{$.trigger.body.text}}"` ou `"Analise: {{$.a6.data.sheet[0].data}}"`.
- `llmModelRouteConfigId` (obrigatorio) → id do step de modelo. `memoryRouteConfigId` (opcional) → memoria. `toolRouteConfigs[]` (opcional) → tools.
- `endpointDefinitions.bottomEndpoints`: `modelEndpoint` (max 1), `memoryEndpoint` (max 1), `toolsEndpoint` (max -1 = ilimitado). `files: []`.
- Vai na cadeia principal: `trigger → … → agente → a999`. O `nextSteps` do agente aponta para o proximo passo/stop.
```json
{
  "id": "a0", "label": "Agente de IA", "type": ".service.ai.AiAgent",
  "image": "aiagent", "nodeSize": "large", "authProvider": "",
  "systemMessage": "Voce e um assistente que ...",
  "userMessage": "{{$.trigger.body.text}}",
  "llmModelRouteConfigId": "a1", "memoryRouteConfigId": "a2",
  "toolRouteConfigs": [{ "id": "a3", "state": "LINKED" }],
  "endpointDefinitions": { "hasSource": true, "targetPosition": "Left", "bottomEndpoints": [
    { "label": "AI_AGENT.MODEL", "name": "modelEndpoint", "position": [0.2,0.95,0,1], "maxConnections": 1 },
    { "label": "AI_AGENT.MEMORY", "name": "memoryEndpoint", "position": [0.5,0.95,0,1], "maxConnections": 1 },
    { "label": "AI_AGENT.TOOLS", "name": "toolsEndpoint", "position": [0.8,0.95,0,1], "maxConnections": -1 } ] },
  "files": [], "mappingAttributes": {}, "customAttributes": [], "logEnabled": true, "valid": true,
  "nextSteps": [{ "id": "a999", "type": ".StopV2Step", "sourceUUID": "integration-step-uuid-sourceEndpoint-a0", "targetUUID": "integration-step-uuid-targetEndpoint-a999" }]
}
```

## Modelos LLM — grupo `LANGUAGE_MODELS`
Step `.service.actions.Action` com `actionId` do provider; `authorization`/`authProvider` = o provider; back-ref `aiAgentRouteConfigId`.
- `actionId`: `OPENAI` | `ANTHROPIC` | `AWS_BEDROCK` | `GOOGLE_GEMINI`. `image`: URL S3 (de `list_actions`).
- **OpenAI** `inputData`: `modelName` (ex. `gpt-5`, `gpt-4o`, `o3`…), `responseFormat` (`JSON`|`TEXT`), `temperature`, `maxTokens`, `maxRetries`, `frequencyPenalty`, `presencePenalty`, `topP`, `timeout`.
- **Anthropic** `inputData`: `modelName` (`claude-opus-4-1-20250805`, `claude-sonnet-4-20250514`, `claude-3-5-haiku-20241022`…), `maxTokens`, `maxRetries`, `temperature`, `topP`, `topK`, `sendThinking` (`true`|`false`). Auth `ANTHROPIC`.
- **AWS Bedrock** / **Google Gemini**: confirme `modelName` e campos via `get_action_struct`.
```json
{
  "id": "a1", "label": "Modelo OpenAI", "type": ".service.actions.Action", "actionId": "OPENAI",
  "authProvider": "OPENAI", "authorization": "OPENAI", "authId": "<id de list_authorizations>",
  "aiAgentRouteConfigId": "a0", "additionalConfiguration": true, "failOnError": true,
  "image": "https://s3.amazonaws.com/flow-manager-api-prd/actions/logo/OPENAI.png",
  "endpointDefinitions": { "targetPosition": "Top" }, "nodeSize": "small",
  "inputData": { "modelName": "gpt-5", "responseFormat": "JSON", "timeout": 3000000 },
  "mappingAttributes": {}, "customAttributes": [], "logEnabled": true, "valid": true
}
```

## Memoria — grupo `CHAT_MEMORY`
- `actionId: "SIMPLE_MEMORY"` (sem auth). Back-ref `aiAgentRouteConfigId`. `inputData`: `memoryId` (default aleatorio), `maxMessages` (default 10).
- Use para conversas multi-turno (chatbot). Para uma analise single-shot, a memoria e dispensavel.

## Tools — qualquer acao ligada via `toolRouteConfigs`
**Uma tool e uma acao normal** (catalogo, HTTP, SQL, custom action ou retriever de vector store) que o agente pode chamar.
Para virar tool: (1) entre em `toolRouteConfigs[]` do agente; (2) o **`label` da tool** e o nome que o LLM ve (use nomes descritivos, ex. `banco_de_dados_torre_controle`); (3) parametros que o LLM deve preencher usam a funcao **`$fromAI`**.

### `{{$fromAI('nome', 'descricao', 'tipo')}}` — parametros preenchidos pelo LLM
Em qualquer campo de `inputData` da tool, declare um argumento que o modelo deve fornecer em tempo de execucao:
```json
{
  "id": "a4", "label": "banco_de_dados_torre_controle", "type": ".service.actions.Action",
  "actionId": "SQL_QUERY", "coreRouteType": "SQL", "authorization": "DATABASE", "authId": "<id>",
  "failOnError": true, "additionalConfiguration": true, "nextSteps": [],
  "inputData": {
    "query": "SELECT * FROM VIEW_X WHERE [CLIENTE] IN {{$fromAI('clientes', 'Lista de clientes no formato IN de SQL incluindo ( )', 'string')}}"
  },
  "mappingAttributes": {}, "logEnabled": true, "valid": true
}
```
Tools NAO tem `nextSteps` para a cadeia principal (`nextSteps: []`); o vinculo e so o `toolRouteConfigs` + (opcional) `aiAgentRouteConfigId`. A saida da tool e consumida internamente pelo agente.

## RAG — Vector store, Embedding, Document loader, Splitter
Para um agente com base de conhecimento (RAG retrieval) e/ou para um pipeline de ingestao.

### Vector store — grupo `VECTOR_STORE`
- `MONGODB_READ_DOCUMENT` — **retriever** (tool de busca semantica). Como tool, entra em `toolRouteConfigs` e tem `embeddingEndpoint` proprio. `inputData`: `databaseName`, `collectionName`, `indexName`, `maxResults`, + `embeddingModelRouteConfigId` (→ embedding). Auth `MONGODB`. `endpointDefinitions: { "hasSource": true, "targetPosition": "Top", "bottomEndpoints": [{ "name": "embeddingEndpoint", "label": "Embedding", "position": [0.5,0.95,0,1], "maxConnections": 1 }] }`. ⚠️ o `indexName`/dimensao do retriever tem de casar com o usado na ingestao.
- `MONGODB_INSERT_DOCUMENT` — **ingestor** (`coreRouteType: "AI_VECTOR_STORE_INGESTOR"`). `inputData`: `databaseName`, `collectionName`, `vectorIndexName`, + `embeddingModelRouteConfigId` (→ embedding) e `documentLoaderRouteConfigId` (→ loader). Entra na cadeia/loop como passo normal.

### Embedding — grupo `EMBEDDING`
- `OPENAI_EMBEDDING` | `AWS_BEDROCK_EMBEDDING` | `GOOGLE_GEMINI_EMBEDDING`. Back-ref `vectorStoreRouteConfigId`. `inputData` (OpenAI): `modelName` (`text-embedding-3-small`…), `dimensions`, `batchSize`, `timeout`, `stripNewLines`. Auth do provider.

### Document loader — grupo `DOCUMENT_LOADER`
- `FILE_DOCUMENT_LOADER` | `URL_DOCUMENT_LOADER`. Back-ref `vectorStoreRouteConfigId`; aponta para o splitter via `documentSplitterRouteConfigId` (em `inputData`). `inputData` (file): `filePath`, `documentType` (`TEXT`|`PDF`|`YAML`|`MARKDOWN`|`OFFICE`).
- Porta canonica para o splitter (em `endpointDefinitions.bottomEndpoints`): `{ "name": "textSplitterEndpoint", "label": "DOCUMENT_LOADER.TEXT_SPLITTER", "position": "Bottom", "maxConnections": 1 }`.

### Document splitter — grupo `DOCUMENT_SPLITTER`
- `DOCUMENT_SPLITTER_BY_WORD` | `_BY_PARAGRAPH` | `_BY_CHARACTER`. Back-ref `documentLoaderRouteConfigId`. `inputData`: `maxSegmentSizeInChars`, `maxOverlapSizeInChars`. `endpointDefinitions: { "targetPosition": "Top" }`.
- **OBRIGATORIO**: todo loader precisa de um splitter ligado — nao e opcional.

Cadeia de ingestao (ingestor amarra tudo): `ingestor → embedding` (`embeddingModelRouteConfigId`) e `ingestor → loader → splitter` (`documentLoaderRouteConfigId` → `documentSplitterRouteConfigId`). **Inclua `endpointDefinitions` em todos** para o canvas desenhar:
```json
// ingestor (cadeia principal) — duas portas inferiores
{ "id": "a1", "actionId": "MONGODB_INSERT_DOCUMENT", "type": ".service.actions.Action",
  "coreRouteType": "AI_VECTOR_STORE_INGESTOR", "nodeSize": "large", "authProvider": "MONGODB", "authId": "<id>",
  "endpointDefinitions": { "hasSource": true, "targetPosition": "Left", "bottomEndpoints": [
    { "name": "embeddingEndpoint", "label": "Embedding", "position": [0.3,0.95,0,1], "maxConnections": 1 },
    { "name": "documentEndpoint", "label": "Documento", "position": [0.7,0.95,0,1], "maxConnections": 1 } ] },
  "inputData": { "embeddingModelRouteConfigId": "a3", "documentLoaderRouteConfigId": "a2",
    "databaseName": "...", "collectionName": "...", "vectorIndexName": "..." } }
// embedding (satelite) — entra por cima
{ "id": "a3", "actionId": "OPENAI_EMBEDDING", "type": ".service.actions.Action", "authProvider": "OPENAI", "authId": "<id>",
  "vectorStoreRouteConfigId": "a1", "endpointDefinitions": { "targetPosition": "Top" },
  "inputData": { "modelName": "text-embedding-3-small", "dimensions": "1536", "batchSize": 256, "stripNewLines": "false" } }
// loader (satelite) — entra por cima, porta inferior pro splitter
{ "id": "a2", "actionId": "FILE_DOCUMENT_LOADER", "type": ".service.actions.Action", "authProvider": "",
  "vectorStoreRouteConfigId": "a1",
  "endpointDefinitions": { "targetPosition": "Top", "bottomEndpoints": [
    { "name": "textSplitterEndpoint", "label": "DOCUMENT_LOADER.TEXT_SPLITTER", "position": "Bottom", "maxConnections": 1 } ] },
  "inputData": { "filePath": "{{$.a0.filename}}", "documentType": "TEXT", "documentSplitterRouteConfigId": "a5" } }
// splitter (satelite do loader) — OBRIGATORIO
{ "id": "a5", "actionId": "DOCUMENT_SPLITTER_BY_PARAGRAPH", "type": ".service.actions.Action", "authProvider": "",
  "documentLoaderRouteConfigId": "a2", "endpointDefinitions": { "targetPosition": "Top" },
  "inputData": { "maxSegmentSizeInChars": 800, "maxOverlapSizeInChars": 80 } }
```
> Posicione os satelites com os X alinhados a porta que os alimenta (embedding sob `embeddingEndpoint`, loader sob `documentEndpoint`) para as arestas nao se cruzarem.

## `CHATGPT_CREATE_COMPLETION` ≠ Agente
Grupo `CHATGPT`: uma **completion simples** (NAO-agentica) — um passo linear comum, sem tools/memoria, saida via `.body`.
Use quando o pedido e "chame o ChatGPT para gerar/classificar X" sem necessidade de raciocinio com ferramentas.
Para agente que decide e usa tools/base de conhecimento, use `.service.ai.AiAgent`.

## Autorizacoes
Modelos e vector store autenticam por **referencia** (`authProvider`/`authId` de `list_authorizations`), nunca chave embutida.
Providers comuns: `OPENAI`, `ANTHROPIC`, `AWS_BEDROCK`/`AWS`, `GOOGLE_GEMINI`, `MONGODB`, `DATABASE` (tools SQL).
Memoria simples e splitters geralmente nao autenticam (`authProvider: ""`).
