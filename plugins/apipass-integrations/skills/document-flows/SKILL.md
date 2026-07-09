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

## 7. Diagramas de sequencia (opcional)

Se o usuario pediu, gere para cada fluxo um diagrama de sequencia SVG convertido para PNG
e embutido como imagem no Word via `ImageRun`. Mantenha-o como passo opcional — pule se a
resposta foi "nao".

### 7.1 Pacote para SVG -> PNG: @resvg/resvg-js

Nao use `sharp` nem `canvas` — ambos sao problematicos no Windows. O pacote correto e
`@resvg/resvg-js`:

```bash
# instalar no diretorio de trabalho (onde o script .js sera executado)
npm install @resvg/resvg-js
```

**Regra critica:** execute o script Node a partir do MESMO diretorio que contem
`node_modules/` (onde o `npm install` foi feito). Se rodar de outro diretorio, o
`require('@resvg/resvg-js')` falha com MODULE_NOT_FOUND.

```javascript
const { Resvg } = require('@resvg/resvg-js');

function svgToPng(svgString) {
  const resvg = new Resvg(svgString, {
    fitTo: { mode: 'width', value: 1200 },  // renderiza em 1200px de largura
    font: { loadSystemFonts: true },         // OBRIGATORIO — sem isso o texto fica invisivel
  });
  return resvg.render().asPng(); // retorna Buffer
}
```

> **`loadSystemFonts: true` e obrigatorio.** Com `false` (padrao), o resvg nao encontra
> nenhuma fonte e renderiza o texto em branco — o diagrama fica visualmente quebrado.

### 7.2 Estrutura do SVG de sequencia

Gere o SVG manualmente (sem dependencia de Mermaid/Puppeteer). O padrao validado:

```javascript
function gerarSVG(titulo, participantes, mensagens) {
  const COL_W   = 200;   // largura por participante (px)
  const LINHA_H = 44;    // espaco vertical entre mensagens normais
  const SEP_H   = 36;    // espaco para faixas de separador (loop/grupo)
  const SELF_H  = 44;    // espaco para self-messages (APIPASS -> APIPASS)
  const TOPO_H  = 90;    // cabecalho (titulo + caixas de participante)
  const MARGEM  = 20;
  const N       = participantes.length;
  const SVG_W   = N * COL_W + 2 * MARGEM;

  // calcula altura dinamicamente por tipo de mensagem
  let totalH = TOPO_H;
  mensagens.forEach(m => {
    if (m.type === 'sep') totalH += SEP_H;
    else if (m.from === m.to) totalH += SELF_H;
    else totalH += LINHA_H;
  });
  const SVG_H = totalH + 50;

  const cx = (i) => MARGEM + i * COL_W + COL_W / 2;
  // ... (ver shape completo abaixo)
}
```

**Tipos de mensagem no array `mensagens`:**
- `{ from: 0, to: 2, text: 'GET /orders' }` — seta horizontal entre participantes
- `{ from: 1, to: 1, text: 'MEMORY_STORE_SET x=1' }` — self-message (loop retangular)
- `{ type: 'sep', text: 'Loop de paginacao' }` — faixa azul claro de separacao

**Self-message (loop retangular, itálico):**
```javascript
const lx = fromX + 24;
svg += `<path d="M ${fromX} ${y} L ${lx} ${y} L ${lx} ${y+18} L ${fromX} ${y+18}"
        stroke="#1F3C70" stroke-width="1.5" fill="none"/>
<polygon points="${fromX},${y+18} ${fromX+7},${y+13} ${fromX+7},${y+23}" fill="#1F3C70"/>
<text x="${lx+6}" y="${y+13}" font-style="italic" font-size="11" fill="#555">${label}</text>`;
y += SELF_H;
```

**Seta normal (texto acima, centralizado):**
```javascript
svg += `<line x1="${fromX}" y1="${y}" x2="${toX}" y2="${y}" stroke="#1F3C70" stroke-width="1.5"/>`;
// ponta da seta conforme direcao (dir > 0: aponta para direita)
svg += `<text x="${midX}" y="${y-8}" text-anchor="middle" font-size="11">${label}</text>`;
y += LINHA_H;
```

**Faixa separadora:**
```javascript
svg += `<rect x="${MARGEM}" y="${y-8}" width="${SVG_W-2*MARGEM}" height="26" rx="3" fill="#E3EAF6"/>
<text x="${MARGEM+10}" y="${y+10}" font-size="11" fill="#1F3C70" font-weight="bold">${label}</text>`;
y += SEP_H;
```

### 7.3 Embutir PNG no Word (ImageRun + docx-js)

```javascript
// converte DXA -> pixels para o ImageRun (96 DPI: 1 inch = 1440 DXA = 96px)
function dxaToPx(dxa) { return Math.round(dxa * 96 / 1440); }

// calcula dimensoes mantendo proporcao do SVG
function dimImg(svgStr, targetWdxa) {
  const w = parseInt(svgStr.match(/width="(\d+)"/)[1]);
  const h = parseInt(svgStr.match(/height="(\d+)"/)[1]);
  return { w: targetWdxa, h: Math.round((h / w) * targetWdxa) };
}

const CWIDTH = 9071; // largura util da pagina A4 ABNT em DXA
const dim    = dimImg(svgString, CWIDTH);
const png    = svgToPng(svgString);

new Paragraph({
  children: [new ImageRun({
    type: 'png',
    data: png,
    transformation: { width: dxaToPx(dim.w), height: dxaToPx(dim.h) },
    altText: { title: 'Diagrama', description: 'Diagrama de sequencia', name: 'diagrama' },
  })],
  alignment: AlignmentType.CENTER,
  spacing: { before: 80, after: 80 },
})
```

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
