---
name: set-account
description: Como informar a conta APIPASS (accountName) que resolve o realm do Keycloak no login. No servidor hospedado, a conta vai como argumento do apipass_login (por usuario/sessao).
disable-model-invocation: true
argument-hint: "[account-name]"
---

# Conta APIPASS (realm) no login

A APIPASS e multi-realm: **um realm do Keycloak por cliente, resolvido pelo `accountName`**. No servidor MCP hospedado (multi-usuario), cada pessoa informa a propria conta **no login** — nao ha config global.

## Como usar
1. Rode `apipass_login` com seu `account_name`:
   ```
   apipass_login account_name="sua-conta"
   ```
   O servidor resolve o realm, retorna a URL de autorizacao.
2. Abra a URL no navegador, autorize no Keycloak da sua conta.
3. O token fica vinculado a sua sessao e renova sozinho. `apipass_auth_status` mostra o estado; `apipass_logout` descarta.

## Observacoes
- O `account_name` so e necessario para escolher o realm no login; depois disso, o API Gateway deriva a identidade do proprio token.
- Em desenvolvimento local (servidor na sua maquina), da para definir um realm default via `APIPASS_KEYCLOAK_REALM` no `.env` do servidor — assim `apipass_login` funciona sem argumento. Em producao hospedada, sempre informe o `account_name`.
