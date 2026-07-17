---
name: apipass-gotchas
description: Erros comuns e armadilhas ao construir fluxos na APIPASS e o fluxo de debug de execucao (analise de logs). Carregue ao depurar um erro de fluxo ou uma execucao que falhou.
disable-model-invocation: false
---

# Gotchas da APIPASS

## Construcao de fluxo

| Sintoma | Causa provavel | Correcao |
|---|---|---|
| "Validacao do fluxo falhou — nada foi salvo" | `id`/`type` vazios, ids duplicados, ou `lastGeneratedStepId` incorreto | Leia a lista de erros do retorno e corrija; ajuste os contadores (= ultimo id gerado + 1; o stop `a999` e sentinela e nao conta) |
| JSON Schema da trigger REST nao aparece na UI | Usou `requestBodySchema` (campo invalido) ou passou o schema como objeto JSON | O campo correto e `jsonSchema` com valor como **string serializada** (com `\r\n`). Exemplo: `"jsonSchema": "{\r\n  \"type\": \"object\"...\r\n}\r\n"`. Nunca use `requestBodySchema`. |
| Switch apos HTTP roteia errado (vai para sucesso mesmo em erro da API) | Usou `INPUT_IS_NOT_NULL` no body como proxy de sucesso | Use `$.aN.headers.responseStatusCode` com `NUMBER_DOES_NOT_MATCH "200"` para detectar erro; sucesso vai para o `default`. |
| Passo nao executa / config "some" no save | Campos no nivel errado. Regra: acao `fixed` (http, triggers, stop, `utility.*`) → campos no TOPO do step; connector `catalog` (`.service.actions.Action`) → campos em `inputData`. `mappingAttributes` fica `{}` nos dois | `fixed`: copie o `stepSkeleton` de `list_actions`. `catalog`: monte `inputData` pelo schema de `get_action_struct` |
| Interpolacao nao resolve (vem literal) | Sintaxe errada `${...}` | Use mustache `{{$.<id>}}` — ex. `{{$.trigger.body}}`, `{{$.a0}}` |
| `save_flow_development` "retornou vazio" | Sucesso NAO traz payload | Nao e erro; confirme relendo com `get_flow_development` |
| "Method and URL are required, check your flow configuration." no step de acao (MEMORY_STORE_SET/GET, PROJECT_STORE_SET/GET, LOGGER etc.) — mesmo com `actionId`/`coreRouteType` corretos no step | Faltou `coreRouteType` no **objeto de link** dentro do array `nextSteps` do step anterior. O engine usa esse campo para resolver a URL do microsservico — sem ele nao roteie e lanca o erro. Causa silenciosa: `get_flow_development` e `save`/`publish` aceitam sem reclamar, mas a execucao falha | Em cada item de `nextSteps` que aponta para um `.service.actions.Action`, inclua `"coreRouteType"` com o mesmo valor do step de destino. Ex: `{"id":"a0","type":".service.actions.Action","coreRouteType":"MEMORY_STORE_GET","sourceUUID":"...","targetUUID":"..."}`. Vale para TODOS os acoes de catalogo. Leia um fluxo funcional com `get_flow_development` para confirmar o shape correto do link. |
| Acao exige credencial mas falha | `authId` vazio numa acao que autentica | Defina o `authId` correto da conta |
| Nao sei os campos de uma acao | Tentou adivinhar | NUNCA invente — pesquise via `/apipass-integrations:research-action` |
| `login_necessario` no meio de uma acao | Sem token valido | Mostre a `authorizeUrl` ao usuario, ele autoriza, refaca a acao |
| Operacao recusada pedindo confirm | Efeito colateral sem `confirm: true` | Confirme com o usuario e reenvie com `confirm: true` |
| Bearer token OAuth nao resolve num step HTTP generico (`.service.http.HttpRequest`) que ja tem `authId`/`authProvider` no topo | Usou `{{$.authorization.<authId>.access_token}}` (com o id embutido no caminho) | Use `{{$.authorization.access_token}}` (sem id) — o `authId`/`authProvider` do proprio step ja escopa qual autorizacao esta em uso; campos disponiveis via `get_authorization_interpolation_fields(authId)` |
| `publish_flow` da HTTP 400 `IER001: Cannot read properties of undefined (reading 'map')` | O step de stop (`.StopV2Step`, ex. `a999`) nao tem o array `responses`. O `save_flow_development`/`create_version` aceitam o stop sem `responses`, mas a publicacao mapeia `responses` para montar o contrato da API | Adicione `responses` ao stop (ao menos a `Default` 200; ideal `Default` + `Error` 400). Copie o shape exato de um fluxo publicavel via `get_flow_development` (ver `/apipass-integrations:apipass-patterns`) |
| `run_test_flow` executa OK mas `{{$.trigger.body.*}}` vem `null` (e o body de resposta do stop que dependa dele) | Modo TEST nao popula o body do trigger como um POST HTTP real — vale para QUALQUER tipo de fluxo, nao so agentes | Nao e defeito do fluxo: o caminho funciona em requisicao real. Para validar a interpolacao do trigger, publique e chame o endpoint de verdade; use `run_test_flow` para validar wiring/passos com valores literais ou que nao dependam do shape do body do trigger |
| `run_test_flow` "nao faz nada" — nenhuma execucao aparece em `list_flow_execution_logs` | O `run_test_flow` roda a versao **publicada** no environment; sem `create_version` + `publish_flow` antes, nada executa. Alem disso a ferramenta retorna vazio (`undefined`), sem `executionId` | Cicle a cada edicao: `save_flow_development` → `create_version` → `publish_flow` → `run_test_flow`; depois consulte `list_flow_execution_logs` (com `startDate`/`endDate`/`page`) para pegar o resultado |
| Em modo TEST o payload chega em `$.trigger` (campos no topo), nao em `$.trigger.body`; webhook real as vezes usa `$.trigger.body` | Diferenca de shape entre TEST e POST real | Coloque um **NodeJS normalizador** como 1o passo apos a trigger e leia tudo dele: `let t=$.trigger||{}; let b=(t.body!=null)?t.body:t; if(typeof b==='string'){try{b=JSON.parse(b)}catch(e){}}; $export(null,{...campos de b})`. Torna o fluxo robusto e testavel; os passos seguintes leem `{{$.aX.body.campo}}` |
| Uma edicao manual feita pelo usuario direto na UI (ex. ajustou um header/valor no canvas) desaparece depois do proximo `save_flow_development` que voce chamar | `save_flow_development` reenvia o array de steps **INTEIRO** — nao e um patch/diff. Se voce montar o payload a partir de um `get_flow_development` antigo (lido antes do ajuste do usuario, ou de memoria da conversa), o save sobrescreve e apaga a mudanca manual sem aviso | Antes de QUALQUER `save_flow_development` de edicao (mesmo que voce ja tenha lido o fluxo antes na mesma conversa), rode `get_flow_development(flowId)` de novo imediatamente antes de montar o payload, para partir do estado mais recente |

## Fluxos de Agente de IA (Agent Builder)
Ver `/apipass-integrations:build-agent-flow` e `/apipass-integrations:apipass-agent-actions`. Armadilhas:

| Sintoma | Causa provavel | Correcao |
|---|---|---|
| Stop/interpolacao do agente vem vazio | Leu a saida do agente via `.body` | A saida do `.service.ai.AiAgent` e via **`.response`** — `{{$.a0.response}}`. So o agente; demais acoes de IA seguem `.body` |
| Designer mostra o agente "sem modelo" / nos soltos / quebra | Ligou modelo/memoria/tool por `nextSteps` | Satelites NAO entram em `nextSteps`. Ligue por `*RouteConfigId` (forward no agente + back-ref `aiAgentRouteConfigId` no satelite) |
| Canvas nao DESENHA as arestas de configuracao (modelo/tool/embedding/loader) mesmo com `*RouteConfigId` corretos e execucao OK | Faltam os `endpointDefinitions` (as portas). `*RouteConfigId` faz executar, mas o designer so desenha com `endpointDefinitions` | Adicione `endpointDefinitions` em cada no: hub/ingestor com `bottomEndpoints` (modelo/memoria/tools, ou embedding/documento), satelites com `targetPosition: "Top"`. Shapes em `/apipass-integrations:apipass-agent-actions` |
| Porta do no aparece com texto cru tipo `VECTOR_STORE.EMBEDDING` no canvas | `label` da porta e uma chave i18n inexistente | Use chave i18n REAL (`AI_AGENT.MODEL`, `DOCUMENT_LOADER.TEXT_SPLITTER`) ou texto literal (`"Embedding"`) |
| Ingestao falha no 1o disparo com `Error connecting to Search Index Management service` (Mongo code 125) | Hiccup transitorio do control-plane do Atlas ao criar/usar o indice vetorial | Geralmente passa no **retry**. O indice e criado pelo proprio ingestor; confirme que o cluster da credencial MONGODB suporta Atlas Vector Search e que `vectorIndexName`/dimensao batem com o retrieval |
| Loader sem splitter (ingestao incompleta) | Achou que splitter era opcional | Todo `FILE_DOCUMENT_LOADER`/`URL_DOCUMENT_LOADER` exige um `DOCUMENT_SPLITTER_*` ligado via `documentSplitterRouteConfigId` |
| Modelo/memoria nao "colam" no agente apos o save | Ligacao so de um lado | As ligacoes sao simetricas: `llmModelRouteConfigId`/`memoryRouteConfigId` no agente E `aiAgentRouteConfigId` no satelite |
| Tool nao recebe o parametro decidido pelo LLM | Valor fixo ou interpolacao normal no `inputData` da tool | Use `{{$fromAI('nome','descricao','tipo')}}` no campo; o LLM preenche em runtime. O `label` da tool e o nome que o LLM ve |
| Satelites empilhados em (0,0) no designer | Step de IA salvo sem `positionX/Y` | Toda acao de IA precisa de posicao; satelites ficam ABAIXO do agente (mesmo X aprox., Y maior) |
| Pediu "chame o ChatGPT" e montou um agente completo | Confundiu completion com agente | `CHATGPT_CREATE_COMPLETION` e passo linear simples (saida `.body`); `.service.ai.AiAgent` so quando ha tools/memoria/decisao |
| RAG retorna vazio | Base nao populada, ou embedding do retriever != embedding da ingestao | Popule via pipeline de ingestao (ingestor `AI_VECTOR_STORE_INGESTOR`); use o MESMO modelo/dimensao de embedding na ingestao e no retrieval |
| Agente da `IllegalArgumentException ... UserMessage ... parameter index 0 is null` no `run_test_flow` | `userMessage` interpola `{{$.trigger.body.*}}`, que vem `null` no modo TEST | Caso particular do quirk geral do `run_test_flow` (ver secao "Construcao de fluxo"): o caminho funciona em POST real; para validar via TEST use `userMessage` literal |

## Custom actions (criacao a partir de doc de API)
Ver `/apipass-integrations:create-action` para o processo completo. Armadilhas:

| Sintoma | Causa provavel | Correcao |
|---|---|---|
| Validacao do jsFile falha (Joi) | Mais de uma funcao, ou nenhuma | O arquivo precisa de EXATAMENTE UMA: `executeHttpRequest` OU `execute`. Nunca `configureCoreRoute` (fora de escopo), nunca as duas |
| Validacao falha em `input`/`configurations` | `type` invalido ou `title` faltando | `input.type`/`configurations.type` so `object|array`; `output.type` so `object`; cada campo precisa de `title`; tipos de campo: string|number|boolean|object|array|password|json|html|sql|xml|text |
| `create_custom_action` falha no provider | `this.authorization` aponta para provider inexistente | Backend roda `checkIfProviderExists` — resolva o provider via `list_authorizations` ou peca para cadastrar; omita `authorization` se a API nao autentica |
| Esqueci os campos da API | Tentou adivinhar | Derive da doc; delegue ao subagent `apipass-action-author`. O que faltar vira pergunta ao usuario — nunca invente |
| Operacao recusada pedindo confirm | Efeito colateral sem `confirm: true` | `create_custom_action`/`update_custom_action`/`delete_custom_action` exigem `confirm: true` E confirmacao do usuario |

## Environments e variaveis de stage

| Sintoma | Causa provavel | Correcao |
|---|---|---|
| `create_environment` recusa com `STAGE002: Invalid name/key... must be snake case without special characters` | Nome do stage tem hifen ou outro caractere especial (ex. `CLIENTE-MARKETPLACE`) | Use snake_case sem hifen — ex. `CLIENTE_MARKETPLACE` |
| Variavel nova (ex. `{{$.stage.MINHA_VAR_NOVA}}`) nao aparece em `get_environment`, e `update_environment_variables` a ignora silenciosamente (so relata as chaves que reconhece) | Um environment so herda as "definitions" de variavel **ja cadastradas na conta** | Use `create_variable_definition(key, type, confirm: true)` para cadastrar a definition a nivel de conta (type: string/number/boolean/authorization) — ela propaga automaticamente para todos os environments existentes, com value vazio. So depois disso a chave passa a existir em todo environment e pode ser preenchida via `update_environment_variables` |

## Leitura de fluxos grandes
`export_flow_json` pode voltar **truncado** em fluxos grandes (observado ~60KB+; ex. fluxo de ~28 steps): o JSON vem cortado e nao parseia. Prefira `get_flow_development(flowId)`, que ja vem **slim** por padrao (sem `previousSteps`, inclusive dentro de `loopSteps`). Se ainda estourar, **pagine**: `get_flow_development(flowId, page, pageSize)` (1-based; a resposta traz `totalSteps`/`totalPages`/`page`/`steps`) — leia em varias chamadas (ex. `pageSize: 10`). Use `includePreviousSteps: true` so se realmente precisar dos schemas de output. Para metadados use `get_flow_info`.

> **Loops e versoes antigas do servidor MCP (< 0.5.1):** o slim limpava `previousSteps` so no topo, e os filhos do loop (`loopSteps`) carregavam o seu — entao um unico step `LoopCanvas` estourava ~60k mesmo com `pageSize: 1`. Se voce estiver numa versao antiga e a leitura do loop vier truncada (string cortada / JSON invalido): reduza `pageSize` ate isolar o loop, e como ultimo recurso leia o arquivo persistido pelo harness, extraia o campo `text`, desescape (`\n`->quebra, `\"`->`"`) e faca grep dos `loopSteps` (os filhos reais vem **depois** dos blocos de `previousSteps`). A partir de 0.5.1 o slim e recursivo e isso nao ocorre mais.

## Regras
- **Nunca invente a config** — para `fixed` use o `stepSkeleton` de `list_actions` (campos no topo); para `catalog` use `inputData` via `get_action_struct`. So leia um fluxo real (`get_flow_development`) para campos estruturais (responses/cases/loopSteps) ou se o skeleton divergir.
- **Contadores**: `lastGeneratedStepId` = id do ultimo step gerado **+ 1**; o stop `a999` e sentinela e nao conta.
- **Interpolacao**: mustache `{{$.<id>}}` (ex. `{{$.trigger.body}}`), nunca `${...}`.
- **Efeito colateral exige confirmacao**: `create_*`, `save_flow_development`, `publish_flow`, `delete_*`.

## Fluxo de debug de execucao (analise de logs)
> Os logs sao para **investigar UMA execucao** (por que falhou, o que entrou/saiu). NAO use logs para **contar/listar quais fluxos executaram** num periodo — isso e sumario: `get_execution_summary(period: "flow")` (ver `/apipass-integrations:apipass-usage`).

1. `list_flow_execution_logs(...)` — encontre a execucao (filtre por `status: "ERROR"` para erros; o enum de status dos logs e `RUNNING | OK | ERROR | STOPPED` — **OK = sucesso, ERROR = erro** — tanto no log de fluxo quanto no de step). **Exige `page`, `startDate` e `endDate`** (sem eles retorna HTTP 400); use datas ISO, ex. `startDate: "2026-06-10T00:00:00.000Z"`. Filtros opcionais: `projectId`, `flowId`, `status`, `pageSize`.
2. `get_flow_execution_log(executionId)` — visao geral da execucao.
3. `list_step_execution_logs(flowExecutionId, page, pageSize, status?)` — quais passos rodaram/falharam. **Exige `page` e `pageSize`** (sem eles retorna HTTP 400).
4. `read_step_payload(...)` — entrada/saida de um passo especifico (para ver o que entrou e saiu).
5. `get_trigger_payload(flowExecutionId)` — o que disparou a execucao.

### Comparacao erro vs. sucesso (padrao obrigatorio)
Sempre que o usuario pedir analise de erros de um fluxo, **busque uma execucao OK em paralelo** com as ERRORs e compare o `read_step_payload` do step falho nas duas. Isso isola se o problema e no dado de entrada (body/queryParam diferente) ou na API/logica do fluxo.

Sequencia padrao:
list_flow_execution_logs(status: "ERROR") → pega execucoes com erro
list_flow_execution_logs(status: "OK") → pega execucao de sucesso (em paralelo)
list_step_execution_logs para ambas → identifica o step falho
read_step_payload para o step falho nas duas execucoes (em paralelo)
Compara input/output: URL, method, headers, body, response
O que observar no `input` do step:
- **body vazio vs. preenchido** — API externa pode retornar 500 quando body e `[]` ou `{}`
- **queryParams diferentes** — filtro ausente que a API exige
- **headers ausentes** — token/auth que nao foi interpolado corretamente
Para metricas agregadas: `get_execution_summary(period: daily|hourly|monthly|flow|total|average|flow-engine-usage, startDate, endDate)`.

### Fuso horario dos timestamps
Todos os timestamps retornados pelas tools de log (`startTime`, `finishTime` em `get_flow_execution_log`, `list_flow_execution_logs`, `list_step_execution_logs`) vem em **UTC** (sufixo `Z`, ex. `2026-07-09T17:23:14.017Z`). A UI da plataforma exibe no fuso horario local da conta (ex. America/Sao_Paulo, UTC-3), entao reportar o valor cru da API diverge do que o usuario ve no log do ambiente. Converta para o fuso do usuario antes de reportar horarios, e deixe explicito que e horario local quando relevante.

### Evidencia junto da conclusao
Ao concluir a causa raiz de um erro ("a URL/filtro/payload esta correto, o problema foi da API externa"), nao basta declarar a conclusao — anexe a evidencia concreta (input/output do step) junto da resposta. O padrao mais forte e comparar lado a lado a execucao com erro e uma execucao de sucesso/retry com o MESMO input: se o request e identico e o resultado muda (500 -> 200), isso isola a causa na API externa, nao no fluxo. Mostre esse comparativo (tabela ou trecho do `read_step_payload`) em vez de so o veredito em prosa.

## Melhorias recomendadas apos debug
Apos identificar a causa raiz de um erro recorrente, sugira proativamente ao usuario as melhorias abaixo quando aplicavel:
### Validacao de input no trigger (JSON Schema)
Quando o erro e causado por body/queryParam invalido ou vazio vindo do chamador, sugira adicionar validacao de schema na trigger (se o tipo de trigger suportar). Isso rejeita a requisicao com 400 antes de chamar APIs externas, evitando 500s confusos downstream. Exemplo de cenario: body `[]` enviado quando a API espera uma lista nao-vazia de codigos.
### Tratativa de erro com log claro no stop
Quando o fluxo nao tem um ErrorHandler ou o stop nao distingue erro de sucesso, sugira:
- Adicionar um **step de ErrorHandler** que captura excecoes do step HTTP e retorna uma resposta estruturada (ex. `{"error": true, "message": "...", "step": "a0"}`)
- Ou configurar o **stop com responses distintas**: `200` para sucesso e `400`/`502` para erro, usando Switch antes do stop para rotear conforme o `responseStatusCode` da chamada externa
- Isso torna o log de execucao autoexplicativo — em vez de "HTTP 500 An error has occurred", o consumidor recebe uma mensagem clara sobre o que falhou
## Re-execucao e parada (efeito colateral — sempre confirme)
Estas operacoes afetam execucoes REAIS e exigem `confirm: true` E confirmacao explicita do usuario. Nomeie o impacto antes de chamar.
- `stop_execution(executionId)` — interrompe uma execucao em andamento.
- `retry_execution_new(executionId, triggerBody)` — re-executa UMA criando nova execucao.
- `retry_execution_replace(executionId, triggerBody)` — re-executa UMA substituindo a existente.
- `batch_retry_new(executionsList[])` / `batch_retry_replace(executionsList[])` — lote por lista de ids.
- `batch_retry_new_by_filter(startDate, ...)` / `batch_retry_replace_by_filter(...)` — lote por FILTRO, **ate 1000 execucoes** e dificil de reverter; confirme o escopo (datas, status, projectId/flowId) com o usuario antes.
- `get_batch_retry_queue_stats(flowEngineId)` — leitura; mostra a fila de retry (sem efeito).