---
name: document-flows
description: |
  Gerar documentacao de integracoes (Word/PDF) a partir dos fluxos de um projeto APIPASS.
  Use quando o usuario pedir "documente os fluxos do projeto X", "gere a documentacao de
  integracao", "PDF dos fluxos do cliente Y", "documento tecnico das integracoes",
  "gerador de documentacao", "documento ABNT", "documento tecnico-funcional".
disable-model-invocation: false
argument-hint: "[nome-do-projeto]"
---

# Gerador de Documentacao de Integracoes — APIPASS

Produz um documento corporativo (`.docx`, com PDF opcional) descrevendo os fluxos de um
projeto APIPASS. Os fluxos sao lidos **direto da APIPASS via MCP** — nao ha upload manual de
JSON. A montagem do arquivo Word e delegada a skill `anthropic-skills:docx`.

Estrutura do entregavel (padrao do "doc SAP de referencia"):
```
CAPA            -> nome APIPASS, projeto/cliente, versao, data, sistemas integrados
1. Visao Geral  -> prosa + tabela indice (fluxo, acionamento, nº de steps)
2..N. Por fluxo -> descricao + informacoes tecnicas + tabela de etapas
Final. Tratamento de Erros e Resiliencia
```

## 1. Coletar inputs do usuario

Se faltarem, pergunte numa unica mensagem (use `AskUserQuestion`):
- **Projeto/cliente** — para resolver o `projectId` via MCP (pode vir como argumento).
- **Nome para a capa e cabecalho** — ex. "Mondelez", "JBS Terminais". Parametriza a capa;
  **nunca** use nome hardcoded de cliente anterior.
- **Organizacao** — um documento por projeto / um consolidado / por categoria.
- **Incluir diagramas de sequencia?** — sim / nao.

## 2. Coletar os fluxos via MCP

1. `list_projects` — resolva o `projectId` pelo nome informado. Se houver mais de um match,
   liste-os e confirme com o usuario antes de seguir.
2. `list_flows(projectId)` — lista os fluxos do projeto.
3. Para cada fluxo a documentar: `export_flow_json(flowId)` (exportacao completa) ou
   `get_flow_development(flowId)` (steps). Use o que retornar a estrutura mais completa.

> Estrutura do specflow (steps, trigger, contadores) esta em
> `/apipass-integrations:apipass-patterns`. Anatomia do FlowStep e do `mappingAttributes` em
> `/apipass-integrations:apipass-actions`. Se uma tool pedir login, mostre a `authorizeUrl`
> ao usuario e refaca.

## 3. Filtrar rascunhos e legados

Ignore fluxos cujo nome contenha (case-insensitive): `teste`, `aaaa`, `copy`, `old`,
`exemplo`, `bkp`, `backup`, `rascunho`. **Antes de gerar**, liste para o usuario o que foi
**incluido** vs. **ignorado** e deixe-o ajustar.

## 4. Extrair de cada fluxo

Do specflow JSON, monte:
- **Cabecalho do fluxo** — nome, `flowId`, **acionamento** (tipo do step de gatilho — o step
  com `trigger != 0` / primeiro step `.trigger.*`).
- **Informacoes tecnicas** — filas AMS, collections MongoDB e APIs externas, lidas dos
  `type` dos steps e dos `mappingAttributes`/`inputData`/campos de topo (ex. `url` de
  `.service.http.HttpRequest`, collection de `.service.mongodb.*`, fila de SQS/AMS).
- **Tabela de etapas** — uma linha por step: `#`, `Etapa` (label), `Descricao`, `Tipo`
  (o `type` da acao, em forma legivel).
- **Descricao em prosa** — extraida dos comentarios `//` no codigo Node dos steps de codigo
  (`.utility.nodejs.*` / Action com script); na ausencia, derive do label + tipo.

## 5. Montar a estrutura do documento

- **Capa** — "APIPASS", nome do projeto/cliente (input do usuario), versao, data
  (use a data atual do ambiente), sistemas integrados (deduzidos dos tipos de acao).
- **Cabecalho/rodape** — `<nome do cliente> | <titulo da secao>`, parametrizado pelo input
  (substitui o hardcode "Projeto Recintos - JBS Terminais" do engine antigo).
- **Secao 1 — Visao Geral** — prosa explicando o projeto + tabela indice (fluxo,
  acionamento, nº de steps).
- **Secoes 2..N** — uma por fluxo: descricao, informacoes tecnicas, tabela de etapas.
- **Secao final — Tratamento de Erros e Resiliencia** — padroes do projeto (failOnError,
  retries, StopStep com `responses`, dead-letter/AMS quando houver).

Conforme a **organizacao** escolhida: um arquivo por projeto, um consolidado (todos os
fluxos num doc), ou agrupado por categoria.

## 6. Gerar o documento (skill docx)

Invoque a skill `anthropic-skills:docx` passando o conteudo estruturado acima para produzir
o `.docx` (gerar com `docx-js`; validar com o `validate.py` da skill — no Windows rode o
Python com `PYTHONUTF8=1`, senao o console quebra em cp1252).

**PDF (opcional):** o caminho padrao da skill docx (LibreOffice headless via `soffice.py`)
**nao funciona no Windows** — o wrapper usa sockets `AF_UNIX`. Neste ambiente, converta com o
Microsoft Word via COM:
```powershell
$w = New-Object -ComObject Word.Application; $w.Visible=$false
$d = $w.Documents.Open($docx,$false,$true); $d.SaveAs([ref]$pdf,[ref]17); $d.Close($false); $w.Quit()
```

### 6.1 Formatacao ABNT NBR 14724 (padrao para clientes brasileiros)

Quando o usuario pedir documento no padrao ABNT ou documento tecnico-funcional formal,
aplique as seguintes configuracoes no script docx-js:

**Pagina A4 e margens:**
```javascript
// 1 cm = 567 DXA | A4 = 11906 x 16838 DXA
// Largura util = 11906 - 1701 - 1134 = 9071 DXA
page: { size: { width: 11906, height: 16838 },
        margin: { top: 1701, right: 1134, bottom: 1134, left: 1701 } }
//              superior 3 cm   direita 2 cm  inferior 2 cm  esquerda 3 cm
```

**Fonte e espacamento:**
```javascript
// Corpo: Arial 12pt (size: 24), espacamento 1,5, recuo 1a linha 1,25 cm
const LS15 = { line: 360, lineRule: "auto" };
spacing: { ...LS15, before: 0, after: 0 }
indent: { firstLine: 709 }           // 1,25 cm
alignment: AlignmentType.JUSTIFIED
```

**Hierarquia de titulos:**
```javascript
// Nivel 1 — MAIUSCULO + negrito (ABNT primario)
children: [run(num + "  " + text.toUpperCase(), { size: 24, bold: true })]
spacing: { line: 360, lineRule: "auto", before: 480, after: 120 }

// Nivel 2 — negrito (ABNT secundario)
children: [run(num + "  " + text, { size: 24, bold: true })]
spacing: { line: 360, lineRule: "auto", before: 360, after: 80 }

// Nivel 3 — negrito italico (ABNT terciario)
children: [run(num + "  " + text, { size: 24, bold: true, italic: true })]
```

**Tabelas e figuras:**
```javascript
// Legenda de tabela: ACIMA, alinhada a esquerda, tamanho 10pt
"Tabela N – Titulo da tabela"      // antes do tbl()
"Fonte: Elaborado pelos autores (2026)."  // apos o tbl(), italico

// Legenda de figura: ABAIXO, centralizada, tamanho 10pt
"Figura N – Titulo da figura"      // apos a imagem
"Fonte: Elaborado pelos autores (2026)."
```

**Numeracao de paginas — canto superior direito (nao rodape):**
```javascript
headers: { default: new Header({ children: [new Paragraph({
  alignment: AlignmentType.RIGHT,
  children: [new TextRun({ children: [PageNumber.CURRENT], font: "Arial", size: 24 })]
})]})},
// Sem footer de numeracao — rodape pode conter info institucional apenas
```

**Listas sem bullet grafico (ABNT):**
```javascript
// Use traco (–) em vez de bullet Unicode ou LevelFormat.BULLET
indent: { left: 720, hanging: 360 },
children: [run("– ", ...), run(text, ...)]
```

**Sumario com pontos (tab leader):**
```javascript
new Paragraph({
  tabStops: [{ type: TabStopType.RIGHT, position: 9071, leader: "dot" }],
  children: [run(num + "  " + titulo), run("\t" + pagina)]
})
```

**Atencao — codificacao no Windows:**
- Nunca use aspas tipograficas (`"` `"`) em strings JS quando o arquivo for gravado via
  PowerShell — o PowerShell pode gravar em CP1252 e o Node falha ao parsear.
- Use aspas ASCII simples `'` ou `"` em todos os literais de string no script JS.
- Para converter SVG para PNG (embutir diagrama no Word), use o pacote `sharp`:
  `npm install sharp` → `sharp(svgBuffer).png().toFile('diagram.png')`

## 7. Diagramas de sequencia (opcional)

Se o usuario pediu, gere para cada fluxo um diagrama de sequencia (gatilho -> steps ->
sistemas externos) e embuta no documento via a skill docx (Mermaid renderizado ou imagem).
Mantenha-o como passo opcional — pule se a resposta foi "nao".

## Observacoes

- Fluxos genericos/rascunho sao ignorados por padrao (ver passo 3); confirme a lista.
- Para um novo cliente, basta repetir informando outro projeto e outro nome de capa — nada e
  hardcoded.
- Fonte da verdade e sempre a APIPASS via MCP; nao edite nem dependa de JSON local.

## Skills relacionadas
- `anthropic-skills:docx` — montagem do arquivo Word/PDF.
- `/apipass-integrations:apipass-patterns` — estrutura do specflow e contadores.
- `/apipass-integrations:apipass-actions` — anatomia do FlowStep e `mappingAttributes`.
- `/apipass-integrations:set-account` — definir a conta/realm antes de ler os fluxos.
