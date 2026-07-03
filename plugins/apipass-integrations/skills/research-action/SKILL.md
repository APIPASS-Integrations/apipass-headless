---
name: research-action
description: Processo para pesquisar uma acao do catalogo da APIPASS — descobrir o type exato, a autenticacao e o shape do mappingAttributes antes de montar um passo do fluxo.
disable-model-invocation: false
argument-hint: "[nome-da-acao]"
---

# Pesquisar Acao: $ARGUMENTS

Para builds reais, prefira delegar ao subagent `apipass-researcher` (ele absorve o schema verboso e devolve um passo pronto). Use este processo direto para buscas triviais.

## Pare e pergunte se
- O `get_action_struct` nao revelar os campos/valores.
- Houver campos ambiguos (status, tipo, prioridade) sem valores claros.
- A autenticacao da acao for incerta.

## Passo 1: Localizar a acao
- `list_action_groups` para ver as categorias.
- `list_actions` (catalogo completo — vem compactado) ou `get_action(groupId, id)` para uma acao especifica.
- Registre o `type` EXATO da acao (e o que vai no campo `type` do FlowStep) e se ela exige autenticacao (`authProvider`/`authId`).

## Passo 1b: Resolver a autorizacao (se a acao autentica)
- Nunca embuta credenciais no step — referencie uma autorizacao por `authId` + `authProvider`.
- `list_authorizations(provider)` acha credenciais do provider/grupo da acao; `id` => `authId`, `provider` => `authProvider`. Filtre por `projectId` quando aplicavel.
- `get_authorization(id)` detalha; `get_authorization_interpolation_fields(id)` lista campos interpolaveis (use via `{{...}}` em headers/params, sem expor o segredo).
- 0 ou varias candidatas = ambiguidade: registre nas incognitas para o usuario decidir/cadastrar.

## Passo 2: Descobrir o shape da config
- **Prefira ler um fluxo real** que ja usa essa acao: `get_flow_development(flowId)` e copie o shape exato — isso revela tambem o NIVEL onde cada campo mora (topo do step vs dentro de `mappingAttributes`), que o struct nao garante. Sempre que possivel, peca/use um `flowId` de exemplo.
- `get_action_struct(id)` lista QUAIS campos a acao tem (util como referencia), mas: pode **404** em acoes `fixed`/embutidas (ex. `.trigger.rest.RestTrigger`) e nao diz em que nivel os campos aparecem no step salvo.
- Atencao: em muitas acoes (ex. `.service.http.HttpRequest`) a config fica no **nivel superior do step** (`url`, `method`, `rawData`, ...) com `mappingAttributes: {}`. O corpo HTTP vai em `rawData`.
- Interpolacao entre passos: mustache `{{$.<id>}}` (ex. `{{$.trigger.body}}`), nunca `${...}`.
- Para passos HTTP, `curl_to_http(command)` converte um cURL em request pronto.

## Passo 3: Custom actions
- `list_custom_actions` / `get_custom_action(id)` para acoes customizadas da conta.

## Retorno
Entregue um resumo enxuto: `type`, necessidade de auth, e o objeto `mappingAttributes` pronto (com placeholders onde faltar valor do usuario). Nao despeje schema cru.
