---
name: build-flow
description: |
  Construir ou modificar fluxos de integracao na APIPASS. Use sempre que o usuario pedir para criar, construir ou alterar um fluxo — "construa um fluxo que...", "crie uma integracao para...", "automatize X", "modifique o fluxo que...".

  Ponto de entrada para TODA construcao/modificacao de fluxo. Carregue ANTES de chamar create_flow / save_flow_development.
disable-model-invocation: false
---

# Construir Fluxo na APIPASS

Siga este processo. Nao pule o planejamento. A fonte da verdade vive no workspace da APIPASS via ferramentas MCP — nunca edite JSON local.

> **Fluxo de Agente de IA?** Se o pedido envolve um agente de IA, RAG ou base de conhecimento (`.service.ai.AiAgent`, modelos LLM, memoria, tools, vector store, embeddings), a topologia e **hub-and-spoke** — diferente da cadeia linear deste guia. Carregue `/apipass-integrations:build-agent-flow` (ele reaproveita a mecanica compartilhada daqui). Uma chamada simples ao ChatGPT sem tools (`CHATGPT_CREATE_COMPLETION`) e um passo linear normal e fica neste guia.

## 0. Autenticacao
As ferramentas operam como o usuario autenticado (Keycloak). Se alguma retornar `status: "login_necessario"` com uma `authorizeUrl`, mostre a URL ao usuario, peca para autorizar no navegador e refaca a acao. O token renova sozinho.

## 1. Planejar (antes de qualquer chamada que escreve)
- Esclareca a intencao: gatilho (trigger), acoes envolvidas, tratamento de erro, casos de borda.
- Veja o contexto: `list_projects` e, se aplicavel, `list_flows(projectId)`.
- Faca 2-3 perguntas de design numa unica mensagem. Confirme o plano antes de construir.

## 2. Pesquisar as acoes (catalogo)
Cada passo do fluxo e uma **acao** do catalogo. Para saber o `type` exato e o shape do `mappingAttributes`, delegue ao subagent `apipass-researcher` ou use `/apipass-integrations:research-action`. Nunca invente nomes/valores de campo — descubra via `get_action_struct` ou lendo um fluxo existente com `get_flow_development`.

> Se uma das acoes for um Agente de IA (`.service.ai.AiAgent`) ou da familia de IA (modelos LLM, memoria, tools, vector store, embeddings, document loader/splitter), pare e use `/apipass-integrations:build-agent-flow` — a montagem desses passos e por `*RouteConfigId` (hub-and-spoke), nao por `nextSteps`.

## 2b. Padroes obrigatorios de estrutura de steps

Siga os padroes abaixo ao montar o array de steps. Nunca invente IDs, tipos ou imagens.

### IDs dos steps
- Trigger sempre: `id: "trigger"`
- Steps sequenciais: `id: "a0"`, `"a1"`, `"a2"`, etc.
- Step de fim sempre: `id: "a999"`
- `lastGeneratedStepId` = **maior numero sufixo dos steps regulares + 1**, SEM contar o `a999` (Fim, sentinela). Ex.: a0,a1,a2,a999 → `lastGeneratedStepId: 3`. Ids de steps dentro de `loopSteps` (`l1a0`...) nao entram nessa conta — o loop tem o seu PROPRIO `lastGeneratedStepId`, com a mesma regra (ver secao "Loop" abaixo). Ao editar um fluxo existente, confira antes o contador atual com `get_flow_info` — se ja estiver a frente (steps removidos), numere os steps novos a partir dele para nao reutilizar ids

### Trigger scheduler
```json
{
  "id": "trigger",
  "trigger": true,
  "label": "Início",
  "image": "scheduler",
  "nodeSize": "small",
  "type": ".trigger.scheduler.TriggerScheduler",
  "cron": "0 8 * * 1-5",
  "zoneId": "America/Sao_Paulo",
  "concurrentExecutions": 1,
  "timeFormat": "dd/MM/yyyy HH:mm",
  "timestamp": false,
  "previousSteps": [],
  "nextSteps": [{ "id": "a0", "type": "...", "sourceUUID": "integration-step-uuid-sourceEndpoint-trigger", "targetUUID": "integration-step-uuid-targetEndpoint-a0" }]
}
```

### Trigger REST (webhook)
A imagem do trigger REST é **`"api"`** (NÃO `"rest"` — `"rest"` renderiza imagem quebrada).
```json
{
  "id": "trigger",
  "trigger": true,
  "label": "Início",
  "image": "api",
  "nodeSize": "small",
  "type": ".trigger.rest.RestTrigger",
  "path": "recebe-info",
  "methods": ["POST"],
  "mediaType": "application/json",
  "authProvider": "ENDPOINT",
  "idempotencyStrategy": "NONE",
  "headers": [],
  "params": [],
  "previousSteps": [],
  "nextSteps": [{ "id": "a0", "type": "...", "sourceUUID": "integration-step-uuid-sourceEndpoint-trigger", "targetUUID": "integration-step-uuid-targetEndpoint-a0" }]
}
```

**Validacao de payload e documentacao OpenAPI (JSON Schema):** use o campo `jsonSchema` com o schema serializado como **string** (com `\r\n`). NÃO use `requestBodySchema` — esse campo nao aparece na UI. O `jsonSchema` serve para **duas finalidades**: validar a requisicao E alimentar o Swagger publico gerado pela APIPASS. Exemplo:
```json
{
  "jsonSchema": "{\r\n  \"type\": \"object\",\r\n  \"properties\": {\r\n    \"strCodigoOuItem\": { \"type\": \"string\", \"example\": \"FILTRO\" },\r\n    \"tambemBuscarViaDescricaoItem\": { \"type\": \"boolean\", \"example\": true }\r\n  },\r\n  \"required\": [\"strCodigoOuItem\"],\r\n  \"example\": { \"strCodigoOuItem\": \"FILTRO\", \"tambemBuscarViaDescricaoItem\": true }\r\n}\r\n"
}
```

**`{{$.trigger.queryParams.*}}` NAO decodifica `+` como espaco.** Um `<form method="GET">` (ex. filtro de dashboard com `<select>`) codifica espacos em valores como `+` na query string — convencao classica de `application/x-www-form-urlencoded`. O `RestTrigger` da APIPASS decodifica `%XX` normalmente, mas **preserva o `+` literal** em vez de converte-lo para espaco. Um valor como `?cliente=Contoso+Seguros` chega em `queryParams.cliente` como a string `"Contoso+Seguros"`, nao `"Contoso Seguros"` — qualquer comparacao/filtro subsequente (`===`, `.indexOf(...)`) contra um valor com espaco real nunca da match, silenciosamente (sem erro, sem log). **Fix:** decodifique manualmente todo `queryParam` que possa conter espaco, ANTES de usar em filtro ou echo: `function decodePlus(v) { return (v || '').replace(/\+/g, ' '); }`. Vale para qualquer valor vindo de um `<select>`/`<input>` de formulario GET — nao so nomes de cliente, mas categorias/status com espaco no proprio nome (ex. `"Dúvida / Solicitação"`).

**`RestTrigger` pode exigir Authorization via `authIds[]` — mas isso quebra link clicavel.** E possivel setar `authProvider: "ENDPOINT"` + `authIds: ["<authId>"]` (array, nao o `authId` singular) apontando pra uma credencial `ENDPOINT`. Isso faz a plataforma validar o header `Authorization` da requisicao real contra o `token` guardado na credencial **antes mesmo do fluxo executar** — e uma protecao de verdade a nivel de plataforma (sem header → 401 automatico; com o token, cru ou `Bearer <token>` → 200), nao uma checagem manual dentro do fluxo. **Trade-off:** como exige um header HTTP customizado, **nao funciona com um link clicado direto no navegador** (browsers nao anexam `Authorization` numa navegacao simples) — serve so para chamada programatica (outro sistema/script). Se o caso de uso e um dashboard/relatorio que humanos abrem clicando num link, use protecao via query param (`?key=...`, checada dentro do proprio fluxo no `.StopV2Step` com `groups`/`TEXT_DOES_NOT_MATCH`) — mais fraca (chave na URL, sem log de acesso), mas e a que funciona pra esse caso. **Pergunte ao usuario antes de sugerir/implementar auth por header num RestTrigger** — so faz sentido se o consumidor for outro sistema, nao um humano clicando num link.

### Loop — use SEMPRE o v3 (`LoopCanvas`)
O único tipo de loop válido é **`.utility.loop.LoopCanvas`** (image `"loop"`). Os tipos
`.utility.loop.LoopUtility` e `.utility.loop.LoopUtilityV2` foram **descontinuados** — nunca os use.

O `LoopCanvas` carrega o corpo do loop em `loopSteps` (NÃO em steps de topo). Início/fim do corpo são
`.StartLoop` (`l1StartLoop`) e `.StopLoop` (`l1999`); os passos do corpo usam ids `l1a0`, `l1a1`, … e
`lastGeneratedLoopId` reflete o número do loop (`l1` → 1).

**Campos obrigatórios do loop — `loopType` E `source` (não só `valid`):**
- `loopType: "EACH_ITEM"` — **sem esse campo, a UI pode ATÉ mostrar "Item de Array" no dropdown "Tipo de Loop" (valor de exibição/default), mas a configuração real não fica persistida e a execução roda indefinidamente** (nunca termina o loop). Sempre setar explicitamente.
- `source: "{{$.aN.body}}"` — o array a iterar. **É esse campo que a UI lê para o campo "Origem"** quando `loopType` está configurado — não `valid`. Se só `valid` for preenchido (sem `loopType`), o campo "Origem" aparece vazio na UI mesmo com o step salvo.
- `valid: "{{$.aN.body}}"` (mesmo valor de `source`) — mantenha os dois preenchidos com o mesmo array; fluxos de referência reais têm ambos os campos, redundantes.
- `lastGeneratedStepId` **no proprio step do loop** (nivel do `LoopCanvas`, ao lado de `loopType`) — contador dos ids do corpo, com a MESMA regra do contador do fluxo: **maior sufixo dos steps de `loopSteps` + 1**, sem contar `l1StartLoop`/`l1999` (ex.: `l1a0`..`l1a8` → `lastGeneratedStepId: 9`). E independente do `lastGeneratedStepId` do fluxo (os ids `l1aN` nao entram na conta do fluxo, e os `aN` nao entram na do loop). Sempre preencher ao criar ou editar um loop.
- Cada step dentro de `loopSteps` (incluindo `l1StartLoop` e `l1999`) também precisa de `previousSteps` (ver seção "Conexões entre steps" abaixo) e de `positionX`/`positionY` — sem isso, o sub-canvas do loop não renderiza os nós ao abrir o step na UI (mesmo bug do canvas principal, mas dentro do loop).

```json
{
  "id": "l1",
  "label": "Loop",
  "type": ".utility.loop.LoopCanvas",
  "image": "loop",
  "loopType": "EACH_ITEM",
  "source": "{{$.a3.body}}",
  "valid": "{{$.a3.body}}",
  "lastGeneratedStepId": 1,
  "nextSteps": [{ "id": "a4", "type": "...", "sourceUUID": "integration-step-uuid-sourceEndpoint-l1", "targetUUID": "integration-step-uuid-targetEndpoint-a4" }],
  "loopSteps": [
    { "id": "l1StartLoop", "type": ".StartLoop", "image": "start", "label": "Início", "previousSteps": [], "positionX": 8043, "positionY": 8718,
      "nextSteps": [{ "id": "l1a0", "type": "...", "sourceUUID": "integration-step-uuid-sourceEndpoint-l1StartLoop", "targetUUID": "integration-step-uuid-targetEndpoint-l1a0" }] },
    { "id": "l1a0", "type": "...", "label": "...", "previousSteps": [{ "id": "l1StartLoop", "type": ".StartLoop", "label": "Início", "image": "start", "output": null }], "positionX": 8253, "positionY": 8718,
      "nextSteps": [{ "id": "l1999", "type": ".StopLoop", "state": "LINKED", "sourceUUID": "integration-step-uuid-sourceEndpoint-l1a0", "targetUUID": "integration-step-uuid-targetEndpoint-l1999" }] },
    { "id": "l1999", "type": ".StopLoop", "image": "stop", "label": "Fim", "previousSteps": [{ "id": "l1a0", "type": "...", "label": "...", "image": "...", "output": null }], "positionX": 8463, "positionY": 8718, "nextSteps": [] }
  ]
}
```

**"Parar Loop" (`.utility.loop.BreakLoop`) — use o shape que a UI gera, NAO o `stepSkeleton` do catalogo.** O skeleton de `list_actions` (grupo `loop`) traz so `type`/`mappingAttributes`, sem `image`; um BreakLoop montado a partir dele (sem `image`, com `nextSteps: []` e campos genericos de step) e aceito no save, mas nao e o conector que o canvas cria, e teve de ser recriado na UI. Shape real, confirmado num fluxo criado pelo canvas:
```json
{ "id": "l1a9", "label": "Parar Loop", "type": ".utility.loop.BreakLoop", "image": "break-loop",
  "authProvider": "", "valid": true, "nodeSize": "small", "positionX": 8592, "positionY": 8572 }
```
- Fica dentro de `loopSteps` e e terminal: **sem `nextSteps`** e sem `failOnError`/`mappingAttributes`/demais campos obrigatorios dos steps comuns. Ao executar, sai do loop inteiro e o fluxo segue para o `nextSteps` do proprio `LoopCanvas`.
- O step anterior aponta para ele normalmente: `{ "id": "l1a9", "type": ".utility.loop.BreakLoop", "sourceUUID": "...sourceEndpoint-l1a0", "targetUUID": "...targetEndpoint-l1a9" }` (sem `state`).
- Seu id conta para o `lastGeneratedStepId` do loop como qualquer outro step do corpo.
- Uso tipico: retry com `loopType: "TIMES"`, em que a tentativa bem-sucedida (ou um erro nao retentavel) sai do loop antes de esgotar as iteracoes.

### Tipos fixos canonicos (NUNCA invente o `type`)
Esses steps "fixos" existem no catalogo (`list_actions`) — mas atencao ao **grupo**, que NAO bate com o rotulo visual. Filtrar pelo nome errado faz o catalogo parecer vazio e leva a inventar um `type` que o engine aceita no save mas a **UI nao abre**. Os types corretos:

| Step | `type` correto | grupo no catalogo | `image` |
|------|----------------|-------------------|---------|
| Switch / condicional | `.utility.switchutility.SwitchUtility` | `switchutility` | `switch` |
| Tratar erro | `.utility.error.ErrorHandler` | `error` | `error-route` |
| Loop (v3) | `.utility.loop.LoopCanvas` | `loop` | `loop` |
| Inicio/Fim do loop | `.StartLoop` / `.StopLoop` | `loop` | `start` / `stop` |
| Parar Loop | `.utility.loop.BreakLoop` | `loop` | `break-loop` |
| Fim do fluxo | `.StopV2Step` | `stop` | `stop` |

NUNCA use `.conditional.SwitchV2`, `.errorhandler.ErrorHandler`, `.utility.loop.LoopUtility(V2)` — sao inventados/descontinuados e quebram o designer.

**Estrutura do Switch (`SwitchUtility`):** os ramos NAO-default ficam em `cases[]`; cada case tem `label`, `targetStepId`, `targetStepType` e `groups[].rules[]` (`{input, condition, expected?}`). O ramo default vai em `defaultStepId`/`defaultStepType`, e `default` recebe o LABEL do ramo default. Condicoes: `INPUT_IS_NULL`, `INPUT_IS_NOT_NULL`, `ARRAY_IS_NOT_EMPTY`, `TEXT_MATCHES`, `TEXT_DOES_NOT_MATCH`, `NUMBER_DOES_NOT_MATCH` (com `expected`). `nextSteps` lista os dois alvos (sem `state`).
```json
{
  "id": "a7", "label": "Tem anexo?", "type": ".utility.switchutility.SwitchUtility", "image": "switch",
  "default": "Sem anexo",
  "cases": [ { "label": "Tem anexo", "targetStepId": "a8", "targetStepType": ".service.http.HttpRequest",
    "groups": [ { "rules": [ { "input": "{{$.a6.body}}", "condition": "ARRAY_IS_NOT_EMPTY" } ] } ] } ],
  "defaultStepId": "a10", "defaultStepType": ".service.http.HttpRequest",
  "nextSteps": [ { "id": "a8", "type": "...", "sourceUUID": "...sourceEndpoint-a7", "targetUUID": "...targetEndpoint-a8" },
                 { "id": "a10", "type": "...", "sourceUUID": "...sourceEndpoint-a7", "targetUUID": "...targetEndpoint-a10" } ]
}
```

**Switch após HTTP — detectar erro por status code:** use `$.aN.headers.responseStatusCode` com `NUMBER_DOES_NOT_MATCH "200"` para rotear o case de erro; o caminho de sucesso fica como `default`. NÃO use `INPUT_IS_NOT_NULL` no body como proxy — o body pode estar preenchido mesmo em respostas de erro.

Quando o destino do case de erro é um ERROR_ROUTE, adicione `coreRouteType: "ERROR_ROUTE"` no nextStep correspondente e `defaultStepCoreRouteType: "ERROR_ROUTE"` no switch (se o default for o ERROR_ROUTE). Exemplo:
```json
{
  "id": "a2", "label": "Sucesso?", "type": ".utility.switchutility.SwitchUtility", "image": "switch",
  "default": "Sucesso",
  "cases": [ { "label": "Erro", "targetStepId": "a3", "targetStepType": ".service.actions.Action",
    "coreRouteType": "ERROR_ROUTE",
    "groups": [ { "rules": [ { "input": "{{$.a1.headers.responseStatusCode}}", "condition": "NUMBER_DOES_NOT_MATCH", "expected": "200" } ] } ] } ],
  "defaultStepId": "a999", "defaultStepType": ".StopV2Step",
  "nextSteps": [
    { "id": "a3", "type": ".service.actions.Action", "coreRouteType": "ERROR_ROUTE", "sourceUUID": "...sourceEndpoint-a2", "targetUUID": "...targetEndpoint-a3" },
    { "id": "a999", "type": ".StopV2Step", "sourceUUID": "...sourceEndpoint-a2", "targetUUID": "...targetEndpoint-a999" }
  ]
}
```

**ERROR_ROUTE como destino de Switch:** use o componente ERROR_ROUTE (NÃO um NodeJS) para tratar o erro e encaminhar ao stop. O output do ERROR_ROUTE é acessado via `$.aN.message` (não `.body`).
```json
{
  "id": "a3", "label": "Tratar Erro", "type": ".service.actions.Action",
  "actionId": "ERROR_ROUTE", "coreRouteType": "ERROR_ROUTE",
  "image": "https://s3.amazonaws.com/flow-manager-api-prd/actions/logo/ERROR_ROUTE.png",
  "additionalConfiguration": true, "failOnError": true,
  "inputData": { "errorMessage": "{{$.a1.body}}" },
  "nextSteps": [{ "id": "a999", "type": ".StopV2Step", "sourceUUID": "...sourceEndpoint-a3", "targetUUID": "...targetEndpoint-a999" }]
}
```
No stop, referencie o erro via `{{$.a3.message}}` (não `.body`).

### Step de fim
```json
{
  "id": "a999",
  "type": ".StopV2Step",
  "image": "stop",
  "label": "Fim",
  "nodeSize": "small",
  "nextSteps": [],
  "previousSteps": [{ "id": "aX", "type": "...", "label": "...", "image": "...", "output": null }]
}
```

**Content-Type real da resposta ignora o campo `responseData.contentType`.** Mesmo padrao do `bearerToken`/`contentType` de nivel raiz do `.service.http.HttpRequest` (ver secao "Step HTTP" abaixo): setar `responseData.contentType: "text/html"` (ou qualquer valor diferente de `application/json`) e aceito no `save_flow_development`, mas a resposta HTTP real sempre volta com `Content-Type: application/json`, independente do valor configurado. **Fix confirmado:** adicione em `responseData.headers` um item `{"label": "Content-Type", "value": "text/html; charset=utf-8"}` — isso sim reflete no header real (confirmado via `fetch(...).headers.get('content-type')` num navegador real contra o endpoint publicado). Mantenha `contentType` preenchido tambem por compatibilidade de schema, mas nunca confie nele isoladamente. Necessario sempre que o Stop precisar servir HTML/CSV/texto puro (ex. um dashboard "server-rendered" pela propria APIPASS) em vez do JSON padrao.

**Fluxos com RestTrigger: sempre preencha `responses[]` com o campo `oas`.**
O campo `responses` e obrigatorio para publicar (sem ele, `publish_flow` retorna HTTP 400). Alem disso, o sub-objeto `oas` em cada resposta alimenta o Swagger publico da APIPASS.
- Uma entrada com `"default": true` e `"groups": []` (caminho feliz, fallback).
- Entradas adicionais para cada codigo de erro com `groups` definindo a condicao de ativacao.
- `oas.jsonSchema` e sempre uma **string** JSON serializada (nunca objeto).

Ver shape completo e exemplos em `/apipass-integrations:apipass-patterns` (secao "Documentacao OpenAPI (OAS)").

### Conexoes entre steps
- `nextSteps[].sourceUUID`: `"integration-step-uuid-sourceEndpoint-{id-origem}"`
- `nextSteps[].targetUUID`: `"integration-step-uuid-targetEndpoint-{id-destino}"`
- Cada step tem `previousSteps` listando quem chega nele: `{ id, type, label, image, output: null }`

### Posicoes (layout horizontal, incremento de 210)
**TODO step PRECISA de `positionX`/`positionY`.** `save_flow_development` REESCREVE o fluxo inteiro: qualquer step (ou filho de `loopSteps`) salvo sem posicao volta para `(0,0)` e os nos ficam empilhados na origem no designer. Ao editar um fluxo existente, **preserve as posicoes** que vieram do `get_flow_development`; ao criar, atribua-as.
- trigger: `positionX: 8190, positionY: 8718`
- a0: `positionX: 8400, positionY: 8718`
- a1: `positionX: 8610, positionY: 8718`
- a2: `positionX: 8820, positionY: 8718`
- a999: positionX do ultimo step regular + 210
- **Loop (`LoopCanvas`)**: os steps dentro de `loopSteps` usam um espaco de coordenadas PROPRIO do canvas do loop (recomece em ~`8000`, ex. `l1StartLoop: 8043,8718`, incrementando 210), independente das posicoes do canvas principal.

### Acesso a saida de steps — nao existe um `.body` universal
Cada tipo de step define seu proprio shape de saida — `.body` NAO e sintaxe obrigatoria de interpolacao, e sim um campo que existe (ou nao) dependendo do formato nativo daquele step:

- **HTTP** (`.service.http.HttpRequest`) e **NodeJS** (`.utility.nodejs.NodeJSUtility`, que roda sobre um mecanismo HTTP por baixo) encapsulam o resultado em `.body` (+ `.headers`). O que um NodeJS exporta com `$export(null, {...})` vai para dentro desse `body`.
  - `{{$.a0.body.campo}}` — acessa `campo` exportado pelo NodeJS a0, ou campo do corpo de resposta HTTP do step a0.
- **Actions de catalogo com shape proprio** (ex. `SQL_QUERY`) NAO usam `.body`. `SQL_QUERY` expoe `.result` (array, para SELECT) e `.rowCount`/`.updateCount` (para INSERT/UPDATE) diretamente no nivel do step.
  - `{{$.a0.result}}` — array de linhas de um SELECT no step a0.
  - `{{$.a0.updateCount}}` — linhas afetadas por um UPDATE/INSERT no step a0.
- **Item atual dentro de um `LoopCanvas`** e exposto em `.data` no nivel daquele loop, tambem sem `.body`.
  - `{{$.l1.data.campo}}` (ou, em codigo NodeJS dentro do loop: `$.l1.data.campo`) — campo do item da iteracao atual do loop l1.

Isso vale tanto dentro de codigo NodeJS quanto em interpolacoes mustache (`{{...}}`). **Nunca assuma `.body` por padrao** — confirme o shape real do step lendo `get_action_struct` (para actions de catalogo) ou um fluxo real existente com `get_flow_development` antes de montar a interpolacao.

Isso vale dentro de codigo NodeJS (`$.a0.body.campo`) e dentro de interpolacoes (`"{{$.a0.body.campo}}"`).

### AMS e AOS — filas assincronas e Object Store
Para consumir/publicar mensagens via fila (AMS) ou persistir dados no MongoDB nativo da APIPASS (AOS), ver `/apipass-integrations:apipass-patterns` (secoes "AMS — Apipass Message System" e "AOS — Apipass Object Store") — shapes completos do trigger `TriggerAMSConsumeMessage`, do step `AMS_SEND_MESSAGE`, de `AOS_FIND_ONE_BY_QUERY`/`AOS_UPDATE`/`AOS_INSERT`/`AOS_DELETE` e do NodeJS helper de `$set`.

**`deleteStrategy` do trigger AMS — valores exatos:** `"IMMEDIATELY"` ou `"ON_FLOW_SUCCESS"` (NAO `"ON_SUCCESS"` — esse valor parece plausivel mas nao existe; o engine aceita no save sem erro, mas a UI nao reconhece o valor ao abrir o step: o dropdown "Estrategia de remocao da mensagem" aparece vazio e, por consequencia, o campo dependente `defaultVisibilityTimeout` (numero, em segundos) tambem aparece vazio mesmo que ja esteja salvo. Sintoma identico ao bug do `loopType`/`source` do Loop — confira sempre o valor exato reabrindo o step na UI apos o save.

### Step NodeJS
- `type: ".utility.nodejs.NodeJSUtility"`, `image: "nodejs"`
- **O codigo-fonte vai no campo `code`, NUNCA em `rawData`** (esse e o campo do body do `.service.http.HttpRequest`, secao abaixo). Usar `rawData` por engano NAO da erro no `save_flow_development` — o step e aceito normalmente — mas a execucao real trava e expira em ~2 minutos (`"Execution timeout"`), como se `$export` nunca tivesse sido chamado. Sintoma silencioso e caro de debugar; se um NodeJS trava sem log de erro, confira esse campo primeiro.
- Exportar resultado: `$export(null, { campo: valor })`
- `usedSteps` e **derivado automaticamente pelo engine** a partir das referencias (`$.a0`, `$.trigger`, etc.) encontradas dentro do `code`, no momento do `save_flow_development`/`create_version` — nao precisa (e nao da para) preencher manualmente; qualquer valor enviado e substituido pelo que o engine detectar no proprio codigo.

### Step HTTP
- `type: ".service.http.HttpRequest"`, `image: "http"`
- Campos no nivel raiz: `url`, `method`, `rawData`, `bearerToken`, `contentType`, `headers: []`, `params: []`, `async: false`
- Interpolacao no rawData: `"{{$.a0.body.campo}}"`

**`bearerToken`/`contentType` de nivel raiz NAO sao aplicados de fato a requisicao (confirmado empiricamente com teste de eco via httpbin.org).** Mesmo preenchidos, o header `Authorization` nao e enviado e o `Content-Type` real da chamada e sempre `text/plain`, nunca o valor configurado. Esses campos existem no `stepSkeleton` (copie-os por compatibilidade de schema), mas nao confie neles para autenticacao ou content-type — configure via `headers` (abaixo).

**`Authorization` e `Content-Type` so funcionam via o array `headers`, e cada item usa `label`/`value` — NUNCA `key`/`value`.** Um header montado com `key` em vez de `label` e aceito silenciosamente pelo `save_flow_development` e pela execucao (sem erro, sem log), mas o header nunca e enviado. Exemplo completo, incluindo o token OAuth de uma autorizacao referenciada no proprio step via `authId`/`authProvider` (sintaxe de interpolacao sem o id embutido — ver `/apipass-integrations:apipass-actions`):
```json
"headers": [
  { "label": "Content-Type", "value": "application/json" },
  { "label": "Authorization", "value": "Bearer {{$.authorization.access_token}}" }
]
```

### Step de acao do catalogo (WhatsApp, Outlook, etc.)
- `type: ".service.actions.Action"`
- `actionId`: ID da acao (ex: `"WHATSAPP_SEND_TEXT_MESSAGE"`)
- `authorization`: nome do grupo (ex: `"WHATSAPP"`)
- `image`: URL S3 obtida via `list_actions(group)` → campo `logoFileUrl`
- `additionalConfiguration: true`
- Campos da acao em `inputData: {...}`
- Interpolacao: `"{{$.a2.body.campo}}"`

### Campos obrigatorios em todos os steps
```json
{
  "authProvider": "",
  "authId": "",
  "doc": "",
  "timeout": "",
  "httpProtocolVersion": "",
  "rawData": "",
  "failOnError": false,
  "logEnabled": true,
  "valid": true,
  "mappingAttributes": {},
  "mappingAttributesRootArray": {},
  "trigger": 0
}
```

## 2c. Autorizacoes (credenciais) — referencie, nunca embuta
**Principio central da plataforma: um step NUNCA carrega credenciais/segredos embutidos. Ele referencia uma autorizacao ja cadastrada pelos campos `authId` + `authProvider`.**

- Descubra as credenciais disponiveis com `list_authorizations` (filtre por `provider` e/ou `projectId`). O `id` retornado vai em `authId`; o `provider` vai em `authProvider`.
- Para acoes do catalogo (`.service.actions.Action`), o `authProvider`/`authId` casam com o grupo/provider da acao (ex. `WHATSAPP`). Para HTTP que precise de credencial, use `authId` da autorizacao adequada em vez de colar token no step.
- Precisa usar um valor da credencial dentro do step (header/param)? Use `get_authorization_interpolation_fields(id)` para descobrir os campos disponiveis (ex. `access_token`), mas interpole **sem o id no caminho**: `{{$.authorization.access_token}}` — nunca `{{$.authorization.<authId>.access_token}}` (forma com id embutido, ERRADA, nao resolve). O `authId`/`authProvider` no topo do PROPRIO step ja escopa qual autorizacao esta em uso; nunca cole o segredo.
- Antes de trocar/remover uma credencial, veja o impacto com `list_flows_using_authorization(authId)`.
- Se nao houver autorizacao para o provider, ou houver ambiguidade, PERGUNTE ao usuario (ou peca para cadastrar) — nao invente `authId` nem embuta credencial.

Ferramentas: `list_authorizations`, `get_authorization`, `get_authorization_interpolation_fields`, `list_flows_using_authorization`.

## 2b. Verifique o catalogo antes de salvar (gap de catalogo)
Ao reconstruir ou **portar** um fluxo para OUTRA conta, lembre que custom actions (`actionId`), credenciais (`authId`) e variaveis de environment (`{{$.stage.X}}`) sao **por conta** e podem nao existir no destino. Antes do `save_flow_development`:
- Confirme cada `actionId` de connector/custom via `list_custom_actions` / `list_actions`.
- Liste as variaveis de environment que o fluxo espera (`{{$.stage.*}}`).
- Se algo faltar: mapeie para um equivalente do catalogo da conta destino ou **sinalize ao usuario** — NUNCA invente o id. Itens nao portaveis viram pendencia explicita (credencial, environment var, custom action especifica).

## 3. Construir incrementalmente
1. `create_project` (se necessario) — exige `confirm: true`.
2. `create_flow(name, projectId)` — exige `confirm: true`. Guarde o `flowId`.
3. Monte o array de `steps` seguindo os padroes da secao 2b.
4. `save_flow_development(id, steps, lastGeneratedStepId, lastGeneratedLoopId, logEnabled, confirm: true)`.

## 4. Validacao (automatica no save)
O `save_flow_development` valida ANTES de enviar e bloqueia em caso de erro (ids duplicados, `id`/`type` vazios, `lastGeneratedStepId` menor que o maior id de step — lembre que o valor correto e max + 1, ver secao 2b). Corrija os erros listados e tente de novo. Campos obrigatorios com default seguro sao preenchidos automaticamente — confira os avisos.

## 4b. Versionar e publicar (cadeia)
A publicacao depende de uma versao, e a versao depende do save. Ordem:
1. `save_flow_development(...)` — grava os steps.
2. `create_version(flowId, comment?, confirm: true)` — cria o snapshot (versao).
3. `publish_flow(environmentId, historyId, confirm: true)` — publica a versao no environment (use `list_environments` / `get_published_environments_for_flow` para achar os ids).
Para testar antes de publicar: `run_test_flow(flowId, environmentId, payload, confirm: true)`. Todas essas operacoes tem efeito real — confirme com o usuario.

## 5. Investigar execucoes
Apos publicar/rodar, analise logs (ver `/apipass-integrations:apipass-gotchas`): `list_flow_execution_logs` -> `get_flow_execution_log` -> `list_step_execution_logs` -> `read_step_payload`.

## Principios
- Descubra tecnicamente, esclareca estrategicamente.
- Nunca adivinhe valores de `mappingAttributes` — pesquise ou pergunte.
- Autenticacao SEMPRE por autorizacao: preencha `authId`/`authProvider` a partir de `list_authorizations`. Nunca embuta credenciais/segredos/tokens direto no step.
- Nunca invente IDs, tipos ou imagens de steps — siga os padroes da secao 2b.
- Nao existe um `.body` universal — o shape de saida varia por tipo de step (ver secao "Acesso a saida de steps"). Confirme sempre via `get_action_struct`/`get_flow_development` antes de assumir `.body`.
- Operacoes com efeito colateral (`create_*`, `save_flow_development`, `publish_flow`, `delete_*`) exigem `confirm: true` E confirmacao do usuario.
- Contadores `lastGeneratedStepId`/`lastGeneratedLoopId` devem refletir os ids usados (ver patterns).

## Skills relacionadas
- `/apipass-integrations:build-agent-flow` — construir fluxos de Agente de IA / RAG (topologia hub-and-spoke)
- `/apipass-integrations:apipass-agent-actions` — anatomia das acoes de IA e do agente
- `/apipass-integrations:research-action` — pesquisar uma acao do catalogo
- `/apipass-integrations:create-action` — criar uma custom action a partir de doc de API
- `/apipass-integrations:apipass-actions` — anatomia do FlowStep e catalogo
- `/apipass-integrations:apipass-patterns` — estrutura do fluxo, contadores, publicacao
- `/apipass-integrations:apipass-gotchas` — erros comuns e debug de execucao
- `/apipass-integrations:set-account` — definir a conta/realm
