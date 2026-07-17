---
name: apipass-patterns
description: 'Estrutura de um fluxo da APIPASS — montagem incremental, contadores lastGeneratedStepId/lastGeneratedLoopId, leitura da estrutura, versoes e publicacao (environment).'
disable-model-invocation: false
---

# Padroes de Fluxo APIPASS

## Montagem incremental
```
create_flow(name, projectId, confirm: true)   -> flowId
save_flow_development(id: flowId, steps: [...], lastGeneratedStepId, lastGeneratedLoopId, logEnabled, confirm: true)
```
Para alterar um fluxo existente: `get_flow_development(flowId)` -> ajuste os steps -> `save_flow_development(...)`.

## Contadores (regra critica)
- `lastGeneratedStepId` = **id numerico do ultimo step gerado + 1** (NAO e apenas ">= o maior id"). Ex.: se o maior step gerado e `a0`, entao `lastGeneratedStepId: 1`.
- **O step de fim e SENTINELA**: `a999` (`.StopV2Step`/`.StopStep`) usa um id fixo convencional e **NAO conta** para o calculo. Ignore-o ao achar o maior id gerado.
- Ao adicionar um step novo, use o valor atual de `lastGeneratedStepId` como `id` numerico do novo step e incremente o contador.
- `lastGeneratedLoopId`: idem para loops. >= 0.

## Ler a estrutura
- `get_flow_development(flowId)` — os steps (use para aprender shapes e para editar).
- `get_flow_info(flowId)` — metadados do fluxo.
- `export_flow_json(flowId)` — exportacao completa em JSON.
- `list_flow_versions(flowId)` / `get_version(versionId)` — historico de versoes.

## Publicacao (environment)
Publicar exige `environmentId` + `historyId`. Descubra-os primeiro:
- `list_environments()` — environments (ambientes) da conta.
- `get_published_environments_for_flow(flowId)` — onde o fluxo ja esta publicado.
Depois:
- `publish_flow(environmentId, historyId, confirm: true)` — torna a versao ativa no environment (efeito real).
- `unpublish_flow(environmentId, historyId, confirm: true)` — despublica.

> **Pre-requisito do stop para publicar:** o step de fim (`.StopV2Step`) precisa ter o array `responses` (ao menos a resposta `Default` 200). O `save_flow_development`/`create_version` aceitam o stop sem ele, mas `publish_flow` falha com HTTP 400 (`reading 'map'`). Shape minimo:
> ```json
> "responses": [
>   { "description": "Default", "default": true, "responseData": { "status": "200" } },
>   { "description": "Error", "responseData": { "status": "400", "contentType": "application/json" },
>     "groups": [ { "rules": [ { "input": "{{$.flowExecution.status}}", "condition": "TEXT_DOES_NOT_MATCH", "expected": "OK" } ] } ] }
> ]
> ```

---

## Documentacao OpenAPI (OAS) — fluxos com RestTrigger

Fluxos com trigger REST expõem um Swagger publico gerado automaticamente pela APIPASS. A documentacao e composta por dois campos:

1. **`jsonSchema` na RestTrigger** — documenta o body de entrada (requisicao).
2. **`oas` em cada item de `responses[]` no StopV2Step** — documenta cada resposta possivel (201, 400, 422, etc.).

Sempre preencha o campo `oas` ao criar ou editar fluxos com RestTrigger.

### Shape completo de um item de `responses[]`

```json
{
  "description": "Descricao da resposta",
  "default": true,
  "responseData": {
    "status": "201",
    "contentType": "application/json",
    "headers": [],
    "body": "{{$.aX.message}}"
  },
  "groups": [],
  "oas": {
    "mediaType": "application/json",
    "jsonSchema": "{\n  \"type\": \"object\",\n  \"properties\": {\n    \"sucesso\": { \"type\": \"boolean\", \"example\": true }\n  }\n}",
    "headers": []
  }
}
```

- **`default: true` + `groups: []`** — resposta padrao (fallback, sem condicao). Exatamente **uma** entrada com esse padrao.
- **`groups`** — regras de condicao que ativam aquela resposta. Vazio apenas na `default`.
- **`oas.jsonSchema`** — **string** JSON (serializada, igual ao `jsonSchema` da RestTrigger). Nunca objeto.

### Exemplo com 3 respostas (201, 400, 422)

```json
"responses": [
  {
    "description": "Default",
    "default": true,
    "responseData": { "status": "201", "contentType": "application/json", "headers": [], "body": "{{$.a8.message}}" },
    "groups": [],
    "oas": {
      "mediaType": "application/json",
      "jsonSchema": "{\n  \"type\": \"object\",\n  \"properties\": {\n    \"sucesso\": { \"type\": \"boolean\", \"example\": true },\n    \"id\": { \"type\": \"string\", \"description\": \"Id do registro criado.\", \"example\": \"07kHZ000009tholYAA.\" }\n  }\n}",
      "headers": []
    }
  },
  {
    "description": "Requisicao invalida",
    "responseData": { "status": "400", "contentType": "application/json", "headers": [], "body": "{{$.a3.message}}" },
    "groups": [ { "rules": [ { "input": "{{$.a3.message}}", "condition": "INPUT_IS_NOT_NULL", "expected": "" } ] } ],
    "oas": {
      "mediaType": "application/json",
      "jsonSchema": "{\n  \"type\": \"object\",\n  \"properties\": {\n    \"sucesso\": { \"type\": \"boolean\", \"example\": false },\n    \"mensagem\": { \"type\": \"string\", \"example\": \"Erro ao validar requisicao.\" },\n    \"erros\": { \"type\": \"array\", \"items\": { \"type\": \"string\" } }\n  }\n}",
      "headers": []
    }
  },
  {
    "description": "Erro ao processar",
    "responseData": { "status": "422", "contentType": "application/json", "headers": [], "body": "{{$.a9.message}}" },
    "groups": [ { "rules": [ { "input": "{{$.flowExecution.status}}", "condition": "TEXT_DOES_NOT_MATCH", "expected": "OK" } ] } ],
    "oas": {
      "mediaType": "application/json",
      "jsonSchema": "{\n  \"type\": \"object\",\n  \"properties\": {\n    \"sucesso\": { \"type\": \"boolean\", \"example\": false },\n    \"mensagem\": { \"type\": \"string\", \"example\": \"Erro ao processar.\" },\n    \"erros\": { \"type\": \"array\", \"items\": { \"type\": \"object\" } }\n  }\n}",
      "headers": []
    }
  }
]
```

> **Regra de condicao para respostas de erro:** use `INPUT_IS_NOT_NULL` no logger de erro para respostas de validacao (400), e `TEXT_DOES_NOT_MATCH "OK"` no `{{$.flowExecution.status}}` para erros de processamento (422/500). A resposta `default` cobre o caminho feliz.

## Teste de fluxo
- `list_test_flows(flowId)` — cenarios de teste existentes.
- `create_test_flow(name, flowId, environmentId, payload, confirm: true)` — cria um cenario.
- `run_test_flow(flowId, environmentId, payload, confirm: true)` — **executa** o fluxo com o payload no environment (efeito real: cria execucao e roda os passos). Sempre confirme com o usuario, nomeando o environment e o que sera disparado. Depois, investigue o resultado pelos logs (ver `/apipass-integrations:apipass-gotchas`).

## Campos derivados no save (nao setar a mao)
O `save_flow_development` preenche/deriva automaticamente alguns campos — o builder NAO precisa enviar:
- `usedSteps` — dependencias entre steps, derivadas das interpolacoes `{{$.<id>}}` (confirma que as referencias resolveram).
- Defaults seguros: `doc`, `timeout`, `mappingAttributesRootArray`, `httpProtocolVersion`/`httpTlsVersion`, `trigger: 0`.
Envie apenas os campos de intencao; releia com `get_flow_development` para conferir o que o engine completou. Ao comparar/diferenciar fluxos (ex. harness), normalize esses campos — senao geram falso-positivo de divergencia.

## Validacao no save
O `save_flow_development` valida a estrutura antes de enviar. Se vier erro, leia a lista e corrija; nada e salvo ate passar.

**Sucesso retorna vazio** (sem payload de confirmacao) — isso NAO e falha. Confirme o resultado relendo com `get_flow_development(flowId)`.

---

## AMS — Apipass Message System (filas assincronas)

O AMS desacopla fluxos via filas: um fluxo **publica** uma mensagem; outro fluxo a **consome** assincronamente.

### Padrao master/subfluxo com AMS
```
Fluxo master (trigger HTTP) → valida → monta payload → AMS_SEND_MESSAGE → retorna 200 ao caller
Subfluxo consumidor (trigger AMS) → processa a mensagem da fila → encerra
```
O master NUNCA espera o subfluxo — retorna imediatamente apos publicar na fila. O subfluxo e disparado automaticamente quando a mensagem chega.

### Nome de fila — convencao obrigatoria
Use variaveis de stage para que o nome mude automaticamente entre ambientes:
```
{{$.stage.name}}-ams-{dominio}-{acao}
Ex.: {{$.stage.name}}-ams-inbound-demanda-atualizar-agendamento-trizy-multi
→ dev-ams-inbound-...  (stage dev)
→ prod-ams-inbound-... (stage prod)
```
**NUNCA hardcode o nome da fila** — use `{{$.stage.name}}-` como prefixo.

### Trigger AMS (subfluxo consumidor)
```json
{
  "id": "trigger",
  "trigger": true,
  "label": "Início",
  "image": "ams",
  "nodeSize": "small",
  "type": ".trigger.ams.TriggerAMSConsumeMessage",
  "queueName": "{{$.stage.name}}-ams-nome-da-fila",
  "concurrentConsumers": 10,
  "deleteStrategy": "IMMEDIATELY",
  "defaultVisibilityTimeout": null,
  "logEnabled": true,
  "previousSteps": [],
  "nextSteps": [{ "id": "a0", "type": "...", "sourceUUID": "integration-step-uuid-sourceEndpoint-trigger", "targetUUID": "integration-step-uuid-targetEndpoint-a0" }]
}
```
- `concurrentConsumers`: numero de consumidores paralelos (tipicamente 5–10).
- `deleteStrategy: "IMMEDIATELY"`: remove a mensagem da fila assim que entregue. Usar `"ON_FLOW_SUCCESS"` para retry automatico em caso de falha no processamento — **NAO `"ON_SUCCESS"`** (valor plausivel mas inexistente; o engine aceita no save sem erro, porem a UI nao reconhece o valor ao reabrir o step: o dropdown "Estrategia de remocao da mensagem" aparece vazio e o campo dependente `defaultVisibilityTimeout` tambem aparece vazio, mesmo ja salvo). Ao usar `"ON_FLOW_SUCCESS"`, preencha tambem `defaultVisibilityTimeout` (numero, em segundos) — deve cobrir o tempo maximo de execucao do fluxo (nao o delay de entrega da fila, que e independente e atua so na primeira entrega).

### Step AMS_SEND_MESSAGE (publicar mensagem)
```json
{
  "id": "a5",
  "label": "Publica na fila",
  "type": ".service.actions.Action",
  "actionId": "AMS_SEND_MESSAGE",
  "coreRouteType": "AMS_SEND_MESSAGE",
  "image": "https://s3.amazonaws.com/flow-manager-api-prd/actions/logo/ams.png",
  "additionalConfiguration": true,
  "authProvider": "",
  "logEnabled": true,
  "failOnError": true,
  "inputData": {
    "queueName": "{{$.stage.name}}-ams-nome-da-fila",
    "queueType": "STANDARD",
    "message": "{{$.a4.body}}"
  },
  "nextSteps": [{ "id": "a999", "type": ".StopV2Step", "sourceUUID": "integration-step-uuid-sourceEndpoint-a5", "targetUUID": "integration-step-uuid-targetEndpoint-a999" }]
}
```
- `queueType`: sempre `"STANDARD"`.
- `message`: o payload serializado. Use `"{{$.aN.body}}"` para enviar o output de um step NodeJS inteiro, ou monte um NodeJS antes para formatar o payload exato.
- `failOnError: true` — se a fila nao existir ou a publicacao falhar, o fluxo master deve falhar (nao silenciar).

### Acesso ao payload no subfluxo consumidor
A mensagem chega no trigger do subfluxo como body:
```javascript
// No subfluxo consumidor:
const { campo } = $.trigger.body;
// Ex.: $.trigger.body.trizy.numeroCarga
```

---

## AOS — Apipass Object Store (persistencia MongoDB)

O AOS e o banco de dados nativo da APIPASS, baseado em MongoDB. Permite persistir, buscar e atualizar dados diretamente nos fluxos sem infra externa.

### Autorizacao AOS
O AOS usa um `authProvider` proprio. Descubra o `authId` com `list_authorizations` (filtre por provider `APIPASS_OBJECT_STORE`):
```json
{
  "authProvider": "APIPASS_OBJECT_STORE",
  "authId": "UUID-da-autorizacao-aos"
}
```

### Convencao de banco/colecao
- `database`: use `{{$.stage.name}}` para separar dados por ambiente (dev/prod).
- `collection`: nome semantico da entidade, ex.: `"shipping_settings"`, `"pedidos"`, `"clientes"`.

### AOS_FIND_ONE_BY_QUERY (buscar um documento)
```json
{
  "id": "a2",
  "label": "Buscar registro",
  "type": ".service.actions.Action",
  "actionId": "AOS_FIND_ONE_BY_QUERY",
  "coreRouteType": "MONGODB_FIND_ONE_BY_QUERY",
  "authorization": "APIPASS_OBJECT_STORE",
  "image": "https://s3.amazonaws.com/flow-manager-api-prd/actions/logo/aos.png",
  "additionalConfiguration": true,
  "authProvider": "APIPASS_OBJECT_STORE",
  "authId": "UUID-da-autorizacao-aos",
  "failOnError": false,
  "inputData": {
    "database": "{{$.stage.name}}",
    "collection": "minha_colecao",
    "filter": "{\"_id\": \"{{$.trigger.queryParams.instance_id}}\"}"
  }
}
```
Output: `$.aN.body.document` — o documento encontrado (null se nao existir).

### AOS_UPDATE (atualizar documento)
```json
{
  "id": "a3",
  "label": "Atualizar registro",
  "type": ".service.actions.Action",
  "actionId": "AOS_UPDATE",
  "coreRouteType": "MONGODB_UPDATE",
  "authorization": "APIPASS_OBJECT_STORE",
  "image": "https://s3.amazonaws.com/flow-manager-api-prd/actions/logo/aos.png",
  "additionalConfiguration": true,
  "authProvider": "APIPASS_OBJECT_STORE",
  "authId": "UUID-da-autorizacao-aos",
  "failOnError": false,
  "inputData": {
    "database": "{{$.stage.name}}",
    "collection": "minha_colecao",
    "filter": "{\"_id\": \"{{$.trigger.queryParams.instance_id}}\"}",
    "upsert": false,
    "updateMany": false,
    "query": "{{$.aN.body.queryMongoDB}}"
  }
}
```
- `query`: operador MongoDB, ex.: `{ "$set": { campo: valor } }`. Monte em um NodeJS antes e passe via `"{{$.aN.body.queryMongoDB}}"`.
- `upsert: true` — cria o documento se nao existir.
- Output: `$.aN.body.document.matchedCount`, `modifiedCount`, `upsertedId`.

### AOS_INSERT (inserir documento)
```json
{
  "actionId": "AOS_INSERT",
  "coreRouteType": "MONGODB_INSERT",
  "inputData": {
    "database": "{{$.stage.name}}",
    "collection": "minha_colecao",
    "document": "{{$.aN.body.documentoParaInserir}}"
  }
}
```
- `document`: JSON do documento a inserir. Inclua `_id` customizado se quiser controle do ID (ex.: `instance_id`).

### AOS_DELETE (remover documento)
```json
{
  "actionId": "AOS_DELETE",
  "coreRouteType": "MONGODB_DELETE",
  "inputData": {
    "database": "{{$.stage.name}}",
    "collection": "minha_colecao",
    "filter": "{\"_id\": \"{{$.trigger.body.id}}\"}"
  }
}
```

### Padrao CRUD com AOS (GET/POST/PATCH em um unico fluxo)
O fluxo `9d7844bf` (shipping-settings) mostra o padrao de um endpoint REST que roteia pelo metodo HTTP:
```
Trigger REST (GET/POST/PATCH) → Valida campos → Switch por metodo
  GET  → AOS_FIND_ONE_BY_QUERY → Monta resposta → Stop
  POST → Monta documento       → AOS_INSERT     → Stop
  PATCH→ Monta query $set      → AOS_UPDATE     → re-busca → Stop
```
Campos `_id` geralmente sao o identificador do caller (`instance_id`, `instance_id` do WIX, etc.), nao o ObjectId do Mongo.

### NodeJS para montar query MongoDB ($set)
```javascript
const moment = require("moment");
const updated_at = moment().subtract(3, "hours").format("YYYY-MM-DDTHH:mm:ss[Z]");

const queryMongoDB = {
  "$set": {
    "campo1": $.trigger.body?.data?.campo1,
    "updated_at": updated_at
  }
};

$export(null, { queryMongoDB });
```

---

## Regra critica — `nextSteps` para steps de acao (`.service.actions.Action`)

Quando um `nextSteps` aponta para um step cujo `type` e `.service.actions.Action` (MEMORY_STORE, PROJECT_STORE, LOGGER, AMS_SEND_MESSAGE, AOS_*, etc.), o objeto de link **deve** incluir `coreRouteType` com o mesmo valor do step de destino. Sem esse campo o engine nao consegue resolver a URL do microsservico e a execucao falha com "Method and URL are required, check your flow configuration." — mesmo que o step de destino esteja configurado corretamente.

**Shape correto:**
```json
"nextSteps": [
  {
    "id": "a0",
    "type": ".service.actions.Action",
    "sourceUUID": "integration-step-uuid-sourceEndpoint-trigger",
    "targetUUID": "integration-step-uuid-targetEndpoint-a0",
    "coreRouteType": "MEMORY_STORE_SET"
  }
]
```

> `save_flow_development` e `publish_flow` aceitam o specflow sem esse campo sem reclamar — o erro so aparece em execucao. Para confirmar o shape correto, leia um fluxo funcional existente com `get_flow_development`.
