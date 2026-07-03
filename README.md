# APIPASS para Claude Code

Construa, publique, teste e investigue integracoes da APIPASS em linguagem natural, dentro do Claude Code. O plugin `apipass-integrations` conecta o Claude ao servidor MCP hospedado da APIPASS — voce descreve o que quer e ele planeja, monta, valida e executa, falando com a plataforma como voce.

Este repositorio e um **marketplace de plugins para o [Claude Code](https://claude.com/claude-code)**. O plugin `apipass-integrations` e composto por:

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

## Suporte
Problemas de login (`invalid redirect_uri`, `client not found`) sao de cadastro do client no Keycloak; 401/403 vem do gateway. Fale com o time de plataforma.
