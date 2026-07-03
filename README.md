# APIPASS Headless para Claude Code

**APIPASS Headless** é operar a plataforma APIPASS **sem a interface grafica** — em linguagem natural, por meio de assistentes de IA. Este repositorio traz a primeira integracao: o plugin oficial `apipass-integrations` para o [Claude Code](https://claude.com/claude-code).

Construa, publique, teste e investigue integracoes da APIPASS conversando com o Claude — voce descreve o que quer e ele planeja, monta, valida e executa, falando com a plataforma (via servidor MCP hospedado) como voce.

Este repositorio e um **marketplace de plugins para o Claude Code**. O plugin `apipass-integrations` e composto por:

- **Skills** (comandos `/apipass-integrations:*`) — construir fluxos, pesquisar acoes, criar custom actions, revisar, documentar e analisar consumo.
- **Subagentes** especializados — pesquisa de acoes do catalogo e autoria de custom actions em sessao isolada.
- **Hooks** — confirmacao obrigatoria antes de qualquer operacao com efeito real (publicar, testar, re-executar).
- **Servidor MCP hospedado** — as ferramentas que falam com a plataforma da APIPASS; nada roda localmente.

## Requisitos
- [Claude Code](https://claude.com/claude-code) instalado.
- Uma conta APIPASS (o seu **accountName**, que resolve o realm do Keycloak).
- Acesso de rede ao servidor MCP de producao (`https://elb.apipass.com.br/mcp`).

## Instalacao
No Claude Code:

```
/plugin marketplace add https://github.com/APIPASS-Integrations/apipass-plugins.git
/plugin install apipass-integrations@apipass-plugins
/reload-plugins
```

> Nao ha nada para rodar localmente: o plugin ja aponta para o servidor MCP hospedado da APIPASS.

## Primeiro uso (login)
Cada pessoa autentica com a **propria conta**. Ao pedir a primeira acao (ex. "liste meus projetos na apipass"), o Claude vai responder que voce precisa logar. Rode:

```
apipass_login account_name="SUA-CONTA"
```

Abra a URL retornada no navegador, autorize no Keycloak da sua conta e volte ao Claude. O token fica na sua sessao e renova sozinho. Ferramentas uteis: `apipass_auth_status` (ver estado) e `apipass_logout` (sair).

## O que da pra fazer
- **Construir fluxos**: "construa um fluxo que sincronize X com Y". O Claude descobre as acoes (catalogo + acoes fixas), monta os passos e valida antes de salvar.
- **Versionar e publicar**: salvar o development -> criar versao -> publicar no environment (com confirmacao).
- **Testar**: rodar um teste do fluxo com um payload (com confirmacao).
- **Investigar execucoes**: listar logs, abrir uma execucao, ler o payload de um passo, ver resumos.
- **Re-executar/parar** execucoes (com confirmacao explicita).

Operacoes com efeito real (criar/salvar/publicar/testar/retry/stop) sempre pedem confirmacao antes.

## Atualizacoes
Quando houver uma nova versao do plugin:

```
/plugin marketplace update apipass-plugins
/reload-plugins
```

## Comandos (skills) disponiveis

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
Abra uma [issue](https://github.com/APIPASS-Integrations/apipass-plugins/issues) descrevendo o que aconteceu (ou o que voce gostaria). Para bugs, inclua o comando/pedido que usou, o que esperava e o que ocorreu.

### Enviar mudancas
1. Faca um fork do repositorio e crie uma branch a partir da `main` (ex. `feat/minha-skill`, `fix/descricao-curta`).
2. Faca as alteracoes seguindo a estrutura e as convencoes abaixo.
3. Teste localmente (veja adiante).
4. Abra um Pull Request para a `main` descrevendo a mudanca e o motivo.

### Estrutura do repositorio
```
.claude-plugin/marketplace.json          # catalogo do marketplace (nome, versao, descricao)
plugins/apipass-integrations/
  .claude-plugin/plugin.json             # manifesto do plugin (versao, metadados)
  .mcp.json                              # servidor MCP hospedado que o plugin usa
  skills/<nome>/SKILL.md                 # comandos /apipass-integrations:<nome>
  agents/<nome>.md                       # subagentes especializados
  hooks/hooks.json + *.js                # gates de confirmacao (PreToolUse)
```

### Convencoes
- **Idioma:** skills, agentes e documentacao em portugues (pt-BR), como o restante do plugin.
- **Skills:** cada skill vive em `skills/<nome>/SKILL.md` com frontmatter (`name`, `description`). A `description` e o que faz o Claude decidir quando carregar a skill — seja especifico.
- **Versao:** ao mudar o comportamento do plugin, incremente a `version` em **`plugin.json` e `marketplace.json`** (os dois devem ficar iguais) e adicione uma entrada no [CHANGELOG.md](CHANGELOG.md).
- **Nunca** embuta credenciais, tokens ou URLs internas no codigo ou na documentacao.

### Testar localmente
Aponte o Claude Code para a sua copia local em vez do repositorio remoto:

```
/plugin marketplace add /caminho/para/apipass-plugins
/plugin install apipass-integrations@apipass-plugins
/reload-plugins
```

Depois de editar uma skill, agente ou hook, rode `/reload-plugins` para recarregar sem reinstalar.

## Suporte
Problemas de login (`invalid redirect_uri`, `client not found`) sao de cadastro do client no Keycloak; 401/403 vem do gateway. Fale com o time de plataforma.
