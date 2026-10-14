# APIPASS Headless

**APIPASS Headless** e operar a plataforma APIPASS **sem a interface grafica** — em linguagem natural, por meio de assistentes de IA. Este repositorio traz o plugin oficial `apipass-integrations`, que funciona em:

| Ferramenta | Como instala | Gate de confirmacao (publicar/testar) |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | marketplace de plugins | hook `PreToolUse` → `ask` |
| [Codex](https://developers.openai.com/codex) (CLI, IDE, app) | marketplace de plugins | `approval_mode: "prompt"` nas tools MCP |
| [GitHub Copilot](https://github.com/features/copilot) (CLI e VS Code) | marketplace de plugins | hook `PreToolUse` → `ask` |
| [Cursor](https://cursor.com) | marketplace de plugins (time) ou plugin local | hook `beforeMCPExecution` → `ask` |

Construa, publique, teste e investigue integracoes da APIPASS conversando com a IA — voce descreve o que quer e ela planeja, monta, valida e executa, falando com a plataforma (via servidor MCP hospedado) como voce.

O plugin `apipass-integrations` e composto por:

- **Skills** (padrao aberto [Agent Skills](https://agentskills.io)) — construir fluxos, pesquisar acoes, criar custom actions, revisar, documentar e analisar consumo.
- **Subagentes** especializados — pesquisa de acoes do catalogo e autoria de custom actions em sessao isolada (nas ferramentas que suportam subagentes).
- **Gate de confirmacao** — confirmacao obrigatoria antes de qualquer operacao com efeito real (publicar, despublicar, testar), implementado no mecanismo nativo de cada ferramenta.
- **Servidor MCP hospedado** — as ferramentas que falam com a plataforma da APIPASS; nada roda localmente.

## Requisitos
- Uma das ferramentas acima instalada.
- Uma conta APIPASS (o seu **accountName**, que resolve o realm do Keycloak).
- Acesso de rede ao servidor MCP de producao (`https://elb.apipass.com.br/mcp`).

## Instalacao

> Nao ha nada para rodar localmente: o plugin ja aponta para o servidor MCP hospedado da APIPASS.

### Claude Code
```
/plugin marketplace add https://github.com/APIPASS-Integrations/apipass-headless.git
/plugin install apipass-integrations@apipass-plugins
/reload-plugins
```
Atualizar: `/plugin marketplace update apipass-plugins` e `/reload-plugins`.

### Codex
```bash
codex plugin marketplace add APIPASS-Integrations/apipass-headless
codex plugin add apipass-integrations@apipass-plugins
```
Ou pelo `/plugins` dentro do Codex. Atualizar: `codex plugin marketplace upgrade apipass-plugins`. Invoque uma skill citando-a (ex. `$build-flow`) ou apenas descreva o pedido.

### GitHub Copilot CLI
```bash
copilot plugin marketplace add APIPASS-Integrations/apipass-headless
copilot plugin install apipass-integrations@apipass-plugins
```
Ou pelo `/plugin` dentro do Copilot CLI.

### GitHub Copilot no VS Code
Habilite os agent plugins (`chat.plugins.enabled`), adicione o marketplace `APIPASS-Integrations/apipass-headless` e instale `apipass-integrations` pela visao de Extensions (`@agentPlugins`). O VS Code le o formato de plugin do Claude diretamente (skills, `.mcp.json` e hooks).

### Cursor
- **Time/empresa:** Dashboard → *Plugins & MCPs* → *Add Marketplace* → *Import from Repo* → `https://github.com/APIPASS-Integrations/apipass-headless`. Depois, *Customize* → *Install*.
- **Local:** copie `plugins/apipass-integrations` para `~/.cursor/plugins/local/apipass-integrations` e rode *Developer: Reload Window*.

### Outras ferramentas (instalacao manual)
Qualquer agente com suporte a MCP e Agent Skills funciona:
1. Cadastre o servidor MCP HTTP `apipass` apontando para `https://elb.apipass.com.br/mcp`.
2. Copie as pastas de `plugins/apipass-integrations/skills/` para o diretorio de skills da ferramenta (ex. `~/.agents/skills/`, `.github/skills/`).
3. Configure a ferramenta para **pedir aprovacao** em `publish_flow`, `unpublish_flow` e `run_test_flow`.

## Primeiro uso (login)
Cada pessoa autentica com a **propria conta**. Ao pedir a primeira acao (ex. "liste meus projetos na apipass"), a IA vai responder que voce precisa logar. Rode (ou peca para a IA rodar):

```
apipass_login account_name="SUA-CONTA"
```

Abra a URL retornada no navegador, autorize no Keycloak da sua conta e volte ao chat. O token fica na sua sessao e renova sozinho. Ferramentas uteis: `apipass_auth_status` (ver estado) e `apipass_logout` (sair).

## O que da pra fazer
- **Construir fluxos**: "construa um fluxo que sincronize X com Y". A IA descobre as acoes (catalogo + acoes fixas), monta os passos e valida antes de salvar.
- **Versionar e publicar**: salvar o development -> criar versao -> publicar no environment (com confirmacao).
- **Testar**: rodar um teste do fluxo com um payload (com confirmacao).
- **Investigar execucoes**: listar logs, abrir uma execucao, ler o payload de um passo, ver resumos.
- **Re-executar/parar** execucoes (com confirmacao explicita).

Operacoes com efeito real (criar/salvar/publicar/testar/retry/stop) sempre pedem confirmacao antes.

## Skills disponiveis

No Claude Code as skills viram comandos `/apipass-integrations:<skill>`; no Codex, `$<skill>`; no Copilot e no Cursor, `/<skill>`. Em todas, basta descrever o pedido.

Construcao de fluxos:
- `/apipass-integrations:build-flow` — construir/alterar um fluxo de integracao (ponto de entrada)
- `/apipass-integrations:build-agent-flow` — construir/alterar um fluxo de agente de IA (RAG, base de conhecimento)
- `/apipass-integrations:research-action` — pesquisar uma acao do catalogo
- `/apipass-integrations:create-action` — criar uma custom action a partir da doc de uma API

Referencia:
- `/apipass-integrations:apipass-actions` — catalogo + anatomia do FlowStep
- `/apipass-integrations:apipass-agent-actions` — catalogo de acoes de IA (Agent Builder)
- `/apipass-integrations:apipass-patterns` — estrutura, versionar, publicar, testar
- `/apipass-integrations:apipass-gotchas` — erros comuns e debug de execucao

Analise e manutencao:
- `/apipass-integrations:review-flow` — auditar um fluxo contra boas praticas
- `/apipass-integrations:diff-versions` — comparar versoes de um fluxo
- `/apipass-integrations:document-flows` — gerar documentacao (Word/PDF) dos fluxos de um projeto
- `/apipass-integrations:apipass-usage` — analise de consumo/uso da conta

Conta:
- `/apipass-integrations:set-account` — informar a conta (realm) no login

## Como contribuir
Contribuicoes sao bem-vindas — desde reportar um problema ate propor uma nova skill.

### Reportar bugs e sugerir melhorias
Abra uma [issue](https://github.com/APIPASS-Integrations/apipass-headless/issues) descrevendo o que aconteceu (ou o que voce gostaria). Para bugs, inclua o comando/pedido que usou, o que esperava e o que ocorreu.

### Enviar mudancas
1. Faca um fork do repositorio e crie uma branch a partir da `main` (ex. `feat/minha-skill`, `fix/descricao-curta`).
2. Faca as alteracoes seguindo a estrutura e as convencoes abaixo.
3. Teste localmente (veja adiante).
4. Abra um Pull Request para a `main` descrevendo a mudanca e o motivo.

### Estrutura do repositorio
```
.claude-plugin/marketplace.json          # marketplace (Claude Code; tambem lido por Codex e Copilot)
.cursor-plugin/marketplace.json          # marketplace do Cursor
.github/plugin/marketplace.json          # espelho para o Copilot (gerado pelo build)
plugins/apipass-integrations/            # FONTE UNICA do plugin
  .claude-plugin/plugin.json             # manifesto Claude/Copilot/VS Code (versao = fonte da verdade)
  .codex-plugin/plugin.json              # manifesto Codex (MCP com approval_mode "prompt")
  .cursor-plugin/plugin.json             # manifesto Cursor
  .mcp.json                              # servidor MCP hospedado
  skills/<nome>/SKILL.md                 # skills (padrao Agent Skills, neutras de ferramenta)
  agents/<nome>.md                       # subagentes especializados
  hooks/hooks.json                       # gate de confirmacao (Claude, Copilot, VS Code)
  hooks/cursor-hooks.json                # gate de confirmacao (Cursor)
  hooks/confirm-publish.js               # script do gate (formatos Claude e Cursor)
scripts/build.mjs                        # sincroniza versoes e valida os manifestos
```

### Convencoes
- **Idioma:** skills, agentes e documentacao em portugues (pt-BR), como o restante do plugin.
- **Skills neutras de ferramenta:** cada skill vive em `skills/<nome>/SKILL.md` com frontmatter (`name` igual ao diretorio, `description` com ate 1024 caracteres). A `description` e o que faz a IA decidir quando carregar a skill — seja especifico. Para citar outra skill, escreva "skill `<nome>`" (nao `/apipass-integrations:<nome>`, que so existe no Claude). Recursos de uma ferramenta especifica (subagentes, `AskUserQuestion`, skills de outros plugins) devem ser citados como opcionais, com alternativa.
- **Versao:** ao mudar o comportamento do plugin, incremente a `version` **so** em `plugins/apipass-integrations/.claude-plugin/plugin.json`, rode `node scripts/build.mjs` (propaga para todos os manifestos) e adicione uma entrada no [CHANGELOG.md](CHANGELOG.md). O CI (`node scripts/build.mjs --check`) falha se algo ficar dessincronizado.
- **Nunca** embuta credenciais, tokens ou URLs internas no codigo ou na documentacao.

### Testar localmente
- **Claude Code:** `/plugin marketplace add /caminho/para/apipass-headless`, `/plugin install apipass-integrations@apipass-plugins`, `/reload-plugins` (rode de novo apos editar).
- **Codex:** `codex plugin marketplace add /caminho/para/apipass-headless` e `codex plugin add apipass-integrations@apipass-plugins`.
- **Copilot CLI:** `copilot --plugin-dir /caminho/para/apipass-headless/plugins/apipass-integrations`.
- **Cursor:** copie/linke `plugins/apipass-integrations` em `~/.cursor/plugins/local/` e rode *Developer: Reload Window*.

## Suporte
Problemas de login (`invalid redirect_uri`, `client not found`) sao de cadastro do client no Keycloak; 401/403 vem do gateway. Fale com o time de plataforma.
