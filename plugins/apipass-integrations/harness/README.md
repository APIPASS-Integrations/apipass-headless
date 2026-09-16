# Harness (TrueForge) — agente `apipass-integrations`

Arquivos consumidos pelo bootstrap do copiloto embarcado no console da APIPASS. O plugin do Claude Code **nao** usa esta pasta; ela existe para que plugin e copiloto compartilhem a mesma fonte de verdade (skills + prompt) numa mesma tag deste repositorio.

| Arquivo | Uso |
|---|---|
| `system-prompt.md` | System prompt do agente. Derivado das skills `build-flow`, `apipass-patterns`, `apipass-gotchas` e das regras do hook `hooks/confirm-publish.js`. |
| `agent.json` | Spec do agente no formato do TrueForge (`AgentSpec`: `model`, `instructions`, `mcp_servers`, `config`). |
| `../skills/index.json` | Manifesto das skills (`name`, `description`, `path`), gerado por `npm run skills:manifest`. Servido pelas tools `list_skills`/`load_skill` do servidor MCP. |

## Placeholders resolvidos no bootstrap

O `agent.json` nao contem valores de ambiente. O script de bootstrap substitui antes de enviar ao TrueForge:

| Placeholder | Significado |
|---|---|
| `${MODEL_NAME}` | FQN do modelo no catalogo do TrueForge (`provider/model`). |
| `${file:./system-prompt.md}` | Conteudo do arquivo `system-prompt.md` (relativo a esta pasta), inline no campo `instructions`. |

O campo `mcp_servers[0].name` (`apipass`) e o nome do connector registrado no TrueForge. Se o BFF criar um connector por conta, ele substitui esse nome no bootstrap.

## Regras

- `require_approval_for_tools` deve ser identico a lista `DESTRUCTIVE_TOOLS` do servidor MCP (`src/tools/instrument.ts`). Ao adicionar uma tool de escrita no servidor, adicione aqui e na secao 4 do `system-prompt.md`.
- Sem segredos, URLs internas ou ids de conta neste diretorio.
- Mudou skill, prompt ou spec? Incremente a versao em `plugin.json` + `marketplace.json`, registre no `CHANGELOG.md` e rode `npm run skills:manifest`.
