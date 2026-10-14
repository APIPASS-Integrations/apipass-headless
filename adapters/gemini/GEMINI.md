# APIPASS Integrations (Gemini CLI)

Esta extensao conecta o Gemini CLI a plataforma APIPASS (iPaaS) pelo servidor MCP `apipass`
e traz skills com o conhecimento da plataforma. Regras gerais:

- **Login:** se uma ferramenta `apipass` responder `login_necessario`, siga a skill
  `set-account` (rode `apipass_login` com o `account_name` do usuario, mostre a URL e faca
  poll de `apipass_auth_status`).
- **Construir ou alterar fluxos:** ative a skill `build-flow` antes de chamar
  `create_flow` / `save_flow_development` (ou `build-agent-flow` para agentes de IA/RAG).
- **Custom actions:** skill `create-action`. **Pesquisa de acoes:** skill `research-action`.
- **Depurar execucoes:** skill `apipass-gotchas`. **Consumo/uso:** skill `apipass-usage`.
- **Revisar, comparar versoes, documentar:** skills `review-flow`, `diff-versions`,
  `document-flows`.
- **Efeito real:** criar, salvar, publicar, testar, re-executar ou parar execucoes tem
  efeito real na conta do usuario. Confirme o plano com o usuario antes. `publish_flow`,
  `unpublish_flow` e `run_test_flow` sempre pedem aprovacao (policy da extensao).
- Nunca invente campos de acoes nem embuta credenciais em steps — descubra pelo catalogo e
  referencie autorizacoes existentes.
