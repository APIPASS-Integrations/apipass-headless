---
name: create-action
description: |
  Criar uma custom action da APIPASS a partir da documentacao de uma API (OpenAPI/Swagger, doc HTML, cURL ou descricao). Use quando o usuario pedir "crie uma action a partir desta doc", "transforme este endpoint em uma action", "gere uma action de API", "importe este OpenAPI como actions".

  Ponto de entrada para CRIAR/EDITAR custom action. Carregue ANTES de chamar create_custom_action / update_custom_action.
disable-model-invocation: false
---

# Criar Custom Action na APIPASS

Uma custom action e um conector da conta definido por um **arquivo NodeJS** (`jsFileAsString`). O backend extrai `label`/`authorization` do proprio arquivo, valida por schema (Joi) e persiste. A fonte da verdade vive no workspace da APIPASS via MCP — nao salve arquivos locais.

## Escopo suportado (IMPORTANTE)
Gere SOMENTE as duas formas HTTP, nunca `configureCoreRoute`:
- **`executeHttpRequest(input, configurations)`** → retorna a request (`{ url, method, headers, body }`); runtime marca `type: 'HTTP'`. **Forma preferida** para mapear um endpoint de API.
- **`execute(input, configurations)`** → logica JS arbitraria; runtime marca `type: 'JS_CODE'`. Use so quando precisa transformar/derivar dados antes/depois da request.

O Joi do backend exige **EXATAMENTE UMA** dessas funcoes no arquivo. Nunca emita as duas, nem `configureCoreRoute`.

## 0. Autenticacao
As ferramentas operam como o usuario autenticado (Keycloak). Se algo retornar `status: "login_necessario"` com uma `authorizeUrl`, mostre a URL, peca para autorizar e refaca. O token renova sozinho.

## 1. Planejar (antes de qualquer escrita)
- Entenda a doc: qual(is) endpoint(s) viram action? Uma action por operacao (METHOD + path).
- Esclareca numa unica mensagem: quais campos sao `input` (entram em tempo de execucao) vs `configurations` (fixos por uso); qual a autenticacao da API; o que sai no `output`.
- Se a doc for grande (OpenAPI), liste as operacoes e confirme quais criar antes de gerar.

## 2. Resolver a autorizacao (authorization)
`this.authorization` no arquivo e o **nome do provider** da credencial (ex. `"GOOGLE"`, ou um provider generico). O backend roda `checkIfProviderExists` — **o provider precisa existir** ou a criacao falha.
- Descubra com `list_authorizations(provider?)` / `get_authorization(id)`. O `provider` retornado e o que vai em `this.authorization`.
- Para usar um segredo da credencial dentro da request, use `get_authorization_interpolation_fields(id)` e interpole — nunca cole o token cru no arquivo.
- Se nao houver provider adequado, PERGUNTE ao usuario (ou peca para cadastrar). Nao invente.

## 3. Gerar o arquivo NodeJS
Delegue ao subagent `apipass-action-author` (ele absorve o schema verboso e devolve o `jsFileAsString` ja validado). Para casos triviais, monte voce mesmo seguindo a anatomia abaixo. Use `curl_to_http` quando a doc trouxer um cURL.

### Anatomia do jsFile
```js
module.exports = function () {
  this.label = 'Criar cliente';            // string (vira o label da action)
  this.help = 'Cria um cliente na API X';  // opcional
  this.authorization = 'PROVIDER';         // provider existente (ou omita se nao autentica)

  // configurations: valores fixos por uso (opcional). type: 'object' | 'array', title obrigatorio.
  this.configurations = {
    title: 'Configuracao', type: 'object',
    properties: { baseUrl: { title: 'Base URL', type: 'string', minLength: 1 } }
  };

  // input: dados de execucao. type: 'object' | 'array'. title obrigatorio em cada campo.
  this.input = {
    title: 'Entrada', type: 'object',
    properties: {
      name:  { title: 'Nome',  type: 'string', description: 'Nome do cliente', minLength: 1 },
      email: { title: 'Email', type: 'string' }
    }
  };

  // output: type 'object'.
  this.output = {
    title: 'output', type: 'object',
    properties: { status: { title: 'status', type: 'string' } }
  };

  // EXATAMENTE UMA funcao:
  this.executeHttpRequest = function (input, configurations) {
    return {
      url: `${configurations.baseUrl}/customers`,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { name: input.name, email: input.email }
    };
  };
};
```

Regras dos schemas (validadas pelo Joi):
- `input.type` e `configurations.type` so aceitam `object` ou `array`. `output.type` so `object`.
- Tipos de campo permitidos: `string | number | boolean | object | array | password | json | html | sql | xml | text`.
- `title` e obrigatorio em cada campo. `minLength: 1` marca o campo como obrigatorio.
- Select: `expression: false` + `options: [{ key, value, selected? }]` (ou com `expression: true`, `options: [{ id, text, selected? }]`).
- Para campos `object`/`array`, aninhe `properties` recursivamente.
- Nao invente campos — derive da doc; o que faltar vira pergunta ao usuario.

## 4. Validar (sempre, antes de criar)
`validate_custom_action(jsFileAsString)` — dry-run, sem efeito colateral. Retorna `{ input, configurations, output, label, authorization }`. Se falhar, corrija o arquivo e revalide. So prossiga com a validacao limpa.

## 5. Criar / atualizar (efeito colateral — confirme)
- `create_custom_action(jsFileAsString, confirm: true)` — cria; retorna o `id`.
- `update_custom_action(id, jsFileAsString, confirm: true)` — atualiza um existente (leia o atual com `get_custom_action_file(id)` antes de editar).
- `delete_custom_action(id, confirm: true)` — remove (falha se algum fluxo usa a action).
Sempre confirme com o usuario antes de enviar `confirm: true`.

## 6. Usar no fluxo
Depois de criada, a action aparece em `list_custom_actions` e pode entrar num fluxo como step de catalogo (`.service.actions.Action` / custom) — ver `/apipass-integrations:build-flow`.

## Principios
- Gere SO `executeHttpRequest` ou `execute` — nunca `configureCoreRoute`, nunca as duas.
- Sempre `validate_custom_action` antes de `create`/`update`.
- `authorization` deve ser um provider existente — resolva via `list_authorizations` ou pergunte.
- Nunca embuta segredos no arquivo — interpole campos da credencial.
- Efeito colateral (`create_*`, `update_*`, `delete_*`) exige `confirm: true` E confirmacao do usuario.

## Skills relacionadas
- `/apipass-integrations:build-flow` — usar a action num fluxo
- `/apipass-integrations:apipass-gotchas` — armadilhas (inclui custom action)
- `/apipass-integrations:set-account` — definir a conta/realm
