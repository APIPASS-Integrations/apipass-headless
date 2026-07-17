---
name: apipass-actions
description: Referencia do catalogo de acoes da APIPASS e a anatomia do FlowStep. Carregue ao montar passos de um fluxo, escolher um gatilho ou preencher mappingAttributes.
disable-model-invocation: false
---

# Catalogo de Acoes e Anatomia do FlowStep

Na APIPASS, cada passo de um fluxo e uma **acao**. O catalogo de acoes e descoberto via ferramentas (nao ha lista fixa — varia por conta):

- `list_action_groups` — categorias de acoes
- `list_actions` — catalogo (compactado)
- `get_action(groupId, id)` — detalhe de uma acao
- `get_action_struct(id)` — **schema de input** da acao (base do `mappingAttributes`)
- `list_custom_actions` / `get_custom_action(id)` — acoes customizadas da conta

## Catalogo completo: banco + acoes fixas
O `list_actions` retorna o catalogo COMPLETO, mesclando duas fontes:
- **`catalog`** — acoes do banco (via `GET /action`); exige login.
- **`fixed`** — acoes fixas embutidas no codigo do flow-manager (ex. `.service.mongodb.MongoDBInsertService`, `.utility.delay.DelayUtility`, `.trigger.scheduler.TriggerScheduler`), que NAO aparecem na API. Sempre disponiveis, mesmo sem login.

Cada item traz `source: "catalog" | "fixed"`. Filtre com `list_actions(group, kind)` — ex. `kind: "trigger"` para gatilhos, `group: "mongodb"` para uma familia. O campo `type` (ex. `.service.mongodb.MongoDBInsertService`) e exatamente o que vai em `FlowStep.type`.

**Campos da action (resolve o cold-start):** as acoes fixas trazem `fields` (struct extraido das classes) e, melhor ainda, um **`stepSkeleton`** — o FlowStep canonico com os campos ja no NIVEL correto (topo do step, `mappingAttributes: {}`) e `mappingLevel: "top-level"`. Use o `stepSkeleton` direto: NAO e preciso fluxo de exemplo nem `get_action_struct` para acao fixa. Excecoes: `.service.actions.Action`/`CustomAction` sao do catalogo (dinamicas) — a config vai em `inputData`, com o schema via `get_action_struct`; algumas `utility.*`/`paradigma.*` ainda nao expoem `fields`/skeleton completo (nesses casos, leia um fluxo existente com `get_flow_development` ou pergunte ao usuario).

> As acoes fixas vem de um manifesto gerado do codigo-fonte (`src/catalog/fixed-actions.ts`). O gerador faz DEDUPE com o repo `actions` (catalogo de connectors): qualquer action que ja exista la (por grupo com `.js` ou por nome) e EXCLUIDA do manifesto, pois retorna via API/`list_actions`. Sobram so as acoes realmente fixas no engine (http, loop, triggers, store? nao — store vem do catalogo; sim: nodejs, switch, jwtsign, text/datetime ops core, etc.). Regenere com `npm run generate:catalog` apontando `FLOW_MANAGER_SRC`, `FLOW_MANAGER_APP_I18N` e `ACTIONS_REPO`.

## Anatomia do FlowStep

Um fluxo e salvo via `save_flow_development` com um array de `steps`. Cada step tem estes campos (todos esperados pela API):

| Campo | Tipo | Quem define | Notas |
|---|---|---|---|
| `id` | string | builder | unico no fluxo; se numerico, conta para `lastGeneratedStepId` |
| `label` | string | builder | rotulo exibido |
| `type` | string | catalogo | o `type` EXATO da acao (de `get_action`) |
| `authProvider` | string | catalogo/auth | provedor de auth da acao |
| `authId` | string | auth | id da credencial; vazio se a acao nao autentica |
| `positionX` / `positionY` | string | builder | posicao no diagrama (default "0") |
| `trigger` | number | builder | indica papel de gatilho (0 = passo normal) |
| `valid` | boolean | builder | default true |
| `mappingAttributes` | object | builder | config da acao em ALGUMAS acoes; em muitas (ex. HttpRequest) fica `{}` e a config vai no nivel superior do step — veja "Onde mora a configuracao" |
| `mappingAttributesRootArray` | object | builder | mapeamento de array raiz (quando aplicavel) |
| `rawData` | string | builder | dados crus do passo (quando usado) |
| `failOnError` | boolean | builder | se falha o fluxo ao dar erro no passo |
| `timeout` / `httpProtocolVersion` / `image` / `doc` | string | builder | metadados; defaults seguros |

**Onde mora a configuracao — o NIVEL e ditado pelo `source` (o nome `mappingAttributes` engana; na pratica fica `{}`):**

| `source` | Tipo de step | Onde os campos de config moram | Como obter |
|---|---|---|---|
| `fixed` | step nativo do engine (http, triggers, stop, `utility.*`) | **nivel superior** do step, `mappingAttributes: {}` | use o **`stepSkeleton`** de `list_actions` — ja vem pronto |
| `catalog` | connector via `.service.actions.Action` / `.CustomAction` (tem `actionId`) | em **`inputData`**, `mappingAttributes: {}` | schema via `get_action_struct(id)` -> monte `inputData` |

Regras:
- **Acao `fixed`**: copie o `stepSkeleton`, preencha valores, ajuste `id`/`label`. Sem fluxo de exemplo, sem `get_action_struct`.
- **Acao `catalog`**: a config vai em `inputData` (NAO no topo, NAO em `mappingAttributes`), guiada pelo schema do struct.
- **So leia um fluxo real** (`get_flow_development`) se o skeleton parecer divergir do salvo, ou para campos estruturais complexos (`responses` do stop, `cases` do switch, `loopSteps` do loop).
- Em nenhum caso invente valores de campo.

Exemplo — `.service.http.HttpRequest` (shape real; campos no topo, `mappingAttributes: {}`):
```json
{
  "id": "a0", "label": "Requisicao HTTP", "type": ".service.http.HttpRequest", "image": "http",
  "authProvider": "ALL_PROVIDERS", "method": "POST",
  "url": "https://exemplo.com/hook", "contentType": "application/json",
  "rawData": "{{$.trigger.body}}",
  "headers": [{ "label": "Content-Type", "value": "application/json" }], "params": [],
  "mappingAttributes": {}, "httpProtocolVersion": "HTTP_2", "httpTlsVersion": "TLS",
  "failOnError": true, "generateRawData": false
}
```
O corpo da requisicao vai em **`rawData`** (string), nao num campo `body`.

## Autorizacoes (credenciais) — `authId` / `authProvider`
Toda acao que autentica referencia uma **autorizacao ja cadastrada**, nunca um segredo embutido no step. Os dois campos do FlowStep envolvidos:
- `authProvider` — o provider/grupo da credencial (ex. `WHATSAPP`, `GOOGLE`); para HTTP generico pode ser `ALL_PROVIDERS`.
- `authId` — o id da autorizacao escolhida (vazio se a acao nao autentica).

Descubra as credenciais disponiveis com as ferramentas (RBAC aplicado; nenhum segredo e retornado):
- `list_authorizations(provider?, projectId?, withoutProjectId?, excludeProviders?)` — lista autorizacoes; `id` => `authId`, `provider` => `authProvider`.
- `get_authorization(id)` — metadados de uma autorizacao.
- `get_authorization_interpolation_fields(id)` — campos da credencial que podem ser interpolados (`{{...}}`) num step, sem expor o segredo.
- `list_flows_using_authorization(authId)` — fluxos que usam a credencial (impacto antes de alterar).

Regra: preencha `authId`/`authProvider` a partir de `list_authorizations`. Se nao houver credencial para o provider ou houver ambiguidade, pergunte ao usuario — nunca chute `authId` nem cole token no step.

### Sintaxe de interpolacao do token (confirmado empiricamente)
Quando um step `.service.http.HttpRequest` referencia a autorizacao via `authId` + `authProvider` no PROPRIO step, os campos dessa credencial (ex. `access_token`, listados por `get_authorization_interpolation_fields(authId)`) sao acessados **sem o id no caminho**: `{{$.authorization.access_token}}`. O `authId`/`authProvider` no topo do step ja escopa QUAL autorizacao esta em uso; NAO use `{{$.authorization.<authId>.access_token}}` — essa forma com o id embutido esta ERRADA e nao resolve.

```json
{
  "id": "a1",
  "type": ".service.http.HttpRequest",
  "authProvider": "PIPEDRIVE",
  "authId": "1be24008-9d24-48ec-9fd4-2d9782a2e128",
  "method": "POST",
  "url": "https://api.pipedrive.com/v1/persons",
  "headers": [
    { "label": "Authorization", "value": "Bearer {{$.authorization.access_token}}" }
  ]
}
```

## Referenciar dados entre passos (interpolacao)
A APIPASS usa expressoes **mustache** `{{$.<caminho>}}` para referenciar a saida de passos anteriores e o contexto de execucao. **NAO use `${...}`** (estilo Camel/JS) — esse formato esta errado.
- `{{$.trigger.body}}` — o payload (body) recebido pela trigger.
- `{{$.<idDoStep>}}` — a saida de outro step pelo id (ex. `{{$.a0}}`, `{{$.a1}}`).
- `{{$.<idDoStep>.<campo>}}` — um campo especifico da saida.
- **Nao existe um `.body` universal — cada tipo de step tem seu proprio shape de saida.** Steps baseados em HTTP (**HTTP** e **NodeJS**, que roda sobre um mecanismo HTTP por baixo) encapsulam o resultado em `.body` (+ `.headers`) — ex. `{{$.a1.body.x}}` para o que um NodeJS exportou com `$export(null, {x})`. Outras actions de catalogo tem shape proprio: ex. `SQL_QUERY` expoe `.result` / `.rowCount` / `.updateCount` diretamente, SEM `.body` (`{{$.a0.result}}`, `{{$.a0.updateCount}}`). O item atual dentro de um `LoopCanvas` e exposto como `.data` (`{{$.l1.data.campo}}`), tambem sem `.body`. Confirme sempre o shape real via `get_action_struct` (actions de catalogo) ou lendo um fluxo real com `get_flow_development`, em vez de assumir `.body` por padrao.
- `{{$.flowExecution.status}}` — contexto da execucao (usado em regras de resposta do StopStep).

Ex.: para repassar TODO o payload da trigger num HttpRequest, use `"rawData": "{{$.trigger.body}}"`. Confirme o caminho exato lendo o `output` do step anterior em `get_flow_development` (cada trigger/acao expoe seu proprio schema de saida).

## Roteamento de erro vs. sucesso (no `nextSteps`)
Quando um step pode desviar para tratamento de erro, o `nextSteps` lista as DUAS saidas e o papel de cada uma e dado pelo tipo do alvo e por um marcador:
- **Sucesso:** a aresta carrega `"state": "LINKED"` e aponta para o proximo passo normal.
- **Erro:** a aresta aponta para um step `.utility.error.ErrorHandler` (image `error-route`) e **NAO** leva `state`. O ErrorHandler encadeia o tratamento (log, montagem de mensagem, notificacao).

O que ativa o desvio e `failOnError: true` no step que pode falhar. Exemplo (HTTP que, em falha, vai ao ErrorHandler; em sucesso, segue ao proximo HTTP):
```json
"nextSteps": [
  { "id": "a3", "type": ".utility.error.ErrorHandler",
    "sourceUUID": "integration-step-uuid-sourceEndpoint-a1", "targetUUID": "integration-step-uuid-targetEndpoint-a3" },
  { "id": "a2", "type": ".service.http.HttpRequest",
    "sourceUUID": "integration-step-uuid-sourceEndpoint-a1", "targetUUID": "integration-step-uuid-targetEndpoint-a2", "state": "LINKED" }
]
```
Varios steps podem apontar para o MESMO ErrorHandler (rota de erro compartilhada).

## Gatilho (primeiro passo)
Todo fluxo comeca por um passo de gatilho. Descubra os tipos de gatilho disponiveis via `list_action_groups` / `list_actions` (o catalogo da conta dita os nomes). Escolha o gatilho conforme a intencao do usuario (agendado, webhook, manual, etc.) e confirme o `type` exato antes de montar.
