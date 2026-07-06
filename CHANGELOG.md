# Changelog — apipass-integrations

## 0.15.0
### Adicionado
- **Guidelines ABNT NBR 14724 na skill `document-flows`.** Nova secao 6.1 com valores numericos prontos para uso no docx-js: margens A4 (superior 3 cm, inferior/direita 2 cm, esquerda 3 cm — largura util 9071 DXA), fonte Arial 12pt com espacamento 1,5, hierarquia de titulos (nivel 1 MAIUSCULO+negrito, nivel 2 negrito, nivel 3 negrito italico), legendas de tabela (acima) e figura (abaixo), numeracao de paginas no canto superior direito (header), listas com traco (--) sem bullet grafico, sumario com pontos via TabStopType.RIGHT. Inclui aviso critico sobre encoding CP1252/UTF-8 no Windows/PowerShell e instrucao para converter SVG para PNG com o pacote `sharp`. Gatilhos da skill atualizados com "documento ABNT" e "documento tecnico-funcional".

## 0.14.0
### Adicionado
- **Padroes de AMS (filas assincronas) e AOS (Object Store) na skill `apipass-patterns`.** Nova secao AMS: trigger `TriggerAMSConsumeMessage`, step `AMS_SEND_MESSAGE`, convencao de nome de fila com `{{$.stage.name}}-`, `deleteStrategy`, acesso ao payload no subfluxo consumidor. Nova secao AOS: autorizacao `APIPASS_OBJECT_STORE`, convencao database/colecao, shapes completos de `AOS_FIND_ONE_BY_QUERY`/`AOS_UPDATE`/`AOS_INSERT`/`AOS_DELETE`, padrao CRUD GET/POST/PATCH, NodeJS para query `$set`. Skill `build-flow` ganhou uma referencia curta a essas secoes (sem duplicar o conteudo).
- **Regras de review para AMS e AOS na skill `review-flow`.** Secao 4e-bis: 7 regras AMS (AMS1-AMS7) — fila hardcoded, `failOnError`, master nao retorna imediatamente, `deleteStrategy`, idempotencia, fila divergente, ausencia de idCorrelacao. Secao 4f-bis: 8 regras AOS (AOS1-AOS8) — database hardcoded, `authProvider` ausente, filter vazio em UPDATE/DELETE, query inline, INSERT sem `_id` customizado, escritas sem verificacao de erro, colecao com sufixo de ambiente, GET sem verificacao de documento nulo.

## 0.13.0
### Mudancas
- **Renderizacao do canvas de Agente de IA (`endpointDefinitions`).** Skills `build-agent-flow` e `apipass-agent-actions`: documentado que os campos `*RouteConfigId` fazem o fluxo EXECUTAR, mas o designer so DESENHA as arestas hub-and-spoke se cada no tiver `endpointDefinitions` (hub/ingestor com `bottomEndpoints`; satelites com `targetPosition: "Top"`). Inclui exemplo JSON completo da cadeia de ingestao (ingestor/loader/embedding/splitter) com os endpoints canonicos. Antes a ausencia desses metadados gerava canvas quebrado / agente "sem modelo" mesmo com a execucao funcionando.
- **`label` de porta deve ser chave i18n real ou texto literal** — chave inexistente (ex. `VECTOR_STORE.EMBEDDING`) aparece crua no canvas; use `AI_AGENT.MODEL`/`.MEMORY`/`.TOOLS`, `DOCUMENT_LOADER.TEXT_SPLITTER`, ou literal (`"Embedding"`).
- **Splitter obrigatorio.** `build-agent-flow`/`apipass-agent-actions`: todo `FILE_DOCUMENT_LOADER`/`URL_DOCUMENT_LOADER` exige um `DOCUMENT_SPLITTER_*` ligado via `documentSplitterRouteConfigId` (antes tratado como opcional). Documentado tambem o padrao de ingerir TEXTO PURO via `WRITE_FILE` + loader `TEXT`.
- **Descoberta de fluxos no `apipass-researcher`.** Agente ganhou as tools `list_projects` e `list_flows` (antes so tinha `get_flow_development`, que exige um flowId conhecido) e orientacao para ler um fluxo real ao montar acoes de IA — `list_actions` pode truncar e ignorar o filtro `group`, escondendo os grupos `AI`/`VECTOR_STORE`/`CHAT_MEMORY`. Evita concluir que um campo "nao existe" por ausencia no catalogo.
- **Gotchas de teste/execucao.** Skill `apipass-gotchas`: `run_test_flow` so roda a versao PUBLICADA e retorna vazio (cicle save → version → publish → test); payload de TEST chega em `$.trigger` (nao `$.trigger.body`) — recomendado NodeJS normalizador como 1o passo; erro transitorio do Atlas Search Index (`code 125`) passa no retry; render por `endpointDefinitions` e splitter obrigatorio.
- Caveat de subagentes: descoberta dependente de MCP fica na thread principal — Explore/researcher rodam em sessao de auth separada e caem em `login_necessario` (token nao compartilhado).

## 0.11.2
### Mudancas (breaking)
- **Nomenclatura "stage" -> "environment" tambem nos nomes de tool e parametros** (acompanha o servidor MCP 0.11.0). Skills, hook de confirmacao e docs atualizados para `list_environments`, `get_published_environments_for_flow` e o parametro `environmentId` (antes `stageId`) em `publish_flow`, `unpublish_flow`, `create_test_flow`, `run_test_flow`, `get_execution_summary` e nas tools de environment/OpenAPI. Os endpoints HTTP e as chaves do backend seguem com `stage`/`stageId` (contrato inalterado). O hook `confirm-publish.js` le `environmentId` (com fallback para `stageId`).

## 0.11.1
### Mudancas
- **Terminologia "stage" -> "environment"** nos textos das skills, do hook de confirmacao e da documentacao (`apipass-patterns`, `build-flow`, `review-flow`, `confirm-publish.js`, README, PLANO-FASE-1). Os contratos da API permanecem intactos — campos (`stageId`), tokens de runtime (`{{$.stage.*}}`), endpoints (`/stage`) e nomes de tools (`list_stages`, `get_published_stages_for_flow`) nao mudaram. Alinha o vocabulario com a futura renomeacao na UI.
- Sincronizada a versao do plugin em `marketplace.json` (estava defasada em 0.10.0) com `plugin.json`.

## 0.11.0
### Adicionado
- **Documentacao OpenAPI (OAS) em fluxos com RestTrigger.** Skill `apipass-patterns`: nova secao "Documentacao OpenAPI (OAS)" com o shape completo de `responses[].oas` no StopV2Step (`mediaType`, `jsonSchema` como string, `headers`), exemplo com 3 respostas (201/400/422) e regras de condicao (`INPUT_IS_NOT_NULL` para validacao, `TEXT_DOES_NOT_MATCH "OK"` no `flowExecution.status` para erros de processamento). Skill `build-flow`: secao RestTrigger atualizada para deixar claro que `jsonSchema` alimenta tanto a validacao quanto o Swagger publico; secao "Step de fim" agora documenta a obrigatoriedade do campo `oas` em fluxos REST e remete a `apipass-patterns` para o shape completo.

## 0.7.0
### Adicionado
- **Gate de confirmacao antes de publicar/executar em qualquer stage.** Novo hook `PreToolUse` (`hooks/hooks.json` + `hooks/confirm-publish.js`) que intercepta `publish_flow`, `unpublish_flow` e `run_test_flow` e SEMPRE forca um prompt de confirmacao do usuario (`permissionDecision: "ask"`), independentemente de allowlist/permissoes. A razao do prompt nomeia a operacao e o alvo (fluxo/stage/versao). Enforcement no nivel do harness, nao dependente do modelo.

## 0.5.2
### Corrigido
- Status dos logs de execucao unificado para `OK`/`ERROR` (antes o swagger de observability emitia `COMPLETED`/`FAILED`, inconsistente com o status de step). Skill `apipass-gotchas`: o passo de debug agora filtra erros com `status: "ERROR"` e documenta o enum `RUNNING | OK | ERROR | STOPPED` (OK = sucesso, ERROR = erro) para log de fluxo e de step. Requer servidor MCP com o client regenerado.

## 0.5.1
### Mudancas
- Skill `apipass-gotchas`: secao "Leitura de fluxos grandes" atualizada com o caso de **loops** — em servidores MCP < 0.5.1 o slim nao limpava `previousSteps` dentro de `loopSteps`, fazendo um unico `LoopCanvas` estourar ~60k chars mesmo com `pageSize` baixo; documenta o workaround e que a partir do servidor 0.5.1 o slim e recursivo.
- Skill `build-flow`: adicionados exemplos de **trigger REST** (`image: "api"` — `"rest"` renderiza icone quebrado) e de **loop** com a regra de usar SEMPRE o v3 `.utility.loop.LoopCanvas` (`loopSteps` + `.StartLoop`/`.StopLoop`); `.utility.loop.LoopUtility`/`LoopUtilityV2` estao descontinuados.
- Skill `build-flow`: secao "Posicoes" reforca que `save_flow_development` REESCREVE o fluxo e que todo step (e filho de `loopSteps`) sem `positionX`/`positionY` volta para `(0,0)` — ao editar, preservar as posicoes do `get_flow_development`; `loopSteps` usam espaco de coordenadas proprio.
- Skill `build-flow`: nova secao "Tipos fixos canonicos" — tabela com o `type`/grupo/`image` corretos de Switch (`.utility.switchutility.SwitchUtility`, grupo `switchutility`), ErrorHandler (`.utility.error.ErrorHandler`, grupo `error`), Loop/Stop, + exemplo de estrutura do Switch (`cases`/`defaultStepId`/condicoes). Evita inventar `.conditional.SwitchV2`/`.errorhandler.ErrorHandler` (aceitos no save, mas a UI nao abre).

## 0.4.1
### Mudancas
- Skill `build-flow` atualizada com os padroes obrigatorios de estrutura de steps (IDs trigger/a0..aN/a999, trigger scheduler, step de fim, conexoes/UUIDs, posicoes, regra universal do `.body` para saida de steps, shapes de NodeJS/HTTP/acao do catalogo e campos obrigatorios).

## 0.4.0
### Adicionado
- **Consumo/uso (observability)**: `get_execution_summary` (serie temporal: daily/hourly/monthly/flow, com stageId/order/sortBy) e novo `get_usage_summary` (agregado da conta: total/average/flow-engine-usage, com accountId). Skill `apipass-usage` para analise de consumo.

## 0.3.0
### Mudancas
- **Servidor MCP multi-usuario (hospedavel).** Sessoes por conexao (Mcp-Session-Id), token por sessao em memoria (interface pronta para Redis), e refresh single-flight por sessao.
- **Login por usuario:** `apipass_login(account_name)` resolve o realm de cada um; sem token, as ferramentas instruem o login (nao auto-logam pois o realm depende do account_name).
- **Callback OAuth publico** (`/oauth/callback` no proprio servidor, derivado de `OAUTH_PUBLIC_BASE_URL`) — substitui o loopback localhost; registrar como redirect_uri no Keycloak por realm.
- Pagina de callback com botao "Voltar ao Claude".
- Skill `set-account` reescrita para o fluxo de login por sessao.

## 0.3.0
### Adicionado
- **Skill `document-flows`** — gerador de documentacao de integracoes (Word/PDF) a partir dos fluxos de um projeto APIPASS. Le os fluxos direto da APIPASS via MCP (`list_projects` -> `list_flows` -> `export_flow_json`/`get_flow_development`), filtra rascunhos/legados, extrai acionamento/etapas/infos tecnicas (filas AMS, collections MongoDB, APIs externas) e descricoes dos comentarios `//` no codigo dos steps, e monta o documento (capa parametrizada pelo cliente -> visao geral -> secao por fluxo -> tratamento de erros) delegando a montagem do `.docx` a skill `anthropic-skills:docx`. Diagramas de sequencia opcionais. Substitui o procedimento manual antigo (scripts `mdlz-engine.js`/`gerar-diagramas.py`/`inject-diagramas.py`), tornando-o reproduzivel.

## 0.2.2
### Mudancas
- **Modelo de colocacao por `source`** (em vez de shapes hardcoded): a descoberta do NIVEL dos campos passa a seguir o `source` da acao. `fixed` → campos no topo do step, montados a partir do **`stepSkeleton`** que o `list_actions` agora entrega (requer `apipass-mcp-server` >= 0.2.2). `catalog` (`.service.actions.Action`/`.CustomAction`) → config em `inputData`, schema via `get_action_struct`. `mappingAttributes` fica `{}` nos dois casos.
- **`apipass-actions`**: tabela do modelo `source` → nivel → como obter; corrigida a afirmacao antiga de que os campos iam "dentro de `mappingAttributes`".
- **`apipass-researcher`**: passa a usar o `stepSkeleton`/`inputData` conforme o `source`, sem exigir `flowId` nem marcar incognita de nivel. Le um fluxo real so para campos estruturais (responses/cases/loopSteps) ou divergencia. Elimina o round-trip de `get_flow_development` para praticamente todas as acoes, nao so 3.
- **`apipass-gotchas`**: regra de colocacao reescrita em torno de `fixed` (topo/stepSkeleton) vs `catalog` (`inputData`).

## 0.2.0
### Adicionado
- **Publicacao de fluxo**: `publish_flow` / `unpublish_flow` + leituras `list_stages`, `get_published_stages_for_flow` (descobrir stageId/historyId).
- **Versionamento**: `create_version` (snapshot, pre-requisito de publicar) + `list_flow_versions`, `get_version`.
- **Teste de fluxo**: `run_test_flow` (executa com payload no stage), `create_test_flow`, `list_test_flows`.
- **Re-execucao e parada (Fase 2)**: `retry_execution_new/replace`, `batch_retry_new/replace`, `*_by_filter`, `stop_execution`, `get_batch_retry_queue_stats`.
- **Catalogo completo de acoes**: `list_actions` mescla catalogo do banco (API) + acoes fixas do codigo, com `fields` (struct) extraido das classes, `groupLabel` (i18n) e filtros `group`/`kind`. Dedupe contra o repo `actions` (connectors que ja retornam via API).
- **Login OAuth nao-bloqueante**: `apipass_login`, `apipass_auth_status`, `apipass_logout`; qualquer tool sem token devolve a URL de login na hora. Tela de callback estilizada.
- **Validacao estrutural** no `save_flow_development` (ids unicos, contadores, campos obrigatorios) com normalizacao de defaults.
- **Compactacao** de respostas verbosas (catalogo/logs).

### Mudancas
- Skills renomeadas para o vocabulario APIPASS: `build-flow`, `research-action`, `apipass-actions`, `set-account` (+ `apipass-patterns`, `apipass-gotchas`).
- Operacoes com efeito colateral exigem `confirm: true` e confirmacao do usuario.

## 0.1.0
- Versao inicial: scaffold do marketplace/plugin, servidor MCP (OAuth2+PKCE via Keycloak atras do API Gateway), ferramentas de catalogo, projetos, construcao de fluxo e leitura de logs.
