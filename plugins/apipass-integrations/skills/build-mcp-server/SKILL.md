---
name: build-mcp-server
description: |
  Criar, montar e publicar um MCP Server na APIPASS — um servidor MCP cujas ferramentas sao fluxos da plataforma (trigger MCP Tool), para um agente de IA usar as integracoes do cliente. Use sempre que o usuario pedir para "criar um MCP Server", "expor fluxos como tools/ferramentas MCP", "disponibilizar uma integracao para um agente", "adicionar/remover uma ferramenta do servidor", "publicar o MCP Server em producao", "qual a URL do MCP Server" ou "configurar a autenticacao do MCP Server".

  Carregue ANTES de chamar create_mcp_server / add_mcp_server_tool / publish_mcp_server. Para construir o fluxo que vira ferramenta, use a skill build-flow (trigger MCP Tool).
disable-model-invocation: false
---

# Construir um MCP Server na APIPASS

Um **MCP Server** e um recurso de projeto (ao lado dos fluxos). Cada **ferramenta** do servidor e o vinculo com um fluxo de trigger **MCP Tool**: chamar a ferramenta executa o fluxo, com os argumentos como payload (`{{$.trigger.*}}`), e devolve ao agente a resposta do step de fim. O servidor e publicado por environment, com uma URL propria em cada um.

Siga as etapas na ordem. Toda escrita exige `confirm: true` **e** a confirmacao do usuario.

## 0. Autenticacao
Se alguma tool retornar `status: "login_necessario"`, rode `apipass_login` com o `account_name`, mostre a URL ao usuario e refaca a acao.

## 1. Entender o pedido
Pergunte numa unica mensagem o que faltar:
- **Para que agente e com qual objetivo?** Vira a instrucao do servidor (`instructions`), que o LLM le para decidir *quando* usar o servidor. Escreva no ponto de vista do agente: dominio, quando usar, limites.
- **Quais capacidades** o agente deve ter (consultar estoque, abrir pedido…)? Cada uma vira uma ferramenta.
- **Em quais environments** publicar (ex. homologacao e producao).
- **Projeto** onde o servidor vai morar (`list_projects`).

## 2. Garantir os fluxos (trigger MCP Tool)
So fluxos com trigger MCP Tool (`.trigger.mcp.McpToolTrigger`) podem virar ferramenta.
- Ja existem? O servidor ainda nao existe na etapa 1, entao procure por `list_flows(projectId, triggerType: ".trigger.mcp.McpToolTrigger")`. Depois de criar o servidor, `list_mcp_server_eligible_flows(mcpServerId)` lista os elegiveis ainda nao vinculados.
- Falta algum? Construa com a skill `build-flow` (secao "Trigger MCP Tool"): o `inputSchema` do trigger e o contrato que o agente usa para montar a chamada, e as anotacoes (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) dizem ao agente o risco de chamar a ferramenta.
- O fluxo precisa estar **publicado** em cada environment onde a ferramenta deve aparecer (`create_version` → `publish_flow`). Ferramenta cujo fluxo nao esta publicado no environment fica fora do `tools/list` dali.

## 3. Criar o servidor
1. Sugira um Server ID (identificador da URL, `[a-z0-9-]`, ate 64 caracteres) e confira com `check_mcp_server_id_availability(serverId)`. A resposta traz o valor normalizado — e ele que vai na URL.
2. `create_mcp_server(projectId, name, serverId?, instructions?, confirm: true)`. Guarde o `id` (o `mcpServerId` das demais tools) e a `revision`.

## 4. Vincular as ferramentas
Para cada fluxo, `add_mcp_server_tool(mcpServerId, flowId, name, title?, description?, confirm: true)`:
- **`name`** — o que o agente ve e chama. Comeca com letra minuscula ou `_`, so `[a-z0-9_-]`, ate 64 caracteres, unico no servidor. Prefira verbo + objeto em snake_case (`consulta_estoque`, `abre_pedido`). Nao derive automaticamente do nome do fluxo: proponha e confirme com o usuario.
- **`title`** — rotulo de exibicao (opcional).
- **`description`** — o que a ferramenta faz e quando usa-la (opcional, mas e o que mais melhora a escolha do agente). Sem ela o agente recebe o `title`, ou o `name`.
- Um fluxo pode ser ferramenta de varios servidores, com `name` diferente em cada. Vincular de novo um fluxo ja vinculado ao mesmo servidor e recusado — use `update_mcp_server_tool`.

## 5. Publicar por environment
1. `list_environments()` para achar os `environmentId`.
2. `publish_mcp_server(mcpServerId, environmentId, confirm: true)` em cada environment escolhido. A resposta traz a **URL** do servidor ali: `https://{flowEngineIdentifier}.core.apipass.com.br/mcp/{environment}/{serverId}`.
3. `list_mcp_server_tools(mcpServerId)` mostra cada ferramenta por environment: `AVAILABLE`, `FLOW_NOT_PUBLISHED` (publique o fluxo naquele environment) ou `UNKNOWN`.

Recusas comuns: environment de flow engine **on-premise** (nao suportado), flow engine sem identificador publico, ou outro environment com o mesmo nome ja servindo esse Server ID no mesmo flow engine.

## 6. Autenticacao (opcional)
Sem configuracao, o endpoint responde sem token. Para exigir token, `configure_mcp_server_auth(mcpServerId, revision, authorizationIds, scopes, confirm: true)` — substitui a configuracao inteira:
- `authorizationIds` — autorizacoes **Endpoint** do Authorization Manager (`list_authorizations`) cujo token o runtime aceita como `Authorization: Bearer` (modo JWT, como no trigger REST).
- `scopes` — client scopes do realm da conta; o runtime aceita um token OAuth2 do realm com ao menos um deles.
- Cada valor pode ser uma interpolacao de variavel de environment (`{{$.stage.mcpAuthId}}`) para usar uma credencial diferente por environment. Lista vazia desliga aquele modo.

## 7. Entregar
Devolva ao usuario uma tabela por environment com a URL, as ferramentas disponiveis e as indisponiveis (com o motivo), e como conectar: a URL vai na configuracao de servidor MCP remoto (HTTP) do cliente; com autenticacao, o cliente envia `Authorization: Bearer <token>`.

## Mudancas depois de publicado — sempre avise antes
**Nao existe rascunho.** Com o servidor publicado, toda alteracao que o agente enxerga vai **na hora** para todos os environments publicados, inclusive producao. A resposta de cada escrita traz `propagation.published` e `propagation.failed` — reporte as falhas (o environment com falha segue servindo o estado anterior; `publish_mcp_server` naquele environment republica).

Avise e confirme com o usuario, citando os environments afetados, antes de:
- **Alterar o Server ID** (`update_mcp_server`) — muda a URL em todos os environments; agentes configurados com a URL antiga param de funcionar.
- **Alterar o `name` de uma ferramenta** (`update_mcp_server_tool`) — agentes que chamam o nome antigo falham.
- **Remover uma ferramenta** (`remove_mcp_server_tool`).
- **Despublicar** (`unpublish_mcp_server`) — a URL daquele environment deixa de responder.
- **Despublicar, arquivar ou trocar o trigger de um fluxo** que e ferramenta — confira antes com `list_flow_mcp_servers(flowId)`. Trocar o trigger ou arquivar o fluxo desfaz o vinculo e descarta `name`/`title`.

Renomear o servidor (`name`) nao publica nada. Edicoes usam a `revision` atual (`get_mcp_server` ou a resposta da ultima escrita); revisao desatualizada volta 409 — releia e refaca.

## Ferramentas
Leitura: `list_mcp_servers`, `get_mcp_server`, `check_mcp_server_id_availability`, `list_mcp_server_tools`, `list_mcp_server_eligible_flows`, `list_flow_mcp_servers`.
Escrita (`confirm: true`): `create_mcp_server`, `update_mcp_server`, `add_mcp_server_tool`, `update_mcp_server_tool`, `remove_mcp_server_tool`, `publish_mcp_server`, `unpublish_mcp_server`, `configure_mcp_server_auth`.

## Skills relacionadas
- skill `build-flow` — construir o fluxo com trigger MCP Tool
- skill `apipass-patterns` — versoes, publicacao de fluxo e o modelo de MCP Server
- skill `apipass-gotchas` — depurar a execucao de uma chamada de ferramenta (cada chamada e uma execucao de fluxo)
