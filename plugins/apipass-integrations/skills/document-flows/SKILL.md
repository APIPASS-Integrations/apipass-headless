---
name: document-flows
description: |
  Gerar documentacao de integracoes (Word/PDF) a partir dos fluxos de um projeto APIPASS, OU
  transcrever uma analise funcional ja feita (pre-implementacao) no padrao AF + De-Para
  (planilha separada, linkada). Use quando o usuario pedir "documente os fluxos do projeto X",
  "gere a documentacao de integracao", "PDF dos fluxos do cliente Y", "documento tecnico das
  integracoes", "gerador de documentacao", "documento ABNT", "documento tecnico-funcional",
  "analise funcional", "AF", "planilha de-para", "de x para", "fluxos MASTER/SUB", ou quando
  anexar um par de arquivos de referencia "AF - ... .docx" + "de-pra-... .xlsx" e pedir para
  seguir o mesmo padrao.
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

## 0. Escolher o padrao do documento

Existem **dois padroes** de entregavel, resolvidos por fontes de dado diferentes. Decida antes
de seguir (pergunte se nao estiver claro):

| Padrao | Quando usar | Fonte dos "steps"/etapas | Entregaveis |
|---|---|---|---|
| **A — Consolidado (SAP-style)** | O projeto ja tem fluxo(s) publicados na APIPASS | `list_flows`/`export_flow_json` via MCP (secao 1-6 abaixo) | 1 `.docx` (com PDF opcional) |
| **B — AF + De-Para (estilo Trizy)** | Analise funcional **pre-implementacao** (fluxo ainda nao existe na plataforma) OU o usuario anexa um par de referencia `AF - ... .docx` + `de-pra-... .xlsx` e pede para replicar o padrao | A analise/documentacao ja levantada na conversa (SQL, curls, regras) — **nao** vem de MCP | 1 `.docx` (AF) + 1 `.xlsx` (De-Para) + N `.txt` de anexo (queries/curls) |

Se o usuario anexar um par de arquivos de referencia (`AF - ...docx` + `de-pra-...xlsx`), va
direto para a **Secao 8** — nao tente ler fluxos via MCP, o padrao B e autocontido a partir do
que ja foi analisado/documentado na conversa.

Se nao houver nem fluxo publicado nem arquivos de referencia, pergunte ao usuario qual dos
dois padroes ele quer.

---

## Padrao A — Documento consolidado via MCP

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

---

## Padrao B — AF + De-Para (estilo Trizy, pre-implementacao)

Use este padrao quando a integracao **ainda nao foi construida na plataforma** — o que existe
e uma analise funcional (queries SQL, regras de negocio, curls de exemplo, diagramas de
sequencia) levantada na propria conversa. Diferente do Padrao A, aqui **nao ha MCP**: a fonte
da verdade e o que ja foi documentado/validado com o usuario e, se fornecido, um par de
arquivos de referencia (`AF - {Origem} _ {Destino} - {Descricao}.docx` +
`de-pra-{...}.xlsx`) cujo layout/estrutura deve ser replicado.

### 8.1 Se o usuario anexar um par de referencia

Antes de montar qualquer coisa, **extraia a estrutura real** do par de arquivos (sao ZIPs
OOXML — nao use o Read tool direto em binario, ele falha). Delegue a um agente Explore
(somente leitura) ou faca voce mesmo via Bash:

```bash
unzip -o "arquivo.docx" -d pasta_extraida/     # word/document.xml, word/numbering.xml,
                                                 # word/styles.xml, word/header*.xml, word/footer*.xml
```

Para o texto/hierarquia: parseie `word/document.xml` com Python (`xml.etree.ElementTree`) —
`python-docx` normalmente NAO esta instalado e nao vale a pena instalar so pra isso. Para
hyperlinks, leia `word/_rels/document.xml.rels` procurando
`.../relationships/hyperlink`. Extraia do XML, literalmente (nao resuma):
- A lista completa de titulos/secoes, em ordem, com a numeracao real renderizada (ex. `I.`,
  `II.`... vem de uma lista numerada em `word/numbering.xml` com `numFmt=upperRoman`, nao de
  texto literal "1.", "2.").
- O texto exato de cada frase-padrao (ex. "De X PARA: Abaixo segue o link do arquivo.") para
  poder reusar o mesmo tom/formato.
- Onde e como o de-para e referenciado (link, texto-ancora = nome do arquivo).

Para o `.xlsx` (mesma logica, `xl/worksheets/sheetN.xml` + `xl/styles.xml` + `xl/theme/theme1.xml`):
nome de cada aba, celulas mescladas, cores de fill (`rgb=` literal ou `theme=` indice — se for
indice, resolva contra `a:clrScheme` do tema), fonte/tamanho/negrito, largura de cada coluna.

> Um agente Explore tem Bash mas **nao tem Write** — se precisar materializar imagens
> extraidas (ex. `word/media/image1.png`) para inspecionar visualmente, faca isso voce mesmo
> (fora do Explore) ja que ele so pode ler em memoria.

### 8.2 Estrutura do `.docx` (AF)

```
[capa em pagina propria — logo, "Analise Funcional", Cliente/Projeto/Fluxo de Processo,
 tabela Elaborador por / Data e Versao / Apresentado para / Data de Apresentacao]
I.   Objetivo e sistemas envolvidos       (prosa)
II.  Foco da integracao                   (prosa + bullet dos processos)
III. Listagem da integracao               (tabela: Prior.|Fluxo|Volumetria|Disparo|
                                            Origem|Conectividade|Destino|Conectividade)
IV.  Regra de negocio                     (uma subsecao A./B./C.../ por fluxo)
V.   Diagrama de Sequencia                (imagem por fluxo)
```

Cada subsecao de **IV** segue sempre:
```
A. <NOME-DO-FLUXO-EM-MAIUSCULO>
   i. Explicacao Geral do Processo: <paragrafo>
   Origem: <Sistema>. <narrativa> + Autorizacao + endpoint(s) + "Exemplo de Chamada:" -> anexo
   Destino: <Sistema>. <narrativa, incluindo "Aplicar as regras descritas na planilha de
            De x Para" quando o fluxo transforma campos> + Autorizacao + endpoint(s) +
            "Exemplo de Chamada:"/"Exemplo de Resposta:" -> anexo(s)
```
Ao final de **IV** (uma unica vez, nao por subsecao): `"De X PARA: Abaixo segue o link do
arquivo."` + o nome do arquivo `.xlsx` como texto-ancora.

**Nomenclatura dos fluxos — convencao MASTER/SUB:** quando ha roteamento (um trigger unico que
decide qual variante processar, ex. por um campo do payload), modele como:
- `MASTER-REST-<ACAO>-<ORIGEM>-<DESTINO>` — fluxo trigger, so roteia e repassa a resposta.
- `SUB-<ACAO>-<VARIANTE>-<ORIGEM>-<DESTINO>` — um por variante, chamado via Call Flow pelo
  master (a primeira/ultima etapa da tabela do sub-fluxo e "Entrada/Retorno (Call Flow)", nao
  "Trigger REST").

Um fluxo `MASTER-...` sem variantes (so um trigger direto, sem sub-fluxos) e normal — nem todo
MASTER tem SUB.

**Nomenclatura de arquivo:** `AF - {Origem} _ {Destino} - {Descricao}.docx` (espaco-hifen-
espaco antes/depois de "AF", espaco-underscore-espaco entre os sistemas) e
`de-pra-{mesma descricao}.xlsx` (prefixo `de-pra-`, sem "AF"; os separadores internos podem
variar — nao ha uma regra rigida observada nos exemplos, use hifen entre termos).

### 8.3 Anexos em `.txt` em vez de conteudo inline

**Nao** embuta SQL/curl/JSON diretamente no corpo do `.docx` — extraia cada query/exemplo de
chamada para um arquivo `.txt` numerado (mesmo padrao do exemplo de referencia: `01-`, `02-`...
contínuo pelo documento inteiro, nao reiniciando por fluxo), e no lugar do conteudo deixe so um
link estilizado (cor de link, sublinhado) com o nome do arquivo como texto.

Convencao de nomenclatura por artefato:
- `NN-Origem-query-SQL-X.Y-descricao-curta.txt` — query contra o banco do sistema de origem.
- `NN-Origem-curl-descricao-curta.txt` — exemplo do payload/chamada que o sistema de origem
  faz PARA a APIPASS (o trigger).
- `NN-Destino-curl-descricao-curta.txt` — chamada que a APIPASS faz PARA o sistema de destino.
- `NN-Destino-response-descricao-curta.txt` — exemplo de resposta do destino.

Se uma query/curl e reutilizada por mais de um fluxo (ex. autenticacao OAuth2, ou uma query de
configuracao consultada por dois sub-fluxos), **nao duplique o arquivo** — referencie o mesmo
numero de novo, com uma nota "(mesmo arquivo do item X)".

Cada `.txt` leva um comentario de 1 linha no topo dizendo a qual query/secao do doc de origem
corresponde e em qual fluxo e usado — isso e o que permite ao usuario colar o conteudo no lugar
certo depois.

**Ao final, sempre devolva ao usuario uma tabela "arquivo -> secao exata onde deve ser
anexado/linkado"** — e a unica forma de ele saber onde cada `.txt` entra sem reabrir o `.docx`.

### 8.4 Estrutura do `.xlsx` (De-Para)

Uma aba por **conjunto de regras de transformacao** — nao necessariamente 1:1 com os fluxos da
secao III (dois fluxos podem chamar o mesmo endpoint de destino com regras diferentes = 2
abas; um fluxo que so faz passthrough sem transformar campo nenhum = 0 abas).

Layout fixo por aba (linhas e colunas fixas, dados a partir da linha 7):
```
A1:E2 mesclado = "DE'"            |  G1:K2 mesclado = "PARA'"
A3    = "Origem"                  |  G3:K3 mesclado = "Destino"
A4:E5 mesclado = <descricao da origem>  | G4:K5 mesclado = <descricao do destino/endpoint>
A6=Ref B6=Campo C6=Obrigatoriedade D6="Tipo do campo" E6=Regra   (F vazia, separador)
G6=Ref H6=Campo I6=Obrigatoriedade J6="Tipo do campo" K6=Regra
```

**Coluna Ref — regra importante:** o prefixo do codigo de referencia (ex. `L1`, `L2`...) e a
**inicial do sistema de origem**, nao um prefixo generico como "R" (de "Referencia"). Se o
sistema de origem for uma sigla de 2+ letras (ex. "LH"), pergunte ao usuario se prefere a sigla
completa (`LH1, LH2...`) ou so a primeira letra (`L1, L2...`) — ja tivemos os dois casos.
Quando um campo de destino combina mais de uma referencia de origem, use `"Lx + Ly"` na coluna
Ref do lado Destino. Campos fixos/calculados em runtime (sem correspondencia na origem) ficam
com Ref vazio e a explicacao vai na coluna Regra (ex. "FIXO DateTime.Now()").

Gerar com `openpyxl` (Python) — geralmente ja disponivel ou instalavel sem complicacao via
`pip install openpyxl`. Larguras de coluna assimetricas: a coluna Regra do lado Origem costuma
ser estreita (~17 unidades), a do lado Destino bem mais larga (~50+), porque a regra de
transformacao (lado Destino) tende a ser mais descritiva que a nota da query de origem.

### 8.5 Identidade visual APIPASS

Quando o usuario pedir para aplicar a marca APIPASS (nao um layout generico nem o de um cliente
de referencia como o exemplo Trizy), use os valores abaixo — extraidos do manual de marca
(`APIPASS - Manual tom de voz.pdf`, se anexado) e de `https://apipass.com.br/` (cores
computadas via `getComputedStyle`, nao adivinhadas):

**Paleta:**
| Cor | Hex | Uso |
|---|---|---|
| Navy (primaria) | `#222D58` | Logo, botoes/CTAs do site, headers de tabela, banner "Origem" no de-para |
| Indigo (secundaria) | `#2D2B73` | Titulos de bloco secundarios |
| Lime (acento, da marca no logo) | `#D2D81F` | Acentos/linhas divisorias, banner "Destino" no de-para (com texto navy, nao branco — lime e claro demais para texto branco) |

**Tipografia:** Montserrat para titulos/headings/botoes (peso 600/bold), Arial para corpo de
texto — mesma combinacao usada no site.

**Logo:** o SVG real fica em `https://apipass.com.br/wp-content/uploads/2024/01/logo-header.svg`
(buscavel via `fetch` no browser tool ou `curl`). Rasterize para PNG antes de embutir no
`.docx` (docx-js so aceita png/jpg/gif/bmp em `ImageRun`, nao svg) — ver 7.1 para o metodo
`@resvg/resvg-js`; se o pacote nao estiver disponivel/instalavel, uma alternativa que funcionou
foi abrir o SVG num navegador headless (Chrome `--headless --screenshot`) e capturar o
resultado.

**Tom de voz:** formal + empatico + objetivo (autoridade e credibilidade, mas humanizado — ex.
"vamos juntos"). Frase-sintese: "Simplificamos o que e complexo, impulsionando resultados."
Aplique o tom de voz **apenas nos paragrafos narrativos/conectivos** (capa, abertura das
secoes I/II/IV, um paragrafo de fechamento) — **nunca** nas descricoes tecnicas (Origem/
Destino, regras de negocio, nomes de campo/query): o proprio manual de marca elege
objetividade e ausencia de ambiguidade como pilares do tom, entao reescrever conteudo tecnico
em "linguagem de marca" iria contra a propria diretriz.

### 8.6 Tecnicas de fallback usadas neste ambiente (Windows, sem poppler/LibreOffice/Word)

- **Ler PDF grande sem `pdftoppm`/poppler:** o Read tool falha se poppler nao estiver
  instalado. Fallback: `pip install pypdf pillow` e usar `pypdf.PdfReader` para extrair texto
  pagina a pagina (grave em arquivo UTF-8 em vez de `print()` — o console do Windows quebra em
  `cp1252` com caracteres especiais) e `page.images` para extrair imagens embutidas (precisa
  do Pillow instalado, senao da erro `ImportError` especifico).
- **Rasterizar SVG (logo, diagramas) sem `resvg-js`/LibreOffice/Word:** Chrome headless
  funciona bem — `chrome.exe --headless --disable-gpu --no-sandbox --screenshot=out.png
  --window-size=WxH --default-background-color=FFFFFFFF file:///caminho/arquivo.svg`. Escreva
  o output para a pasta scratchpad primeiro se o diretorio do projeto der "Acesso negado" (o
  processo do Chrome as vezes nao tem permissao de escrita direta no diretorio do projeto,
  mesmo quando o Write tool tem).
- **Descobrir a paleta de cores real de um site (nao adivinhar pelo olho):** usar o browser
  tool com `javascript_tool` rodando um scan de `getComputedStyle` em todos os elementos,
  contando `backgroundColor` por frequencia — revela as cores de marca reais mesmo sem acesso
  ao design system/Figma.
- **Gerar `.docx`/`.xlsx` do zero:** `docx` (npm, via `docx-js`) e `openpyxl` (Python) cobrem
  a grande maioria dos casos sem precisar de LibreOffice/Word instalados. Rode o script de
  build numa pasta temporaria (`npm init -y && npm install docx`), gere o arquivo final no
  destino certo, e apague a pasta de build — nao deixe `node_modules`/scripts de build
  misturados com os entregaveis do usuario.

---

## Observacoes

- Fluxos genericos/rascunho sao ignorados por padrao (ver passo 3, Padrao A); confirme a lista.
- Para um novo cliente, basta repetir informando outro projeto e outro nome de capa — nada e
  hardcoded.
- No Padrao A, fonte da verdade e sempre a APIPASS via MCP; nao edite nem dependa de JSON
  local. No Padrao B, a fonte da verdade e a analise ja validada com o usuario na conversa (e,
  se houver, o par de arquivos de referencia) — deixe isso explicito no proprio documento
  quando o fluxo ainda nao existir na plataforma.

## Skills relacionadas
- `anthropic-skills:docx` — montagem do arquivo Word/PDF.
- `/apipass-integrations:apipass-patterns` — estrutura do specflow e contadores.
- `/apipass-integrations:apipass-actions` — anatomia do FlowStep e `mappingAttributes`.
- `/apipass-integrations:set-account` — definir a conta/realm antes de ler os fluxos.
