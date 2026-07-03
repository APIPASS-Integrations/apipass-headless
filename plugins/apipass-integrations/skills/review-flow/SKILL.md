---
name: review-flow
description: >
  Audita um fluxo APIPASS contra boas práticas e convenções da plataforma — arquitetura,
  tratamento de erros, autorização e credenciais, código NodeJS, queries SQL, nomenclatura,
  variáveis de environment, sincronismo e persistência.
  Use quando o usuário pedir para revisar, auditar, checar ou analisar um fluxo —
  "revise o fluxo X", "tem algo errado neste fluxo?", "analise a arquitetura do fluxo",
  "verifique boas práticas", "code review do fluxo", "o que pode melhorar neste fluxo".
argument-hint: "[nome ou id do fluxo]"
---

# Review de Fluxo APIPASS

Audita um fluxo existente contra as convenções e boas práticas da plataforma APIPASS e produz um relatório com findings classificados por severidade.

---

## 1. Autenticação

Verificar `apipass_auth_status`. Se não autenticado, chamar `apipass_login` antes de continuar.

---

## 2. Resolução do Fluxo

- Se o usuário passou um **nome**: chamar `list_flows` e localizar pelo nome (case-insensitive).
- Se passou um **ID**: usar diretamente.
- Se ambíguo: perguntar ao usuário qual fluxo deseja revisar (listar as opções encontradas).

---

## 3. Coleta de Dados

Executar **em paralelo**:

```
get_flow_development(flowId)          → estrutura completa (steps, counters, logEnabled)
get_flow_info(flowId)                 → metadados (nome, trigger, projeto)
get_published_environments_for_flow(flowId) → environments publicados (para regra S1)
```

Para fluxos com steps NodeJS ou custom actions, chamar também:
```
get_custom_action_file(actionId)  → inspecionar código JS (regras JS1–JS6)
```

Para steps SQL, extrair as queries dos campos `rawData`/`inputData` para análise estática (regras SQL1–SQL5) — não requer chamada adicional, os dados já vêm em `get_flow_development`.

### 3a. Subfluxos Aninhados

Após coletar o fluxo principal, identificar **todos os subfluxos referenciados**:

- **RunChildFlow** (`type: ".utility.runchildflow.RunChildFlow"` ou similar): extrair o `flowId` do subfluxo referenciado no `inputData`/`mappingAttributes`.
- **Steps AMS** (`coreRouteType: "AMS_SEND_MESSAGE"`): localizar o fluxo consumidor da fila — geralmente documentado no campo `documentation` do step ou identificável pelo nome da fila. Localizar via `list_flows` filtrando pelo nome da fila.

Para cada subfluxo identificado, executar o mesmo ciclo de coleta (`get_flow_development`, `get_flow_info`, `get_published_environments_for_flow`) e aplicar **todas as mesmas regras de revisão** (seção 4). Reportar os findings de cada subfluxo em seção própria no relatório, identificada pelo nome do subfluxo.

**O processo é recursivo:** após revisar cada subfluxo, identificar novamente todos os `RunChildFlow` e steps AMS referenciados *nesse* subfluxo e repetir o ciclo para cada um deles. Continuar até que não haja mais subfluxos novos a revisar. Cada subfluxo deve ser revisado apenas uma vez — manter uma lista de `flowId` já revisados para evitar loops em caso de referências circulares.

---

## 4. Análise — Regras de Revisão

Aplicar **todas** as regras abaixo ao array de steps retornado por `get_flow_development`.

### 4a. Estrutura e Integridade (Crítico)

| # | Regra | Como detectar |
|---|-------|---------------|
| C1 | IDs duplicados ou vazios | Verificar unicidade de todos os `id` no array de steps |
| C2 | Counter `lastGeneratedStepId` incorreto | Deve ser `max(sufixo numérico dos steps regulares) + 1`; step `a999` NÃO conta |
| C3 | Counter `lastGeneratedLoopId` incorreto | Deve ser `(número de loops criados) + 1` |
| C4 | Step de Stop (`a999`) ausente | Verificar se existe step com `id: "a999"` e `type: ".StopV2Step"` |
| C5 | Stop sem campo `responses` | `.StopV2Step` sem `responses` → `publish_flow` falha com HTTP 400. **Ordem das responses:** a response com `default: true` é sempre a primeira no array, mas o engine a executa apenas quando nenhuma das outras condições é satisfeita — o comportamento de fallback é definido pelo flag `default: true`, não pela posição no array. As responses condicionais devem vir após a Default no array, e o engine as avalia independentemente da ordem. |
| C6 | Tipo descontinuado `.StopStep` | Deve ser `.StopV2Step` |
| C7 | Tipo descontinuado `.conditional.SwitchV2` | Deve ser `.utility.switchutility.SwitchUtility` |
| C8 | Loop v1/v2 (não-LoopCanvas) | Deve ser `.utility.loop.LoopCanvas` |
| C9 | Step sem `positionX` ou `positionY` | Todos os steps exigem coordenadas |
| C10 | Interpolação com sintaxe `${...}` pura | Deve ser `{{$...}}` — varrer `rawData`, `mappingAttributes`, `inputData`. **Exceção:** a sintaxe `${ return <expressão> }` é válida na plataforma e permite executar qualquer expressão JavaScript válida inline — operadores lógicos, ternários, manipulação de strings, cálculos, chamadas de métodos, etc. Ex.: `${ return '{{$.a9.message.message}}' || 'Valor padrão' }`. Não reportar como erro — é um recurso intencional da plataforma. |
| C11 | Referência a output sem `.body` | Ex.: `{{$.a0.campo}}` em vez de `{{$.a0.body.campo}}`. **Exceção:** o step Logger (`coreRouteType: "LOGGER_UTILITY"`) NÃO usa `.body` — seus campos são acessados diretamente como `{{$.aN.message}}` e `{{$.aN.level}}`. O campo `message` contém exatamente o que foi passado em `logMessage`: pode ser uma string simples ou um objeto JSON. Se o `logMessage` foi um JSON com campo `message`, então `{{$.aN.message.message}}` é válido e acessa esse campo interno. |
| C12 | `failOnError: true` sem tratamento de erro | Se qualquer step tem `failOnError: true`, deve haver ao menos uma das duas abordagens de tratamento: **(1) Response condicional no Stop (`a999`)** — o engine redireciona automaticamente ao Stop em caso de falha; sem response condicional o chamador recebe apenas a response default sem indicação do erro real. A condição genérica recomendada para capturar qualquer falha de step com `failOnError: true` é: `input: {{$.flowExecution.status}}` / condição: `(Text) Does Not Match` / valor esperado: `OK` — com descrição clara de que se trata de tratamento de erro genérico. **(2) Conector "Tratar Erro"** — conectado diretamente ao step com `failOnError: true`, permite desviar o erro para steps de tratamento personalizado (log, alerta, transformação da mensagem de erro) antes de chegar ao Stop. Ambas as abordagens são válidas e podem ser combinadas. |

### 4b. Tratamento de Erros e Alertas (Crítico)

| # | Regra | Como detectar |
|---|-------|---------------|
| C13 | ErrorHandler sem step de alerta | ErrorHandler existente mas sem nenhum step de envio (email, Slack, webhook) dentro dele — erros somem sem rastro |
| C14 | Response de erro sem mensagem descritiva | Stop response com status 4xx/5xx e `responseData` vazio ou sem campo `message`/`error` — usuário final não entende o que ocorreu |
| C15 | Step externo sem `failOnError` e sem verificação inline | Steps HTTP/SQL com `failOnError: false` e sem Switch após verificando o resultado — erros passam silenciosamente |

### 4c. Variáveis de Environment vs. Valores Fixos (Crítico)

| # | Regra | Como detectar |
|---|-------|---------------|
| C16 | URL, IP ou token hardcoded nos steps | Strings com padrão `http://`, `https://`, endereços IP (`\d+\.\d+\.\d+\.\d+`), portas ou strings longas que parecem tokens em `rawData`/`mappingAttributes`/`inputData`. **Exceções — não reportar como C16:** (1) **Path de trigger REST usado em payload de reprocessamento num único step NodeJS**: o trigger REST da APIPASS não expõe o path configurado de forma dinâmica (`$.trigger.path` não existe), portanto hardcodar o path no payload é inevitável — é um acoplamento documentado, não um erro de configuração; se o path mudar, o step deverá ser atualizado junto. (2) **Account/project UUID da plataforma APIPASS embutido numa URL interna** (`https://core.apipass.com.br/api/{uuid}/...`): esse UUID é o identificador estável do projeto/conta no APIPASS e não varia entre environments — não é uma credencial nem um valor de ambiente; não sugerir extrair para variável de environment. |
| C17 | Mesmo valor hardcoded repetido em múltiplos steps | Valor idêntico em 2+ steps — candidato a variável de environment para não quebrar na promoção dev→hml→prod |

### 4d. Switch, Loop e Fluxo de Controle (Aviso)

| # | Regra | Como detectar |
|---|-------|---------------|
| W1 | Switch sem condição `default` | Step `SwitchUtility` sem um case marcado como default |
| W2 | Switch com apenas 1 branch | Switch com menos de 2 condições — desnecessário |
| W3 | Loop sem steps internos | LoopCanvas com `loopSteps: []` ou campo ausente |
| W4 | Step inacessível (unreachable) | Steps que não aparecem no `previousSteps` de nenhum outro step (exceto trigger e a999) |
| W4b | Steps sem `nextSteps` — falso positivo | **Não** reportar como rota desconectada steps com `nextSteps: []` ou ausente. O engine trata a ausência de conexão como rota implícita para o Stop (`a999`), desde que o fluxo tenha ao menos um step com conexão explícita a `a999`. Só é problema real se **nenhum** step do fluxo conectar ao Stop. |
| W4c | Concatenação de steps mutuamente exclusivos — falso positivo | O padrão `{{$.a6.body}}{{$.a7.body}}` em um mesmo campo é **correto e intencional** quando `a6` e `a7` são branches exclusivos de um Switch: o engine atribui o valor do step que foi executado. **Não** sugerir `{{$.a6.body \|\| $.a7.body}}` — essa sintaxe causa erro na plataforma. |
| W5 | RunChildFlow sem uso do output | Step filho chamado mas `{{$.aN.body...}}` não referenciado por nenhum step posterior |
| W5b | `errorMessage` de RunChildFlow com conteúdo indefinido — falso positivo | **Não** reportar como problema o uso de `{{$.aN.body}}` no `errorMessage` de um ERROR_ROUTE dentro de um caminho "Tratar Erro" quando `aN` é um `RunChildFlow`. O body do RunChildFlow contém a response do Stop do subfluxo filho, que pode ser estruturada e descritiva. **Antes de reportar**, verificar se o Stop do subfluxo filho tem responses de erro configuradas (`status: "ERROR"` ou condição genérica `{{$.flowExecution.status}}` ≠ `OK`). Se o filho tiver responses de erro, o body estará populado com dados úteis e não há problema. Só reportar se o filho **não tiver** nenhuma response de erro no Stop — nesse caso o body pode ser nulo ou genérico em cenários de falha. |

### 4e. Sincronismo, Assincronismo e Performance (Aviso)

| # | Regra | Como detectar |
|---|-------|---------------|
| W6 | Fluxo síncrono com operações pesadas | Trigger HTTP síncrono + múltiplos SQL/HTTP em cadeia ou loops grandes sem RunChildFlow ou AMS — caller fica bloqueado |
| W7 | Fluxo complexo sem padrão master/subfluxo | Mais de 15 steps lineares sem nenhum `RunChildFlow` — sugerir quebra em orquestrador + subfluxos |
| W8 | Loop com chamadas externas por item sem AMS | LoopCanvas iterando coleção e fazendo HTTP/SQL por item — candidato a fila AMS para desacoplamento e resiliência |

### 4e-bis. AMS — Boas Práticas (Aviso/Crítico)

Aplicar a fluxos com trigger `.trigger.ams.TriggerAMSConsumeMessage` ou steps `AMS_SEND_MESSAGE`.

| # | Regra | Sev. | Como detectar |
|---|-------|------|---------------|
| AMS1 | Nome de fila hardcoded | 🔴 | `queueName` sem `{{$.stage.name}}-` como prefixo — a mesma fila será usada em dev e prod, causando consumo cruzado de mensagens |
| AMS2 | `failOnError: false` no AMS_SEND_MESSAGE | 🟡 | Publicação na fila com `failOnError: false` — falha silenciosa perde a mensagem sem sinalizar o caller |
| AMS3 | Fluxo master não retorna imediatamente após publicar | 🟡 | Steps após `AMS_SEND_MESSAGE` que não são o `StopV2Step` — o master deve publicar e retornar; processamento vai para o subfluxo |
| AMS4 | `deleteStrategy` ausente ou incorreto em trigger AMS | 🟡 | Trigger AMS sem `deleteStrategy` explícito — padrão `IMMEDIATELY` não garante retry em falha; usar `ON_SUCCESS` quando resiliência é crítica |
| AMS5 | Subfluxo AMS sem tratamento de idempotência | 🔵 | Consumidor AMS com `deleteStrategy: "IMMEDIATELY"` processando operações não-idempotentes (ex.: INSERT sem verificar duplicatas) — falha antes do commit não faz retry mas falha após pode re-entregar |
| AMS6 | `queueName` diferente entre publisher e consumer | 🔴 | O nome da fila no `AMS_SEND_MESSAGE` (master) e no trigger AMS (subfluxo) não coincidem — mensagens nunca chegam ao consumidor |
| AMS7 | Payload publicado sem `idCorrelacao` | 🔵 | Mensagem AMS sem campo de correlação (`idCorrelacao`, `correlationId`, etc.) — dificulta rastreabilidade entre execuções do master e do subfluxo |

### 4f. Persistência de Dados (Aviso)

| # | Regra | Como detectar |
|---|-------|---------------|
| W9 | Dados críticos sem persistência | Fluxo que processa pedidos, transações ou notificações sem nenhum step SQL INSERT/UPDATE, AOS ou escrita em storage — risco de perda em falha |
| W10 | Output de subfluxo usado sem persistência intermediária | RunChildFlow seguido de uso direto do resultado sem salvar — retry inconsistente |

### 4f-bis. AOS — Boas Práticas (Aviso/Crítico)

Aplicar a fluxos com steps `AOS_FIND_ONE_BY_QUERY`, `AOS_UPDATE`, `AOS_INSERT` ou `AOS_DELETE` (coreRouteType `MONGODB_*`).

| # | Regra | Sev. | Como detectar |
|---|-------|------|---------------|
| AOS1 | `database` hardcoded (sem `{{$.stage.name}}`) | 🔴 | Campo `database` com valor fixo em vez de `"{{$.stage.name}}"` — dados de dev e prod vão para o mesmo banco |
| AOS2 | `authProvider` ausente ou incorreto em step AOS | 🔴 | Step AOS sem `authProvider: "APIPASS_OBJECT_STORE"` ou sem `authId` válido — chamada falhará em runtime |
| AOS3 | Filter vazio ou sem cláusula `_id`/índice em UPDATE/DELETE | 🔴 | `filter: "{}"` ou filter sem campo indexado em `AOS_UPDATE`/`AOS_DELETE` — operação afetará todos os documentos da coleção |
| AOS4 | Query `$set` montada inline em `inputData` em vez de via NodeJS | 🟡 | Objeto MongoDB com operadores (`$set`, `$push`, etc.) diretamente no `inputData.query` sem interpolação de step NodeJS — dificulta manutenção e valores dinâmicos |
| AOS5 | AOS_INSERT sem `_id` customizado em entidade identificável | 🟡 | INSERT em coleção de configurações/entidades sem definir `_id` explícito — gera ObjectId aleatório e dificulta lookup por chave de negócio |
| AOS6 | Múltiplas operações AOS de escrita em sequência sem verificação de erro | 🟡 | Dois ou mais steps AOS_UPDATE/INSERT/DELETE consecutivos com `failOnError: false` — falha parcial não é detectada |
| AOS7 | `collection` hardcoded com nome de ambiente | 🟡 | Nome de coleção com `_dev`, `_prod`, `_hml` embutido — usar `database: "{{$.stage.name}}"` + coleção sem sufixo de ambiente |
| AOS8 | GET sem verificação de documento nulo | 🔵 | `AOS_FIND_ONE_BY_QUERY` seguido de uso direto de `$.aN.body.document.campo` sem Switch verificando se o documento existe — NullPointerException em runtime se registro não encontrado |

### 4g. Nomenclatura e Documentação (Aviso)

| # | Regra | Como detectar |
|---|-------|---------------|
| W11 | Label vazio, igual ao ID ou muito curto | `label` ausente, igual ao `id` (ex.: `"a0"`) ou com menos de 5 caracteres |
| W12 | Label técnico em vez de negócio | Labels como `"HttpRequest"`, `"NodeJS"`, `"Switch"` sem contexto de negócio |
| W13 | Steps complexos sem descrição/comentário | Steps NodeJS ou Switch com lógica não trivial sem campo `description` preenchido |
| W14 | Labels inconsistentes no mesmo fluxo | Mistura de idiomas (pt + en) ou formatos diferentes nos labels |

### 4h. Variáveis de Environment (Aviso)

| # | Regra | Como detectar |
|---|-------|---------------|
| W15 | URL de API completa hardcoded | URL completa fixa em `rawData`/`inputData` — pode quebrar ao promover entre environments |
| W16 | Configuração de banco ou fila hardcoded | String de conexão, nome de fila, schema ou tabela como valor fixo |

### 4i. Autorização e Credenciais (Crítico/Aviso)

Verificar **todos os steps** que fazem chamadas externas (HTTP, SQL, email, webhooks, connectors de catálogo).

| # | Regra | Sev. | Como detectar |
|---|-------|------|---------------|
| AUTH1 | Credencial ausente em step que exige autenticação | 🔴 | Step HTTP/conector sem `authId` + `authProvider` quando o endpoint claramente requer auth — comparar com `list_authorizations` |
| AUTH2 | `authId` hardcoded como string literal não-UUID | 🔴 | `authId` com valor que não parece um ID de autorização válido (ex.: nome de usuário, senha, token diretamente no campo) |
| AUTH3 | Credencial interpolada diretamente em `rawData` | 🔴 | Strings que parecem senhas, tokens ou API keys embutidas em body/headers de `rawData` em vez de usar `get_authorization_interpolation_fields` |
| AUTH4 | Múltiplos steps usando `authId` diferente para o mesmo serviço | 🟡 | Dois ou mais steps conectando ao mesmo host/serviço com `authId` distintos — pode indicar credencial duplicada ou inconsistência |
| AUTH5 | Step sem `authProvider` mas com `authId` preenchido | 🟡 | Os dois campos devem estar presentes juntos — um sem o outro causa erro de runtime |
| AUTH6 | Autorização de outro projeto/ambiente usada diretamente | 🔵 | `authId` que, ao verificar com `get_authorization`, pertence a um projeto diferente — risco de dependência cruzada |

### 4j. Código NodeJS — Boas Práticas (Aviso/Sugestão)

Aplicar ao `jsFileAsString` de cada custom action usada no fluxo (obtido via `get_custom_action_file`).

| # | Regra | Sev. | Como detectar |
|---|-------|------|---------------|
| JS1 | `try/catch` usado sem necessidade | 🔵 | `try/catch` **não** é prática padrão em steps NodeJS da APIPASS — a ausência é intencional: erros não tratados interrompem o fluxo naturalmente, que é o comportamento esperado. Usar `try/catch` apenas quando uma biblioteca específica exige (ex.: `yup` em validações, onde o catch captura os erros de validação para tratamento inline). Reportar apenas se `try/catch` estiver suprimindo erros que deveriam interromper o fluxo (ex.: catch vazio ou catch que retorna sucesso independente do erro). |
| JS2 | `console.log` com dados sensíveis | 🟡 | `console.log` logando objetos de request/response inteiros, especialmente campos como `password`, `token`, `authorization`, `secret` |
| JS3 | Callback assíncrono sem `await` | 🟡 | Chamadas a funções assíncronas (ex.: `fetch`, funções de lib) sem `await` — resultado silenciosamente ignorado |
| JS4 | Retorno sem estrutura `{ body: ... }` | 🔴 | Função retornando objeto plano sem envolver em `{ body: ... }` — o próximo step não conseguirá acessar os dados via `{{$.aN.body.campo}}` |
| JS5 | Uso de `var` em vez de `const`/`let` | 🔵 | `var` em qualquer lugar do código — usar `const` por padrão, `let` quando reatribuição necessária |
| JS6 | Lógica de negócio complexa sem comentários | 🔵 | Blocos de código com mais de 15 linhas, expressões regulares, cálculos financeiros ou transformações de data sem nenhum comentário explicativo |
| JS7 | Manipulação de data/hora sem fuso horário explícito | 🟡 | `new Date()`, `Date.now()` ou libs de data sem especificação de timezone — risco de inconsistência entre ambientes (padrão deve ser UTC-3 para Brasil) |
| JS8 | Credencial ou URL hardcoded no código JS | 🔴 | Strings com padrão de token, senha, IP ou URL de ambiente embutidas no código em vez de recebidas via `input.configurations` |

### 4k. Queries SQL — Boas Práticas e Performance (Aviso/Sugestão)

Extrair queries dos campos `rawData`/`inputData` dos steps SQL para análise estática.

| # | Regra | Sev. | Como detectar |
|---|-------|------|---------------|
| SQL1 | `SELECT *` sem projeção explícita | 🟡 | Query com `SELECT *` — retorna colunas desnecessárias, aumenta payload e dificulta manutenção; listar colunas explicitamente |
| SQL2 | Query sem `WHERE` em tabela de dados transacionais | 🔴 | `UPDATE`, `DELETE` ou `SELECT` em tabela que claramente armazena registros (ex.: `pedidos`, `usuarios`, `transacoes`) sem cláusula `WHERE` — risco de full-table scan ou deleção em massa |
| SQL3 | Parâmetro interpolado diretamente na query (SQL Injection) | 🔴 | Valor de input interpolado com mustache diretamente na query: `WHERE id = '{{$.trigger.body.id}}'` — deve usar parâmetros preparados ou validação prévia |
| SQL4 | Query sem `LIMIT` em SELECT sobre tabela grande | 🟡 | `SELECT` sem `LIMIT`/`TOP`/`FETCH FIRST` em tabelas que podem crescer — risco de timeout e sobrecarga de memória no step |
| SQL5 | Múltiplas queries em um único step SQL | 🟡 | Mais de uma instrução SQL separada por `;` no mesmo step — dificulta debug; separar em steps individuais com labels descritivos |
| SQL6 | JOIN sem índice provável nas colunas de junção | 🔵 | `JOIN` em colunas que não são PK/FK explícita (ex.: joins por `nome`, `email`, `descricao`) — sugerir verificação de índices |
| SQL7 | Subquery correlacionada em loop | 🟡 | Subquery dentro de `SELECT` que referencia a tabela externa (padrão N+1) — candidato a JOIN ou CTE |
| SQL8 | Ausência de transação em operações múltiplas | 🟡 | Dois ou mais steps SQL de escrita consecutivos sem mecanismo de rollback — se o segundo falhar, o primeiro já foi commitado |

### 4l. Boas Práticas e Observabilidade (Sugestão)

| # | Regra | Como detectar |
|---|-------|---------------|
| S1 | Fluxo sem versão publicada | `get_published_environments_for_flow` retorna vazio |
| S2 | `logEnabled: false` | Execuções não serão rastreáveis — dificulta debug em produção |
| S3 | Fluxo com mais de 20 steps sem subfluxos | Sugerir RunChildFlow para modularização e reuso |
| S4 | Steps com `failOnError: true` sem tratamento de erro | Quando um step falha com `failOnError: true`, o engine redireciona ao Stop (`a999`). Duas abordagens de tratamento, ambas válidas e combináveis: **(1)** Response condicional no Stop detectando a falha. A condição genérica recomendada — cobre qualquer step com `failOnError: true` no fluxo: `input: {{$.flowExecution.status}}` / condição: `(Text) Does Not Match` / valor esperado: `OK`. Usar descrição que deixe claro ser um tratamento de erro genérico. **(2)** Conector **"Tratar Erro"** ligado ao step com `failOnError: true`, permitindo steps de tratamento personalizado (log, alerta, transformação da mensagem) antes de chegar ao Stop. Sugerir a opção mais adequada ao contexto do fluxo. |
| S5 | `try/catch` suprimindo erros em custom action NodeJS | Verificar `jsFileAsString` — `try/catch` é usado apenas quando a biblioteca exige; catch vazio ou que retorna sucesso independente do erro é o problema real, não a ausência de try/catch |
| S6 | Response de erro sem mensagem amigável ao usuário | Status 4xx/5xx no Stop sem campo `message` descritivo |
| S7 | Operações de escrita sem auditoria | INSERT/UPDATE/DELETE, email ou SMS sem nenhum step de registro de auditoria |
| S8 | Fluxo async sem mecanismo de status/callback | Retorna 202 Accepted mas sem webhook de retorno, polling ou persistência de estado |

---

## 5. Formato do Relatório

Produzir o relatório em markdown:

```markdown
# Revisão do Fluxo: {Nome do Fluxo}
**ID:** `{flowId}` | **Steps:** {N} | **Versão analisada:** development | **Trigger:** {tipo}

---

## 🔴 Crítico ({X} findings)

### [C4] Step de Stop ausente
- **Problema:** Nenhum step com `id: "a999"` e `type: ".StopV2Step"` encontrado.
- **Impacto:** `publish_flow` falhará com HTTP 400.
- **Correção:** Adicionar step Stop ao final do fluxo com campo `responses`.

---

## 🟡 Avisos ({X} findings)

### [W6] Fluxo síncrono com operações pesadas
- **Steps afetados:** `a2` (SQL), `a3` (HTTP), `a4` (SQL)
- **Problema:** Trigger HTTP síncrono com 3 chamadas externas em cadeia sem subfluxo.
- **Sugestão:** Retornar 202 Accepted imediatamente e delegar processamento a um RunChildFlow assíncrono.

---

## 🔵 Sugestões ({X} findings)

### [S2] logEnabled desativado
- **Problema:** `logEnabled: false` — execuções não serão registradas.
- **Sugestão:** Ativar `logEnabled: true` pelo menos em hml/prod para facilitar debug.

---

## ✅ Resumo — Fluxo Principal
| Severidade | Total |
|------------|-------|
| 🔴 Crítico | X |
| 🟡 Aviso   | X |
| 🔵 Sugestão | X |

---

# Revisão do Subfluxo: {Nome do Subfluxo}
**ID:** `{flowId}` | **Steps:** {N} | **Referenciado por:** `{stepId}` ({label do step pai})

## 🔴 Crítico ({X} findings)
...

## ✅ Resumo Consolidado (todos os fluxos)
| Fluxo | 🔴 Crítico | 🟡 Aviso | 🔵 Sugestão |
|-------|-----------|---------|------------|
| master-xxx | X | X | X |
| sub-yyy | X | X | X |
| **Total** | **X** | **X** | **X** |

{Se zero findings em todas categorias em todos os fluxos: "Nenhum problema encontrado — todos os fluxos seguem as boas práticas da plataforma."}
```

Se não houver findings em uma categoria, omitir a seção inteira. Se não houver subfluxos, omitir a tabela consolidada e usar apenas o resumo simples.

---

## 6. Após o Relatório

Sempre oferecer as opções ao usuário:

1. **Aplicar correções automáticas** — para findings críticos que têm correção direta (ex.: atualizar counters, adicionar `responses` no Stop, corrigir sintaxe de interpolação). Chamar `save_flow_development` com as correções.
2. **Detalhar um finding** — explicar com mais profundidade como corrigir um ponto específico.
3. **Ignorar e encerrar** — registrar que a revisão foi feita.

### ⚠️ Regra de Ouro — Nunca Publicar sem Confirmação Explícita

**Jamais chamar `create_version` ou `publish_flow` sem perguntar ao usuário antes**, mesmo que ele tenha dito "corrija e publique" ou "aplique tudo". Sempre apresentar o que será feito e aguardar confirmação explícita antes de qualquer operação de versionamento ou publicação.

---

## 7. Princípios Gerais

- Analisar **todos os steps** — não parar no primeiro finding crítico.
- Ser **específico**: nomear o `id` do step afetado, o campo problemático e o valor encontrado.
- Não inventar findings — só reportar o que foi observado na estrutura real do fluxo.
- Steps com `nextSteps: []` ou sem `nextSteps` **não são** rotas desconectadas — o engine os encaminha implicitamente ao Stop quando o fluxo possui ao menos uma conexão explícita a `a999`. Só reportar como problema se absolutamente nenhum step conectar ao Stop.
- Para W9/W10 (persistência) e W6–W8 (async), usar julgamento contextual: fluxos de log/auditoria podem não precisar de persistência adicional.
- Detecção de C16/C17 (valores hardcoded): evitar false positives em IDs de autorização legítimos — focar em URLs completas, IPs e strings que claramente são configurações de ambiente.
- Para AUTH1–AUTH6: chamar `list_authorizations` uma vez para ter o catálogo de `authId` válidos do projeto; não reportar AUTH1 em steps que por design não requerem auth (ex.: StopV2Step, Switch, Loop).
- Para JS1–JS8: inspecionar o código via `get_custom_action_file` — só reportar findings presentes no código real, nunca inferir.
- Para SQL1–SQL8: análise estática das queries em `rawData`/`inputData`; SQL3 (injection) é sempre crítico mesmo que pareça "controlado".
- Para C11 (referência sem `.body`): steps do tipo Logger (`coreRouteType: "LOGGER_UTILITY"`) são exceção — seus outputs `message` e `level` são acessados diretamente **sem** `.body`. O campo `message` reflete exatamente o conteúdo de `logMessage`: se for um JSON com campo `message`, então `{{$.aN.message.message}}` é válido. Antes de reportar duplo nível como erro, verificar o `inputData.logMessage` do Logger para entender a estrutura real.
