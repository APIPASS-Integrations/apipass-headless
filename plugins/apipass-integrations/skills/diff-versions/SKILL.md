---
name: diff-versions
description: |
  Comparar versoes de um fluxo APIPASS — ver o que mudou entre versoes, listar historico de versoes, auditar alteracoes em steps. Use sempre que o usuario pedir para comparar versoes, ver diferencas entre versoes, ver o que mudou em um fluxo, auditar historico de alteracoes, ou listar versoes de um fluxo.

  Carregue ANTES de chamar list_flow_versions / get_version.
disable-model-invocation: false
---

# Comparar Versões de Fluxo na APIPASS

Você é especialista em análise de versões de fluxos na plataforma APIPASS. Quando o usuário pedir para comparar versões de um fluxo, siga rigorosamente o algoritmo abaixo.

---

## PASSO 1 — Resolver o flowId

- Se o usuário forneceu um **ID direto**, use-o.
- Se o usuário forneceu um **nome de fluxo**, chame `list_flows` (filtrando por projeto se informado) para encontrar o `flowId`.
- Se houver ambiguidade (múltiplos fluxos com nome similar), liste as opções e pergunte.

---

## PASSO 2 — Listar versões disponíveis

Chame `list_flow_versions(flowId)` e exiba uma tabela ao usuário:

```
| # | versionId | Criado em | Descrição |
|---|-----------|-----------|-----------|
| 1 | abc123    | 2024-03-10 | ...       |
| 2 | def456    | 2024-04-02 | ...       |
```

**Regras de seleção automática:**
- `"compare versão 1 e 2"` → use os índices da lista (1-based)
- `"o que mudou na última versão"` → compare penúltima (A) com última (B)
- `"compare development com versão 2"` → use `get_flow_development(flowId)` como versão B e `get_version` como versão A

Se o usuário não especificou as versões, exiba a lista e pergunte quais comparar antes de continuar.

---

## PASSO 3 — Buscar as duas versões em paralelo

Chame simultaneamente:
- `get_version(versionId_A)` para a versão mais antiga (A)
- `get_version(versionId_B)` para a versão mais nova (B)

Se uma das versões for o "development atual", use `get_flow_development(flowId)` no lugar.

---

## PASSO 4 — Algoritmo de comparação

Monte dois Maps indexados por `stepId`:

```
Map_A = { stepId → step }  ← versão A
Map_B = { stepId → step }  ← versão B
```

Classifique cada step:

| Categoria | Critério |
|---|---|
| **ADICIONADO** | Presente em B, ausente em A |
| **REMOVIDO** | Presente em A, ausente em B |
| **MODIFICADO** | Presente em ambos, mas com pelo menos um campo diferente |
| **INALTERADO** | Idêntico em ambos — **omitir do relatório** |

Para steps **MODIFICADOS**, liste apenas os campos que mudaram. Campos relevantes a verificar:
- `type` (tipo do step)
- `method`, `url` (para steps HTTP)
- `mappingAttributes` (mapeamentos de entrada/saída — compare campo a campo)
- `conditions` (para Switch)
- `jsFileAsString` (código NodeJS — se mudou, indique "código alterado")
- `authId`, `authProvider`
- `failOnError`, `async`
- `name` / `label` do step

---

## PASSO 5 — Formatar o relatório

```markdown
## Comparação: Fluxo "{nome}"
**Versão A:** v{N} ({data})  →  **Versão B:** v{N} ({data})

### ✅ Steps Adicionados ({count})
- **{stepId}** `{type}` — {descrição curta do step}

### ❌ Steps Removidos ({count})
- **{stepId}** `{type}` — {descrição curta do step}

### ✏️ Steps Modificados ({count})
- **{stepId}** `{type}` — `{campo}`: `"{antes}"` → `"{depois}"` | `{campo2}`: ...

### ↺ Steps Inalterados
_{N} steps sem alteração (omitidos)_
```

Regras de formatação:
- Se uma seção tiver 0 itens, escreva `_Nenhum_`
- Para `mappingAttributes`, cite o nome do atributo: ex. `mappingAttributes.status: "ATIVO" → "INATIVO"`
- Para `jsFileAsString`, não cole o código — escreva apenas `"código NodeJS alterado"`
- Se houver muitos campos alterados em um step, agrupe os menos relevantes: `+ 3 campos em mappingAttributes alterados`

---

## PASSO 6 (opcional) — Análise de impacto em execuções reais

**Ative esta seção SOMENTE se o usuário pedir explicitamente** (ex.: "mostre o impacto real", "analise execuções", "o que mudou no comportamento").

1. Chame `list_flow_execution_logs(flowId)` para buscar execuções recentes pós-publicação da versão B
2. Para cada step **MODIFICADO**, chame `read_step_payload(executionId, stepId)` para obter o I/O real
3. Adicione ao relatório:

```markdown
### 🔍 Impacto observado em execução recente
- **{stepId}** `{type}` — entrada: `{resumo}` | saída: `{resumo}` | status: `{200 OK / erro}`
```

> Se não houver execuções disponíveis após a versão B, informe ao usuário.

---

## Casos de uso

| Pedido do usuário | Comportamento |
|---|---|
| `compare versão 1 e 2 do fluxo X` | Busca as duas versões e exibe o diff |
| `o que mudou na última versão` | Compara penúltima → última automaticamente |
| `compare development atual com versão 3` | `get_flow_development` como B, `get_version` como A |
| `lista as versões do fluxo X` | Exibe tabela de versões sem comparar |
| `compare e mostre o impacto nas execuções` | Diff + Passo 6 ativado |
