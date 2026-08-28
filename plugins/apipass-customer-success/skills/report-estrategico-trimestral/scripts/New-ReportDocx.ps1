# New-ReportDocx.ps1
# Monta o Report Estrategico Trimestral em .docx (Word COM, servido pelo WPS) e
# exporta PDF. Le todo o conteudo de um JSON UTF-8 -- este arquivo e ASCII puro de
# proposito, para nao depender do encoding com que o powershell.exe le o script.
#
# O schema do JSON e as tres variantes de layout estao em
# references/render-report.md. As armadilhas gerais de COM estao em
# ../../extrato-consumo/references/render-lamina.md.
#
# GUARD: o formato acordado e 1-2 paginas. Se estourar, o script SAI COM ERRO em vez
# de gerar o PDF -- um "executive summary" de 5 paginas nao e lido.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DataJson,
    [Parameter(Mandatory=$true)][string]$OutDocx,
    # B e o layout PADRAO, escolhido pela Elisama em 19/08/2026 (faixa de KPIs no topo).
    # A e C ficam disponiveis, mas nao se usa outro layout sem pedido explicito.
    [ValidateSet("A","B","C")][string]$LayoutVariant = "B",
    [switch]$ExportPdf,
    [string]$WorkDir = "",
    [int]$MaxPages = 2,
    # Rotulos CANONICOS. O report tem os MESMOS topicos para todo cliente, e a garantia
    # disso nao pode depender de quem monta o JSON: o arquivo abaixo e a base, e o
    # `rotulos` do cliente so consegue SOBREPOR o que ja existe, nunca criar estrutura.
    [string]$RotulosJson = ""
)

$ErrorActionPreference = "Stop"
$ptBR = [Globalization.CultureInfo]::GetCultureInfo("pt-BR")
$inv  = [Globalization.CultureInfo]::InvariantCulture
Add-Type -AssemblyName System.Drawing

# COM do WPS falha de formas pouco informativas; sem o stack trace fica cego.
trap {
    Write-Output ("ERRO: " + $_.Exception.Message)
    Write-Output "--- stack ---"
    Write-Output $_.ScriptStackTrace
    exit 1
}

# ---------- constantes COM ----------
$wdStory            = 6
$wdAlignLeft        = 0
$wdAlignCenter      = 1
$wdLineStyleNone    = 0
$wdLineStyleSingle  = 1
$wdStatisticPages   = 2
$wdFormatPDF        = 17   # serve para ExportAsFixedFormat e para SaveAs
$msoTrue            = -1
$wdBorderBottom     = -3

$FONT = "Segoe UI"

# ---------- helpers ----------

# Word COM recebe cor em BGR, nao RGB. Passar hex direto pinta a cor errada
# sem lancar erro -- e o tipo de bug que so aparece no PDF entregue.
function Hex-ToBgr([string]$hex) {
    if ([string]::IsNullOrWhiteSpace($hex)) { return 0 }
    $h = $hex.Trim().TrimStart('#')
    if ($h.Length -ne 6) { return 0 }
    $r = [Convert]::ToInt32($h.Substring(0,2), 16)
    $g = [Convert]::ToInt32($h.Substring(2,2), 16)
    $b = [Convert]::ToInt32($h.Substring(4,2), 16)
    return ($b * 65536 + $g * 256 + $r)
}
function Hex-ToColor([string]$hex) {
    $h = $hex.Trim().TrimStart('#')
    return [Drawing.Color]::FromArgb(
        [Convert]::ToInt32($h.Substring(0,2),16),
        [Convert]::ToInt32($h.Substring(2,2),16),
        [Convert]::ToInt32($h.Substring(4,2),16))
}
function Fmt-Int($n) {
    if ($null -eq $n) { return "-" }
    return ([long]$n).ToString("#,##0", $ptBR)
}
# Acesso seguro a membro de PSCustomObject vindo do ConvertFrom-Json: chave ausente
# nao e erro, e "seção nao coletada" -- que o report declara em vez de inventar.
function Has-Prop($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    return ($null -ne $obj.PSObject.Properties[$name]) -and ($null -ne $obj.$name)
}
function Get-Prop($obj, [string]$name, $default = $null) {
    if (Has-Prop $obj $name) { return $obj.$name }
    return $default
}
function Count-Of($arr) {
    if ($null -eq $arr) { return 0 }
    return @($arr).Count
}
function Strip-Acentos([string]$s) {
    if ($null -eq $s) { return "" }
    $n = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}
# TODO texto visivel ao cliente vem do JSON (bloco "rotulos"). Este .ps1 e ASCII puro,
# entao qualquer string escrita aqui sai SEM ACENTO no documento -- "Visao geral",
# "Integracoes", "Nao constam". O fallback existe so para nao derrubar o render; quando
# ele e usado, entra pendencia.
$script:rotuloFaltando = New-Object Collections.Generic.List[string]
# NAO chamar esta funcao de "R": R e alias nativo de Invoke-History e alias tem
# precedencia sobre funcao no PowerShell -- o sintoma e "nao e possivel localizar um
# parametro posicional", nao "funcao nao encontrada".
function Rot([string]$key, [string]$fallback) {
    if (Has-Prop $script:rotulos $key) { return [string]$script:rotulos.$key }
    if (-not $script:rotuloFaltando.Contains($key)) { $script:rotuloFaltando.Add($key) }
    return $fallback
}

# ---------- grafico de crescimento (GDI+) ----------
# DESVIO DELIBERADO do caminho Excel COM usado pelo extrato-consumo. Ali o grafico
# nasce de um range renderizado como PNG porque o conteudo E uma tabela. Aqui e um
# grafico de 3 barras: fazer por GDI+ elimina uma dependencia COM nao verificada no
# WPS (Chart.SetSourceData) e da controle exato do resultado. Sem COM, sem risco de
# Value2 recusar numero -- a armadilha nº 1 do render-lamina.md.
# REGRA DA ELISAMA (26/08/2026), acima de qualquer conveniencia de layout:
# O PADRAO DO GRAFICO NUNCA MUDA. Nada e injetado nele para explicar ausencia de dado --
# nem nota, nem legenda de "sem permissao", nem texto substituto. O grafico e o mesmo para
# todo cliente: barras com o absoluto, rotulo de mes, linha de media do trimestre anterior.
# A capacidade contratada (linha + percentual por barra) e o UNICO elemento opcional, e
# entra somente quando houve acesso a tela de Gerenciamento de Conta.
# Ausencia de dado se declara em TEXTO do documento (`naoConstam`), nunca dentro do PNG:
# legenda de grafico e pixel, nao da para buscar nem selecionar.
# O parametro `notaContratado` existia e foi REMOVIDO -- foi ele que fez o grafico da Conta A
# sair diferente dos outros dois clientes. Nao reintroduzir.
function New-BarChartPng([string]$outPng, $labels, $values, [string]$hexAccent,
                         [double]$mediaBaseline, [string]$labelBaseline,
                         [double]$capContratada, [string]$labelContratado,
                         [string]$explicaPercentual) {
    $w = 1600; $h = 620
    $bmp = New-Object Drawing.Bitmap($w, $h)
    $g = [Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode     = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $g.Clear([Drawing.Color]::White)

        $accent = Hex-ToColor $hexAccent
        $gray   = [Drawing.Color]::FromArgb(120,120,120)
        $fVal   = New-Object Drawing.Font($FONT, 30, [Drawing.FontStyle]::Bold)
        $fLbl   = New-Object Drawing.Font($FONT, 28)
        $fNote  = New-Object Drawing.Font($FONT, 24)
        $brAcc  = New-Object Drawing.SolidBrush($accent)
        $brTxt  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(60,60,60))
        $brGray = New-Object Drawing.SolidBrush($gray)
        $penAxis = New-Object Drawing.Pen($gray, 2)

        $n = @($values).Count
        if ($n -eq 0) { return }
        $maxV = 0.0
        foreach ($v in $values) { if ([double]$v -gt $maxV) { $maxV = [double]$v } }
        if ($mediaBaseline -gt $maxV) { $maxV = $mediaBaseline }
        # A capacidade contratada entra na escala: se ficasse fora, a linha sairia do
        # grafico e o gestor nao veria QUANTO espaco ainda cabe -- que e o ponto da secao.
        if ($capContratada -gt $maxV) { $maxV = $capContratada }
        if ($maxV -le 0) { $maxV = 1.0 }

        # padB reserva espaco para os rotulos de mes E para as legendas.
        # As legendas ficam no rodape, nao junto das linhas: coladas na linha elas eram
        # desenhadas POR CIMA das barras e ficavam ilegiveis (medido 05/08/2026).
        $temLeg1 = ($mediaBaseline -gt 0)
        $temLeg2 = ($capContratada -gt 0)
        $padL = 40.0; $padR = 40.0; $padT = 80.0

        # A explicacao do percentual e uma frase longa: quebra por palavra, igual a nota.
        # Sem isso ela saia do bitmap cortada no meio ("...(200.00").
        $explicaLinhas = @()
        if (($capContratada -gt 0) -and (-not [string]::IsNullOrWhiteSpace($explicaPercentual))) {
            $maxLarg2 = ($w - $padL - $padR) - 20.0
            $at = ""
            foreach ($p in ($explicaPercentual -split ' ')) {
                if ($at -eq "") { $t2 = $p } else { $t2 = $at + " " + $p }
                if ((($g.MeasureString($t2, $fNote)).Width -gt $maxLarg2) -and ($at -ne "")) {
                    $explicaLinhas += $at
                    $at = $p
                } else { $at = $t2 }
            }
            if ($at -ne "") { $explicaLinhas += $at }
        }

        # padB cresce com a quantidade REAL de linhas de legenda, incluindo as da nota
        # quebrada. Valor fixo estourava o bitmap quando a nota ocupava duas linhas.
        $nLeg = 0
        if ($temLeg1) { $nLeg = $nLeg + 1 }
        if ($temLeg2) { $nLeg = $nLeg + 1 }
        # + as linhas que explicam a conta do percentual
        $nLeg = $nLeg + $explicaLinhas.Count
        $padB = 130.0
        if ($nLeg -gt 0) { $padB = 130.0 + 60.0 + (($nLeg - 1) * 44.0) }
        $plotW = $w - $padL - $padR
        $plotH = $h - $padT - $padB
        $slot  = $plotW / $n
        $barW  = [math]::Min(($slot * 0.55), 260.0)

        # linha de media do trimestre anterior: transforma o grafico de "quanto rodou"
        # em "rodou mais ou menos que antes", que e a leitura que o gestor quer
        $yLeg = $padT + $plotH + 90.0
        # Linha 1 -- media do trimestre anterior: transforma o grafico de "quanto rodou"
        # em "rodou mais ou menos que antes", que e a leitura que o gestor quer.
        if ($temLeg1) {
            $y = $padT + $plotH - ($mediaBaseline / $maxV) * $plotH
            $penRef = New-Object Drawing.Pen($gray, 3)
            $penRef.DashStyle = [Drawing.Drawing2D.DashStyle]::Dash
            $g.DrawLine($penRef, [single]$padL, [single]$y, [single]($padL + $plotW), [single]$y)
            $g.DrawLine($penRef, [single]$padL, [single]($yLeg + 14), [single]($padL + 60), [single]($yLeg + 14))
            $g.DrawString($labelBaseline, $fNote, $brGray, [single]($padL + 74), [single]$yLeg)
            $penRef.Dispose()
            $yLeg = $yLeg + 44.0
        }
        # Linha 2 -- ambiente contratado. Tracado ponto-traco e na cor de destaque para
        # nao ser confundido com a linha de media, que e cinza.
        # UNICO elemento opcional do grafico. Sem capacidade, simplesmente NAO se desenha:
        # nao existe ramo `else` aqui de proposito (ver a regra no topo da funcao).
        if ($temLeg2) {
            $y2 = $padT + $plotH - ($capContratada / $maxV) * $plotH
            $penCap = New-Object Drawing.Pen($accent, 3)
            $penCap.DashStyle = [Drawing.Drawing2D.DashStyle]::DashDot
            $g.DrawLine($penCap, [single]$padL, [single]$y2, [single]($padL + $plotW), [single]$y2)
            $g.DrawLine($penCap, [single]$padL, [single]($yLeg + 14), [single]($padL + 60), [single]($yLeg + 14))
            $g.DrawString($labelContratado, $fNote, $brGray, [single]($padL + 74), [single]$yLeg)
            $penCap.Dispose()
            # avanca: sem isso a explicacao do percentual era desenhada EM CIMA desta
            $yLeg = $yLeg + 44.0
        }

        for ($i = 0; $i -lt $n; $i++) {
            $v = [double]$values[$i]
            $bh = ($v / $maxV) * $plotH
            $x = $padL + ($slot * $i) + (($slot - $barW) / 2.0)
            $y = $padT + $plotH - $bh
            $g.FillRectangle($brAcc, [single]$x, [single]$y, [single]$barW, [single]$bh)

            # Rotulo do valor e, quando ha capacidade, o percentual dela. Com a
            # capacidade no eixo as barras podem ficar pequenas, e e o texto que carrega
            # a magnitude -- por isso o percentual fica junto do numero, nao na legenda.
            $sv = Fmt-Int $v
            $sz = $g.MeasureString($sv, $fVal)
            $pct = ""
            if ($capContratada -gt 0) {
                $pct = ([math]::Round(($v / $capContratada) * 100, 2)).ToString("0.00", $ptBR) + "%"
            }
            # PowerShell 5.1 NAO aceita `if` inline dentro de expressao aritmetica
            # (`$a + (if (...) {...})` da "O termo 'if' nao e reconhecido"). Use statement.
            $szP = $null
            $altura = [double]$sz.Height
            if ($pct -ne "") {
                $szP = $g.MeasureString($pct, $fNote)
                $altura = $altura + [double]$szP.Height
            }

            # Barra alta empurraria o rotulo para cima da linha da capacidade e do titulo.
            # Acima de 70% do plot, o texto vai DENTRO da barra, em branco.
            $dentro = ($bh -gt ($plotH * 0.70))
            if ($dentro) {
                $brDentro = New-Object Drawing.SolidBrush([Drawing.Color]::White)
                $yv = $y + 12
                $g.DrawString($sv, $fVal, $brDentro, [single]($x + ($barW - $sz.Width) / 2.0), [single]$yv)
                if ($pct -ne "") {
                    $g.DrawString($pct, $fNote, $brDentro, [single]($x + ($barW - $szP.Width) / 2.0), [single]($yv + $sz.Height))
                }
                $brDentro.Dispose()
            } else {
                $yv = $y - $altura - 10
                $g.DrawString($sv, $fVal, $brTxt, [single]($x + ($barW - $sz.Width) / 2.0), [single]$yv)
                if ($pct -ne "") {
                    $g.DrawString($pct, $fNote, $brGray, [single]($x + ($barW - $szP.Width) / 2.0), [single]($yv + $sz.Height))
                }
            }

            $sl = [string]$labels[$i]
            $sz2 = $g.MeasureString($sl, $fLbl)
            $g.DrawString($sl, $fLbl, $brTxt, [single]($x + ($barW - $sz2.Width) / 2.0), [single]($padT + $plotH + 16))
        }
        $g.DrawLine($penAxis, [single]$padL, [single]($padT + $plotH), [single]($padL + $plotW), [single]($padT + $plotH))

        # Explicacao da conta do percentual, pedida pela Elisama: o leitor nao deve ter
        # de deduzir de onde saiu o "1,71%". Texto do JSON (visivel ao cliente).
        foreach ($ln in $explicaLinhas) {
            $g.DrawString($ln, $fNote, $brGray, [single]$padL, [single]$yLeg)
            $yLeg = $yLeg + 44.0
        }

        $fVal.Dispose(); $fLbl.Dispose(); $fNote.Dispose()
        $brAcc.Dispose(); $brTxt.Dispose(); $brGray.Dispose(); $penAxis.Dispose()
        if (Test-Path $outPng) { Remove-Item $outPng -Force }
        $bmp.Save($outPng, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $g.Dispose(); $bmp.Dispose() }
    if (-not (Test-Path $outPng)) { throw "falha ao gerar o grafico $outPng" }
}

# ---------- helpers de Word ----------
# Construcao via Selection e o caminho mais compativel entre Word e WPS: montar por
# Range/Paragraphs.Add da diferenca de comportamento no append.
function Add-Text($sel, [string]$text, [double]$size, [bool]$bold, [int]$colorBgr, [int]$align, [double]$spaceAfter) {
    $sel.EndKey($wdStory) | Out-Null
    $sel.ParagraphFormat.Alignment = $align
    $sel.ParagraphFormat.SpaceBefore = 0
    $sel.ParagraphFormat.SpaceAfter = $spaceAfter
    $sel.Font.Name = $FONT
    $sel.Font.Size = $size
    $sel.Font.Bold = $bold
    $sel.Font.Color = $colorBgr
    $sel.TypeText($text)
    $sel.TypeParagraph()
}
function Add-SectionTitle($sel, [string]$text, [int]$accent) {
    Add-Text $sel $text 11.5 $true $accent $wdAlignLeft 3
}
function Add-Body($sel, [string]$text) {
    Add-Text $sel $text 9.5 $false 0 $wdAlignLeft 5
}
function Add-Bullets($sel, $itens) {
    foreach ($it in @($itens)) {
        Add-Text $sel ([char]0x2022 + " " + $it) 9.5 $false 0 $wdAlignLeft 2
    }
}
# Tabela sem borda com sombreamento e o truque padrao de Word para "card".
function New-BorderlessTable($doc, $sel, [int]$rows, [int]$cols) {
    $sel.EndKey($wdStory) | Out-Null
    $tbl = $doc.Tables.Add($sel.Range, $rows, $cols)
    $tbl.Borders.InsideLineStyle  = $wdLineStyleNone
    $tbl.Borders.OutsideLineStyle = $wdLineStyleNone
    $tbl.Range.Font.Name = $FONT
    $tbl.Range.Font.Size = 9.5
    # Rows.SpaceBetweenColumns lanca E_FAIL no COM do WPS (medido 05/08/2026).
    # Padding de celula e cosmetico: tentar e seguir, nunca derrubar o report por isso.
    try { $tbl.Rows.SpaceBetweenColumns = 8 } catch {
        try { $tbl.LeftPadding = 4; $tbl.RightPadding = 4 } catch {}
    }
    return $tbl
}
function Set-Cell($tbl, [int]$r, [int]$c, [string]$text, [double]$size, [bool]$bold, [int]$colorBgr) {
    $cell = $tbl.Cell($r, $c)
    $cell.Range.Text = $text
    $cell.Range.Font.Name = $FONT
    $cell.Range.Font.Size = $size
    $cell.Range.Font.Bold = $bold
    $cell.Range.Font.Color = $colorBgr
}
function After-Table($sel) {
    $sel.EndKey($wdStory) | Out-Null
    $sel.ParagraphFormat.SpaceAfter = 8
    $sel.TypeParagraph()
}

# ---------- entrada ----------
if (-not (Test-Path $DataJson)) { throw "JSON nao encontrado: $DataJson" }
$raw = [IO.File]::ReadAllText($DataJson, [Text.Encoding]::UTF8)
$d = $raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($WorkDir)) { $WorkDir = Split-Path -Parent $OutDocx }
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force $WorkDir | Out-Null }
$outDir = Split-Path -Parent $OutDocx
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

# ---------- arquiva o vigente antes de sobrescrever ----------
# O nome do entregavel e fixo (Report Estrategico <trimestre> - <Cliente>), entao cada
# geracao SOBRESCREVE a anterior. Se aquela ja tinha sido enviada ao cliente, ela se
# perderia. Aqui ela vai para _versoes-antigas antes.
#
# UMA copia por dia, de proposito: o nome do arquivo arquivado leva a data e, se ja
# existir, NAO e sobrescrito. Assim iterar dez vezes num dia preserva o estado de ANTES
# do dia -- que e o que se quer recuperar -- em vez de encher a pasta com dez copias.
# Foi o que aconteceu de verdade: 26 versoes acumuladas na pasta da Conta A.
if ($outDir -and (Test-Path $OutDocx)) {
    $arqDir = Join-Path $outDir "_versoes-antigas"
    if (-not (Test-Path $arqDir)) { New-Item -ItemType Directory -Force $arqDir | Out-Null }
    $stamp = (Get-Date).ToString("yyyy-MM-dd")
    $baseNome = [IO.Path]::GetFileNameWithoutExtension($OutDocx)
    foreach ($ext in @(".docx", ".pdf")) {
        $orig = [IO.Path]::ChangeExtension($OutDocx, $ext)
        if (-not (Test-Path $orig)) { continue }
        $alvo = Join-Path $arqDir ($baseNome + " (antes de " + $stamp + ")" + $ext)
        if (Test-Path $alvo) {
            Write-Output ("ARQUIVO: ja existe copia de hoje, mantida a original -> " + (Split-Path $alvo -Leaf))
        } else {
            # COPY, nao MOVE -- e nunca aborta o build.
            # Era Move-Item, e isso causou um estrago real em 27/08/2026: o arquivamento
            # tirou os .docx das tres pastas de entrega, o build seguinte falhou (arquivo
            # travado por um wps orfao) e as pastas ficaram com PDF do dia anterior e
            # NENHUM .docx. Copiar deixa o vigente no lugar ate o novo sobrescrever:
            # build que falha nao pode destruir o entregavel que ja estava entregue.
            try {
                Copy-Item -LiteralPath $orig -Destination $alvo -Force
                Write-Output ("ARQUIVADO (copia): " + (Split-Path $alvo -Leaf))
            } catch {
                Write-Output ("AVISO: nao consegui arquivar " + (Split-Path $orig -Leaf) + " -> " + $_.Exception.Message)
            }
        }
    }
}

$meta = Get-Prop $d "meta"

# Rotulos: canonicos primeiro, cliente depois. Assim as secoes e os rotulos sao
# IDENTICOS entre clientes por construcao -- foi o que quebrou quando cada JSON
# trazia os seus (Conta A dizia "Frentes de negocio atendidas", Conta B "Frentes
# atendidas"; e "Com trafego em producao" virou "Com execucao em producao").
if ([string]::IsNullOrWhiteSpace($RotulosJson)) {
    $RotulosJson = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "assets\rotulos-canonicos.json"
}
$script:rotulos = $null
if (Test-Path $RotulosJson) {
    $canon = [IO.File]::ReadAllText($RotulosJson, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:rotulos = $canon
    $doCliente = Get-Prop $d "rotulos"
    if ($null -ne $doCliente) {
        $sobrepostos = New-Object Collections.Generic.List[string]
        foreach ($p in $doCliente.PSObject.Properties) {
            if ($null -eq $canon.PSObject.Properties[$p.Name]) { continue }  # nao cria rotulo novo
            if ([string]$canon.$($p.Name) -ne [string]$p.Value) { $sobrepostos.Add($p.Name) }
            $canon | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
        }
        if ($sobrepostos.Count -gt 0) {
            $pendRotulo = "Rotulos do cliente divergem do canonico (" + ($sobrepostos -join ", ") +
                          "). O report deve ter os MESMOS topicos para todo cliente: corrija em assets/rotulos-canonicos.json, nao no JSON do cliente."
        }
    }
} else {
    $pendRotulo = "assets/rotulos-canonicos.json nao encontrado: os rotulos sairam do JSON do cliente e a estrutura pode divergir entre clientes."
    $script:rotulos = Get-Prop $d "rotulos"
}
$hexAccent = Get-Prop $meta "corDestaque" "#1F3864"
$accent = Hex-ToBgr $hexAccent
$gray   = Hex-ToBgr "#6E6E6E"

$pend = New-Object Collections.Generic.List[string]
foreach ($p in @(Get-Prop $d "pendencias" @())) { $pend.Add([string]$p) }

$amb  = Get-Prop $d "ambiente"
$cres = Get-Prop $d "crescimento"
$conf = Get-Prop $d "confiabilidade"
$cap  = Get-Prop $d "capacidade"
$usu  = Get-Prop $d "usuarios"
$sup  = Get-Prop $d "suporte"
$opor = @(Get-Prop $d "oportunidades" @())
$ativ = @(Get-Prop $d "atividades" @())
$naoC = @(Get-Prop $d "naoConstam" @())

if ((Count-Of $ativ) -eq 0) {
    # Nao duplicar: quem monta o JSON normalmente ja declara esta pendencia com
    # texto proprio (e acentuado). Dedupe por texto nao resolve -- as duas frases
    # divergem nos primeiros caracteres. Resolver na origem.
    $jaTem = $false
    foreach ($p in $pend) {
        if ((Strip-Acentos ([string]$p)).ToLowerInvariant() -like "*atividades em andamento*") { $jaTem = $true }
    }
    if (-not $jaTem) {
        $pend.Add("Atividades em andamento nao informadas (input manual de CSM/Projetos/Arquitetos) - bloco omitido do report.")
    }
}

# ---------- grafico ----------
$chartPng = ""
if ((Has-Prop $cres "serieMensal") -and ((Count-Of $cres.serieMensal) -gt 0)) {
    $labels = @(); $values = @()
    foreach ($b in @($cres.serieMensal)) { $labels += [string]$b.mes; $values += [double]$b.execucoes }
    # A linha de media do trimestre anterior SAIU do grafico (decisao da Elisama,
    # 19/08/2026). No eixo da capacidade contratada ela vira uma lasca colada no eixo e
    # so suja o desenho; a comparacao entre trimestres ja esta na TABELA logo acima, que
    # e onde ela se le bem. O grafico agora responde uma pergunta so: quanto do plano
    # esta em uso.
    $mediaBase = 0.0; $labelBase = ""
    # Segunda linha de referencia: o ambiente contratado. Sem ela o grafico responde
    # "rodou mais que antes?"; com ela responde tambem "quanto ainda cabe no plano?",
    # que e a pergunta da secao de capacidade de crescimento.
    $capMensal = 0.0; $labelCap = ""
    $capIn = Get-Prop $cres "contratadoMensal" $null
    # O guard que tirava a capacidade da escala quando ela era muito maior que as barras
    # FOI REMOVIDO por decisao da Elisama (19/08/2026): a capacidade fica no eixo mesmo
    # quando as barras ficam pequenas, porque a pergunta da secao e "quanto do plano
    # esta em uso" e barra pequena E a resposta. Para o leitor nao ficar sem referencia,
    # cada barra ganha o percentual e a legenda explica a conta.
    if (($null -ne $capIn) -and ([double]$capIn -gt 0)) {
        $capMensal = [double]$capIn
        $rc = Get-Prop $cres "rotuloContratado" ""
        if ([string]::IsNullOrWhiteSpace($rc)) {
            $rc = "ambiente contratado"
            $pend.Add("crescimento.rotuloContratado ausente no JSON: a legenda do grafico saiu sem acentuacao. Preencher antes de enviar ao cliente.")
        }
        $labelCap = $rc + ": " + (Fmt-Int $capMensal)
    } else {
        # Sem capacidade o grafico sai no padrao, SEM nada no lugar da linha.
        # `crescimento.notaContratado` foi ELIMINADO do contrato do JSON: era ele que punha
        # "Sem permissao para quantificar os dados" dentro do PNG e fazia o grafico de um
        # cliente sair diferente dos outros. Se aparecer num JSON antigo, isso e pendencia.
        if (-not [string]::IsNullOrWhiteSpace((Get-Prop $cres "notaContratado" ""))) {
            $pend.Add("crescimento.notaContratado presente no JSON e IGNORADO: o padrao do grafico nunca muda, e ausencia de dado se declara em texto do documento (naoConstam), nao dentro do PNG. Remova o campo do JSON.")
        }
        $pend.Add("Capacidade contratada nao entrou: sem acesso a tela de Gerenciamento de Conta. O grafico saiu no padrao, sem a linha de referencia, e a ausencia deve estar declarada em naoConstam.")
    }
    $chartPng = Join-Path $WorkDir "grafico-crescimento.png"
    $explicaPct = Get-Prop $cres "explicaPercentual" ""
    if (($capMensal -gt 0) -and [string]::IsNullOrWhiteSpace($explicaPct)) {
        $pend.Add("crescimento.explicaPercentual ausente no JSON: o grafico saiu sem a legenda que explica a conta do percentual (execucoes do mes / capacidade contratada). A Elisama pediu essa explicacao em 19/08/2026.")
    }
    New-BarChartPng $chartPng $labels $values $hexAccent $mediaBase $labelBase $capMensal $labelCap $explicaPct
}

# ---------- blocos ----------
function Block-Header($sel) {
    # Marca acima do titulo. O manual de tom de voz e explicito: APIPASS em TODAS as
    # maiusculas -- "APIPass", "Apipass" e "ApiPass" sao usos incorretos. Vem do JSON
    # como todo texto visivel, mas o fallback tambem respeita a regra.
    $marca = Get-Prop $meta "marca" ""
    if (-not [string]::IsNullOrWhiteSpace($marca)) {
        Add-Text $sel $marca 9 $true $accent $wdAlignLeft 2
    }
    Add-Text $sel (Get-Prop $meta "titulo" "Report Estrategico Trimestral") 18 $true $accent $wdAlignLeft 0
    $sub = (Get-Prop $meta "cliente" "") + "  |  " + (Get-Prop $meta "periodoLabel" "")
    if ((Get-Prop $meta "parcial" $false) -eq $true) { $sub = $sub + "  |  PERIODO PARCIAL" }
    Add-Text $sel $sub 10.5 $false $gray $wdAlignLeft 10
}
function Block-Resumo($sel) {
    $r = Get-Prop $d "resumo" ""
    if (-not [string]::IsNullOrWhiteSpace($r)) { Add-Body $sel $r }
}
function Block-KpiBand($doc, $sel) {
    $areas = Count-Of (Get-Prop $amb "areas" @())
    $exec = "-"
    if (Has-Prop $cres "atual") { $exec = Fmt-Int (Get-Prop $cres.atual "execucoes" 0) }
    $vals = @(
        @{ n = (Fmt-Int (Get-Prop $amb "projetosAtivos" 0));    r = (Rot "projetosAtivos" "Projetos ativos") },
        @{ n = (Fmt-Int (Get-Prop $amb "integracoesAtivas" 0)); r = (Rot "integracoesAtivas" "Integracoes ativas") },
        @{ n = (Fmt-Int $areas);                                r = (Rot "areasAtendidas" "Areas de negocio atendidas") },
        @{ n = $exec;                                           r = (Rot "execucoesTrimestre" "Execucoes no trimestre") }
    )
    $tbl = New-BorderlessTable $doc $sel 2 4
    # SEM SOMBREAMENTO DE CELULA -- decisao da Elisama, 26/08/2026.
    # O .docx e o PDF estavam corretos (14 retangulos, todos #F2F4F8, verificado nos
    # operadores graficos do PDF), mas o leitor de PDF dela renderizava uma FAIXA PRETA
    # no lugar do fundo claro, nas duas tabelas. Num documento que vai para gestor de
    # cliente, garantia de renderizacao vale mais que o destaque visual.
    # NAO reintroduzir Shading.BackgroundPatternColor sem testar no leitor dela.
    for ($c = 1; $c -le 4; $c++) {
        Set-Cell $tbl 1 $c $vals[$c-1].n 20 $true $accent
        Set-Cell $tbl 2 $c $vals[$c-1].r 8.5 $false $gray
    }
    After-Table $sel
}
function Block-Ambiente($sel, [bool]$compacto) {
    Add-SectionTitle $sel (Rot "ambiente" "Visao geral do ambiente") $accent
    if (-not $compacto) {
        $l = ((Rot "projetosAtivos" "Projetos ativos") + ": " + (Fmt-Int (Get-Prop $amb "projetosAtivos" 0)) +
              "   |   " + (Rot "integracoesAtivas" "Integracoes ativas") + ": " + (Fmt-Int (Get-Prop $amb "integracoesAtivas" 0)) +
              "   |   " + (Rot "integracoesProd" "Em producao") + ": " + (Fmt-Int (Get-Prop $amb "integracoesProd" 0)))
        Add-Text $sel $l 9.5 $true 0 $wdAlignLeft 4
    }
    $sis = @(Get-Prop $amb "sistemas" @())
    if ((Count-Of $sis) -gt 0) { Add-Body $sel ((Rot "sistemasIntegrados" "Sistemas integrados") + ": " + ($sis -join ", ") + ".") }
    # Lista dos projetos ativos. Pedido explicito: a visao do ambiente nomeia os
    # projetos, nao so conta. Formato compacto para nao estourar o limite de paginas.
    $projs = @(Get-Prop $amb "projetos" @())
    if ((Count-Of $projs) -gt 0) {
        Add-Text $sel (Rot "projetosLista" "Projetos ativos no periodo:") 9.5 $true 0 $wdAlignLeft 2
        $linhas = @()
        foreach ($p in $projs) {
            $t = [string](Get-Prop $p "nome" "")
            $qt = Get-Prop $p "integracoes" $null
            if ($null -ne $qt) {
                # Singular/plural: "1 integracoes" num documento que vai ao gestor e
                # desleixo visivel. O rotulo singular tambem vem do JSON canonico.
                $suf = if ([int]$qt -eq 1) { (Rot "integracoesSufixoSingular" "integracao") } else { (Rot "integracoesSufixo" "integracoes") }
                $t = $t + " (" + (Fmt-Int $qt) + " " + $suf + ")"
            }
            $nt = Get-Prop $p "nota" ""
            if (-not [string]::IsNullOrWhiteSpace($nt)) { $t = $t + " " + [char]0x2014 + " " + $nt }
            $linhas += $t
        }
        # Separador por CODIGO, nunca literal: este .ps1 e ASCII e um "·" literal
        # virou "Â·" no documento. Foi o proprio erro que a regra do ASCII previne.
        Add-Body $sel ($linhas -join (" " + [char]0x00B7 + " "))
    }
    $areas = @(Get-Prop $amb "areas" @())
    if ((Count-Of $areas) -gt 0) {
        $itens = @()
        foreach ($a in $areas) {
            $t = (Get-Prop $a "area" "") + " - " + (Fmt-Int (Get-Prop $a "integracoes" 0)) + " " + (Rot "integracoesSufixo" "integracoes")
            $desc = Get-Prop $a "descricao" ""
            if (-not [string]::IsNullOrWhiteSpace($desc)) { $t = $t + ": " + $desc }
            $itens += $t
        }
        Add-Bullets $sel $itens
    }
}
function Block-Crescimento($doc, $sel) {
    Add-SectionTitle $sel (Rot "crescimento" "Capacidade de crescimento") $accent
    $temBase = ((Get-Prop $cres "temBaseline" $false) -eq $true)
    if (-not $temBase) {
        Add-Body $sel ("Linha de base estabelecida neste trimestre: nao havia fotografia do trimestre anterior, " +
                       "portanto o comparativo passa a existir a partir da proxima edicao.")
    }
    if ($chartPng -ne "" -and (Test-Path $chartPng)) {
        $sel.EndKey($wdStory) | Out-Null
        $sel.ParagraphFormat.Alignment = $wdAlignCenter
        $shp = $doc.InlineShapes.AddPicture($chartPng, $false, $true, $sel.Range)
        try { $shp.LockAspectRatio = $msoTrue } catch {}
        $shp.Width = 440
        $sel.EndKey($wdStory) | Out-Null
        $sel.TypeParagraph()
        $sel.ParagraphFormat.Alignment = $wdAlignLeft
    }
    if ($temBase -and (Has-Prop $cres "baseline") -and (Has-Prop $cres "atual")) {
        $b = $cres.baseline; $a = $cres.atual
        # Rotulos PROPRIOS desta tabela. Nao reaproveitar os do bloco de ambiente:
        # la "Projetos ativos" conta o que existe cadastrado, aqui a linha mede o que
        # EXECUTOU no trimestre -- que e o numero que justifica o volume. Com o mesmo
        # rotulo nos dois lugares o gestor ve 10 e 9 para a "mesma" coisa e conclui
        # que um dos dois esta errado.
        $linhas = @(
            @{ r = (Rot "crescProjetos" "Projetos com execucao");       v1 = (Get-Prop $b "projetos" $null);    v2 = (Get-Prop $a "projetos" $null) },
            @{ r = (Rot "crescIntegracoes" "Integracoes com execucao"); v1 = (Get-Prop $b "integracoes" $null); v2 = (Get-Prop $a "integracoes" $null) },
            @{ r = (Rot "crescExecucoes" "Execucoes realizadas");       v1 = (Get-Prop $b "execucoes" $null);   v2 = (Get-Prop $a "execucoes" $null) }
        )
        # Linha do pacote contratado: entra SO quando ha dado. Sem ela a tabela mostra
        # consumo sem referencia de capacidade; com valor chutado, mostra referencia
        # falsa -- e o gestor decide plano com base nela.
        $cb = Get-Prop $b "contratado" $null
        $ca = Get-Prop $a "contratado" $null
        if (($null -ne $cb) -or ($null -ne $ca)) {
            $linhas += @{ r = (Rot "crescContratado" "Execucoes contratadas"); v1 = $cb; v2 = $ca }
        }
        $tbl = New-BorderlessTable $doc $sel ($linhas.Count + 1) 3
        Set-Cell $tbl 1 1 "" 9 $false $gray
        Set-Cell $tbl 1 2 ([string](Get-Prop $b "trimestre" "anterior")) 9 $true $gray
        Set-Cell $tbl 1 3 ([string](Get-Prop $meta "trimestre" "atual")) 9 $true $accent
        # Default $null, NAO 0: contagem de baseline ausente renderizada como "0"
        # afirmaria que o cliente tinha zero projetos no trimestre anterior -- e o
        # comparativo viraria "crescemos do nada", que e mentira. Fmt-Int($null) = "-".
        for ($i = 0; $i -lt $linhas.Count; $i++) {
            Set-Cell $tbl ($i+2) 1 $linhas[$i].r 9.5 $false 0
            Set-Cell $tbl ($i+2) 2 (Fmt-Int $linhas[$i].v1) 9.5 $false $gray
            Set-Cell $tbl ($i+2) 3 (Fmt-Int $linhas[$i].v2) 9.5 $true $accent
        }
        After-Table $sel
        # Legenda: a tabela mistura metricas de natureza diferente (o que executou vs.
        # capacidade contratada). Sem legenda o gestor compara linhas nao comparaveis.
        $leg = Get-Prop $cres "legenda" ""
        if (-not [string]::IsNullOrWhiteSpace($leg)) {
            Add-Text $sel $leg 8 $false $gray $wdAlignLeft 2
        }
    }
    $novos = @(Get-Prop $cres "novos" @())
    if ((Count-Of $novos) -gt 0) {
        $itens = @()
        foreach ($n in $novos) {
            $t = (Get-Prop $n "nome" "") + " (" + (Get-Prop $n "tipo" "") + ")"
            $pq = Get-Prop $n "paraQueServe" ""
            if (-not [string]::IsNullOrWhiteSpace($pq)) { $t = $t + " - " + $pq }
            $itens += $t
        }
        Add-Text $sel (Rot "adicionadoNoTrimestre" "Adicionado no trimestre:") 9.5 $true 0 $wdAlignLeft 2
        Add-Bullets $sel $itens
    }
    $leitura = Get-Prop $cres "leitura" ""
    if (-not [string]::IsNullOrWhiteSpace($leitura)) { Add-Body $sel $leitura }
}
# Marcador de secao ainda sem dado. RASCUNHO INTERNO por definicao: o comportamento
# padrao do report e OMITIR a secao e declarar a ausencia no rodape (`naoConstam`),
# porque uma secao vazia num documento que vai ao gestor sugere que a APIPASS nao tem
# o dado. Placeholder serve para revisar a estrutura, nao para entregar ao cliente.
function Block-EmConstrucao($sel, [string]$titulo, [string]$nota) {
    Add-SectionTitle $sel $titulo $accent
    $txt = (Rot "emConstrucao" "[Em construcao]")
    if (-not [string]::IsNullOrWhiteSpace($nota)) { $txt = $txt + " " + $nota }
    Add-Text $sel $txt 9.5 $false $gray $wdAlignLeft 5
}
# Retorna $true se o bloco existe e esta marcado como em construcao.
function Em-Construcao($obj) {
    if ($null -eq $obj) { return $false }
    return ((Get-Prop $obj "emConstrucao" $false) -eq $true)
}
function Block-Usuarios($sel) {
    # Secao AUSENTE tambem renderiza: o report tem os mesmos topicos para todo cliente.
    if ($null -eq $usu) { Block-EmConstrucao $sel (Rot "usuarios" "Usuarios ativos") (Rot "notaUsuarios" ""); return }
    if (Em-Construcao $usu) {
        Block-EmConstrucao $sel (Rot "usuarios" "Usuarios ativos") (Get-Prop $usu "nota" "")
        return
    }
    Add-SectionTitle $sel (Rot "usuarios" "Usuarios ativos") $accent
    $l = ((Fmt-Int (Get-Prop $usu "acessaram" $null)) + " de " + (Fmt-Int (Get-Prop $usu "total" $null)) +
          "   |   " + (Get-Prop $usu "percentual" "-"))
    Add-Text $sel $l 9.5 $true 0 $wdAlignLeft 3
    $leitura = Get-Prop $usu "leitura" ""
    if (-not [string]::IsNullOrWhiteSpace($leitura)) { Add-Body $sel $leitura }
}
function Block-Suporte($sel) {
    if ($null -eq $sup) { Block-EmConstrucao $sel (Rot "suporte" "Suporte") (Rot "notaSuporte" ""); return }
    if (Em-Construcao $sup) {
        Block-EmConstrucao $sel (Rot "suporte" "Suporte") (Get-Prop $sup "nota" "")
        return
    }
    Add-SectionTitle $sel (Rot "suporte" "Suporte") $accent
    # `destaque` e a linha de numeros; `leitura` e a analise. A regra da Vanessa e que
    # o bloco de suporte seja ANALISE, nao dado bruto -- entao `leitura` e obrigatoria
    # na pratica, e `destaque` sozinho nao serve.
    $dest = Get-Prop $sup "destaque" ""
    if (-not [string]::IsNullOrWhiteSpace($dest)) { Add-Text $sel $dest 9.5 $true 0 $wdAlignLeft 3 }
    # Corte por SERVICO -- regra da Elisama, 27/08/2026. O bloco de suporte informa
    # quantidade de chamados e a distribuicao por servico ("3 chamados: 2 em N1 e 1 em N3"),
    # e NAO leva tempo de resolucao: nem dias, nem horas, nem mediana. Cada item vem do
    # `byServico` do Dashboard CS - Metricas Suporte.
    $porSvc = @(Get-Prop $sup "porServico" @())
    if ((Count-Of $porSvc) -gt 0) {
        $partes = @()
        foreach ($x in $porSvc) {
            $nome = Get-Prop $x "servico" ""
            $qtd  = Get-Prop $x "quantidade" $null
            if (-not [string]::IsNullOrWhiteSpace($nome)) { $partes += ((Fmt-Int $qtd) + " " + $nome) }
        }
        if ($partes.Count -gt 0) {
            $sep = " " + [char]0x00B7 + " "
            Add-Text $sel ((Rot "suportePorServico" "Por servico:") + " " + ($partes -join $sep)) 9 $false $gray $wdAlignLeft 3
        }
    }
    $leitura = Get-Prop $sup "leitura" ""
    if (-not [string]::IsNullOrWhiteSpace($leitura)) { Add-Body $sel $leitura }
    # Guard: tempo de resolucao NAO entra mais no report. Se um JSON antigo trouxer os
    # campos ou o texto mencionar dia/hora/mediana, emite pendencia em vez de publicar calado.
    $proibidos = @("tempoMedio","tempoMediano","medianaDias","medianaHoras","mediana","diasCorridos")
    foreach ($p in $proibidos) {
        if (-not [string]::IsNullOrWhiteSpace((Get-Prop $sup $p ""))) {
            $pend.Add("suporte." + $p + " presente no JSON e IGNORADO: por decisao da Elisama (27/08/2026) o bloco de Suporte nao leva tempo de resolucao. Remova o campo.")
        }
    }
    $alvo = ($dest + " " + $leitura)
    if ($alvo -match "(?i)dia[s]? corrido|dias ute|mediana|tempo m[eé]dio|horas de resolu") {
        $pend.Add("TEXTO DE SUPORTE menciona tempo de resolucao (dia/hora/mediana). Por decisao da Elisama (27/08/2026) isso NAO entra no report -- reescreva o texto sem referencia a tempo.")
    }
}
# Capacidade contratada vs implementada. Fonte: endpoint grafana/usage-metrics/
# flow-engine-summaries com family=f (instance.quotas.capacity + deployments).
# ENQUADRAMENTO OBRIGATORIO: capacidade DISPONIVEL para crescer, nunca sobra ociosa.
# Risco levantado pela propria Vanessa -- "contratou X, usa Y" faz o cliente concluir
# que deve REDUZIR o plano. Por isso o bloco mostra o que cabe, nao o que sobra.
function Block-Capacidade($doc, $sel) {
    # OBRIGATORIO (Elisama, 26/08/2026): sem autorizacao de acesso a tela de Gerenciamento
    # de Conta, o report DIZ isso, em texto, aqui e em `naoConstam`. Sem a frase o leitor
    # compara com o report de outro cliente e conclui que ESTE saiu errado -- foi o efeito
    # real entre a Conta A e a Conta B. O texto e canonico (`semAcessoCapacidade`), nao vem
    # do JSON do cliente: nao pode depender de eu lembrar de escrever.
    if (($null -eq $cap) -or (Em-Construcao $cap)) {
        Add-SectionTitle $sel (Rot "capacidade" "Capacidade do ambiente") $accent
        $txtSem = (Rot "semAcessoCapacidade" "")
        if ([string]::IsNullOrWhiteSpace($txtSem)) {
            $txtSem = (Rot "emConstrucao" "[Em construcao]")
            $pend.Add("rotulos.semAcessoCapacidade ausente: a secao de capacidade saiu com placeholder em vez da frase que explica a falta de autorizacao de acesso. A Elisama exige a frase (26/08/2026).")
        }
        Add-Text $sel $txtSem 9.5 $false $gray $wdAlignLeft 5
        return
    }
    Add-SectionTitle $sel (Rot "capacidade" "Capacidade do ambiente") $accent
    # Fonte: Gerenciamento de Conta > CONSUMO > Flow Engine
    # (/account-manager/usage-explorer/flow-engine). Sao EXECUCOES contratadas por mes.
    #
    # A QUOTA E MENSAL E NAO ACUMULA. Uma versao anterior somava as tres quotas do
    # trimestre (200.000 x 3 = 600.000) e dividia o total do trimestre por isso. Esse
    # denominador NAO EXISTE em tela nem em contrato, e a media esconde o pico: na
    # Conta B dava 3,0% quando o mes de maior uso (maio) foi 4,26%. Se um mes chegasse
    # a 90% do limite, a media continuaria parecendo tranquila.
    # Por isso o bloco compara o MES DE MAIOR USO contra a quota MENSAL.
    $usado = Get-Prop $cap "execucoesPico" $null
    if ($null -eq $usado) { $usado = Get-Prop $cap "execucoes" $null }
    $quota = Get-Prop $cap "contratadoMensal" $null
    if ($null -eq $quota) { $quota = Get-Prop $cap "contratado" $null }
    $tbl = New-BorderlessTable $doc $sel 2 3
    Set-Cell $tbl 1 1 (Fmt-Int $usado) 20 $true $accent
    Set-Cell $tbl 1 2 (Fmt-Int $quota) 20 $true $gray
    Set-Cell $tbl 1 3 ([string](Get-Prop $cap "percentualUso" "-")) 20 $true $accent
    Set-Cell $tbl 2 1 (Rot "capExecucoes" "Execucoes no trimestre") 8.5 $false $gray
    Set-Cell $tbl 2 2 (Rot "capContratado" "Capacidade contratada") 8.5 $false $gray
    Set-Cell $tbl 2 3 (Rot "percentualUso" "Da capacidade em uso") 8.5 $false $gray
    # sem sombreamento de celula -- ver a nota em Block-KpiBand
    After-Table $sel
    # Linha secundaria: instancia e trafego. Entra so com dado; sem inventar.
    $inst = Get-Prop $cap "instancia" ""
    $traf = Get-Prop $cap "trafego" ""
    $trafQ = Get-Prop $cap "trafegoContratado" ""
    $partes = @()
    if (-not [string]::IsNullOrWhiteSpace($inst))  { $partes += ((Rot "capInstancia" "Instancia") + ": " + $inst) }
    if ((-not [string]::IsNullOrWhiteSpace($traf)) -and (-not [string]::IsNullOrWhiteSpace($trafQ))) {
        $partes += ((Rot "capTrafego" "Trafego de dados") + ": " + $traf + " de " + $trafQ)
    }
    if ($partes.Count -gt 0) { Add-Text $sel ($partes -join "   |   ") 9.5 $true 0 $wdAlignLeft 4 }
    $leitura = Get-Prop $cap "leitura" ""
    if (-not [string]::IsNullOrWhiteSpace($leitura)) { Add-Body $sel $leitura }
}
function Block-Confiabilidade($sel) {
    if ($null -eq $conf) { Block-EmConstrucao $sel (Rot "confiabilidade" "Confiabilidade das integracoes") (Rot "notaConfiabilidade" ""); return }
    Add-SectionTitle $sel (Rot "confiabilidade" "Confiabilidade das integracoes") $accent
    $l = ((Rot "execucoesTrimestre" "Execucoes no trimestre") + ": " + (Fmt-Int (Get-Prop $conf "execucoes" 0)) +
          "   |   " + (Rot "taxaSucesso" "Taxa de sucesso") + ": " + (Get-Prop $conf "taxaSucesso" "-"))
    Add-Text $sel $l 9.5 $true 0 $wdAlignLeft 3
    $leitura = Get-Prop $conf "leitura" ""
    if (-not [string]::IsNullOrWhiteSpace($leitura)) { Add-Body $sel $leitura }
}
function Block-Oportunidades($sel) {
    if ((Count-Of $opor) -eq 0) { Block-EmConstrucao $sel (Rot "oportunidades" "Oportunidades de uso") (Rot "notaOportunidades" ""); return }
    Add-SectionTitle $sel (Rot "oportunidades" "Oportunidades de uso") $accent
    foreach ($o in $opor) {

        Add-Text $sel ([char]0x2022 + " " + (Get-Prop $o "titulo" "")) 9.5 $true 0 $wdAlignLeft 1
        $txt = ""
        $ev = Get-Prop $o "evidencia" ""
        $op = Get-Prop $o "oportunidade" ""
        if (-not [string]::IsNullOrWhiteSpace($ev)) { $txt = $ev }
        if (-not [string]::IsNullOrWhiteSpace($op)) {
            # Travessao, nao ponto: juntar com ". " produzia "no ambiente. a
            # funcionalidade..." -- minuscula depois de ponto, num documento que vai
            # para o gestor decisor.
            if ($txt -ne "") { $txt = $txt + " " + [char]0x2014 + " " }
            $txt = $txt + $op
        }
        if ($txt -ne "") { Add-Text $sel ("    " + $txt) 9.5 $false 0 $wdAlignLeft 4 }
    }
}
function Block-Atividades($sel) {
    # `atividadesEmConstrucao` no JSON troca a omissao pelo placeholder.
    if ((Count-Of $ativ) -eq 0) {
        $nota = Get-Prop $d "atividadesNota" ""
        if ([string]::IsNullOrWhiteSpace($nota)) { $nota = (Rot "notaAtividades" "") }
        Block-EmConstrucao $sel (Rot "atividades" "Atividades em andamento") $nota
        return
    }
    Add-SectionTitle $sel (Rot "atividades" "Atividades em andamento") $accent
    $itens = @()
    foreach ($a in $ativ) {
        $t = (Get-Prop $a "time" "")
        $resp = Get-Prop $a "responsavel" ""
        if (-not [string]::IsNullOrWhiteSpace($resp)) { $t = $t + " (" + $resp + ")" }
        $t = $t + ": " + (Get-Prop $a "descricao" "")
        $itens += $t
    }
    Add-Bullets $sel $itens
}
# Fechamento na voz da marca. O manual de tom de voz pede equilibrio entre
# formalidade, empatia e objetividade, e endossa a humanizacao ("vamos juntos").
# `assinatura` carrega o principio: "Simplificando integracoes, impulsionando
# resultados." Ambos vem do JSON.
function Block-Fechamento($sel) {
    $fech = Get-Prop $d "fechamento" ""
    if (-not [string]::IsNullOrWhiteSpace($fech)) { Add-Body $sel $fech }
    $ass = Get-Prop $d "assinatura" ""
    if (-not [string]::IsNullOrWhiteSpace($ass)) {
        Add-Text $sel $ass 10.5 $true $accent $wdAlignLeft 4
    }
}
# Ausencia declarada. Omitir em silencio faria o gestor concluir que a APIPASS nao
# tem o dado -- e o report existe justamente para construir credibilidade.
function Block-Rodape($doc, $sel) {
    $itens = @()
    foreach ($x in $naoC) {
        $t = (Get-Prop $x "secao" "")
        $m = Get-Prop $x "motivo" ""
        if (-not [string]::IsNullOrWhiteSpace($m)) { $t = $t + " (" + $m + ")" }
        $itens += $t
    }
    # Falta de autorizacao de acesso entra AUTOMATICAMENTE, sem depender do JSON do cliente.
    # Regra da Elisama, 26/08/2026: e obrigatorio informar no relatorio, porque quem le
    # compara com o report de outro cliente e conclui que este saiu errado.
    if (($null -eq $cap) -or (Em-Construcao $cap)) {
        $curto = (Rot "semAcessoCapacidadeCurto" "")
        if (-not [string]::IsNullOrWhiteSpace($curto)) {
            $jaTem = $false
            foreach ($i in $itens) { if ($i -like "*apacidade*") { $jaTem = $true } }
            if (-not $jaTem) { $itens += $curto }
        }
    }
    if ($itens.Count -eq 0) { return }
    $sel.EndKey($wdStory) | Out-Null
    $sel.ParagraphFormat.SpaceBefore = 6
    $sel.ParagraphFormat.Borders.Item($wdBorderBottom).LineStyle = $wdLineStyleNone
    Add-Text $sel ((Rot "naoConstam" "Nao constam nesta edicao:") + " " + ($itens -join "; ") + ".") 8.5 $false $gray $wdAlignLeft 0
}

# ---------- montagem ----------
$word = $null; $doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    try { $word.DisplayAlerts = 0 } catch {}
    $doc = $word.Documents.Add()

    try {
        $ps = $doc.PageSetup
        $ps.TopMargin = 45; $ps.BottomMargin = 40; $ps.LeftMargin = 50; $ps.RightMargin = 50
    } catch { Write-Output "AVISO: PageSetup parcialmente aplicado (COM do WPS)." }

    $sel = $word.Selection

    switch ($LayoutVariant) {
        "A" {
            Block-Header $sel
            Block-Resumo $sel
            Block-Ambiente $sel $false
            Block-Crescimento $doc $sel
            Block-Capacidade $doc $sel
            Block-Usuarios $sel
            Block-Suporte $sel
            Block-Confiabilidade $sel
            Block-Oportunidades $sel
            Block-Atividades $sel
            Block-Fechamento $sel
            Block-Rodape $doc $sel
        }
        "B" {
            Block-Header $sel
            Block-KpiBand $doc $sel
            Block-Resumo $sel
            Block-Ambiente $sel $true
            Block-Crescimento $doc $sel
            Block-Capacidade $doc $sel
            Block-Usuarios $sel
            Block-Suporte $sel
            Block-Confiabilidade $sel
            Block-Oportunidades $sel
            Block-Atividades $sel
            Block-Fechamento $sel
            Block-Rodape $doc $sel
        }
        "C" {
            # Duas colunas via TABELA sem borda, nao via Section.TextColumns: colunas de
            # secao exigem quebra de secao e o reflow deixa a contagem de paginas
            # imprevisivel -- o que quebraria o guard de 2 paginas.
            # O grafico fica ACIMA da tabela: imagem dentro de celula estreita
            # espremeria os rotulos.
            Block-Header $sel
            Block-Resumo $sel
            Block-Crescimento $doc $sel
            $tbl = New-BorderlessTable $doc $sel 1 2
            $tbl.Columns.Item(1).PreferredWidthType = 2  # wdPreferredWidthPercent
            $tbl.Columns.Item(1).PreferredWidth = 50
            $tbl.Columns.Item(2).PreferredWidthType = 2
            $tbl.Columns.Item(2).PreferredWidth = 50
            $txtL = New-Object Collections.Generic.List[string]
            $txtL.Add((Rot "ambiente" "Visao geral do ambiente"))
            $sis = @(Get-Prop $amb "sistemas" @())
            if ((Count-Of $sis) -gt 0) { $txtL.Add((Rot "sistemasIntegrados" "Sistemas integrados") + ": " + ($sis -join ", ")) }
            foreach ($a in @(Get-Prop $amb "areas" @())) {
                $txtL.Add([char]0x2022 + " " + (Get-Prop $a "area" "") + " - " + (Fmt-Int (Get-Prop $a "integracoes" 0)) + " " + (Rot "integracoesSufixo" "integracoes"))
            }
            $txtR = New-Object Collections.Generic.List[string]
            $txtR.Add((Rot "oportunidades" "Oportunidades de uso"))
            foreach ($o in $opor) { $txtR.Add([char]0x2022 + " " + (Get-Prop $o "titulo" "") + " " + [char]0x2014 + " " + (Get-Prop $o "oportunidade" "")) }
            if ($null -ne $cap) {
                $txtR.Add("")
                $txtR.Add((Rot "capacidade" "Capacidade do ambiente") + " " + [char]0x2014 + " " +
                          (Fmt-Int (Get-Prop $cap "fluxosImplementados" $null)) + " de " +
                          (Fmt-Int (Get-Prop $cap "fluxosContratados" $null)) + " (" +
                          (Get-Prop $cap "percentualUso" "-") + ")")
            }
            if ($null -ne $conf) {
                $txtR.Add("")
                $txtR.Add((Rot "confiabilidade" "Confiabilidade das integracoes") + " " + [char]0x2014 + " " +
                          (Rot "taxaSucesso" "Taxa de sucesso") + ": " + (Get-Prop $conf "taxaSucesso" "-"))
            }
            Set-Cell $tbl 1 1 ($txtL -join [char]13) 9.5 $false 0
            Set-Cell $tbl 1 2 ($txtR -join [char]13) 9.5 $false 0
            $tbl.Cell(1,1).Range.Paragraphs.Item(1).Range.Font.Bold = $true
            $tbl.Cell(1,1).Range.Paragraphs.Item(1).Range.Font.Color = $accent
            $tbl.Cell(1,2).Range.Paragraphs.Item(1).Range.Font.Bold = $true
            $tbl.Cell(1,2).Range.Paragraphs.Item(1).Range.Font.Color = $accent
            After-Table $sel
            Block-Atividades $sel
            Block-Fechamento $sel
            Block-Rodape $doc $sel
        }
    }

    $doc.SaveAs([ref]$OutDocx) | Out-Null

    # ---------- guard de paginas ----------
    try { $doc.Repaginate() | Out-Null } catch {}
    $pages = 0
    try { $pages = [int]$doc.ComputeStatistics($wdStatisticPages) } catch {
        Write-Output "AVISO: ComputeStatistics indisponivel neste COM; guard de paginas NAO aplicado."
        $pages = -1
    }
    Write-Output ("Paginas: " + $pages + " (limite " + $MaxPages + ")")

    if ($pages -gt $MaxPages) {
        Write-Output ("ERRO: o report ficou com " + $pages + " paginas; o formato acordado e 1-" + $MaxPages + ".")
        Write-Output "Blocos por volume (resuma o maior, nao aumente o limite):"
        Write-Output ("  areas de negocio : " + (Count-Of (Get-Prop $amb "areas" @())))
        Write-Output ("  novos no trimestre: " + (Count-Of (Get-Prop $cres "novos" @())))
        Write-Output ("  oportunidades    : " + (Count-Of $opor))
        Write-Output ("  atividades       : " + (Count-Of $ativ))
        Write-Output ("Docx gerado para inspecao: " + $OutDocx)
        exit 4
    }

    # ---------- PDF ----------
    if ($ExportPdf) {
        $pdf = [IO.Path]::ChangeExtension($OutDocx, ".pdf")
        if (Test-Path $pdf) { Remove-Item $pdf -Force }
        $via = ""
        try {
            $doc.ExportAsFixedFormat($pdf, $wdFormatPDF)
            $via = "ExportAsFixedFormat"
        }
        catch {
            # WPS nao implementa a API inteira do Word; SaveAs com wdFormatPDF e o plano B.
            $doc.SaveAs([ref]$pdf, [ref]$wdFormatPDF) | Out-Null
            $via = "SaveAs(wdFormatPDF)"
        }
        if (Test-Path $pdf) { Write-Output ("PDF: " + $pdf + "  [via " + $via + "]") }
        else { $pend.Add("PDF nao foi gerado: nem ExportAsFixedFormat nem SaveAs(17) produziram arquivo.") }
    }

    Write-Output ("Docx: " + $OutDocx)
    Write-Output ("Layout: " + $LayoutVariant)
}
finally {
    if ($null -ne $doc)  { try { $doc.Close(0) | Out-Null } catch {} }
    if ($null -ne $word) { try { $word.Quit() | Out-Null } catch {} }
    # Close + Quit NAO bastam: medido 05/08/2026, cinco execucoes deixaram cinco
    # processos wps headless vivos, e o sexto run falhou com "Falha Ao Salvar" porque
    # o orfao ainda segurava o .docx. ReleaseComObject e o que de fato solta a
    # referencia; sem isso a skill quebra sozinha depois de algumas execucoes.
    if ($null -ne $doc)  { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($doc) } catch {} }
    if ($null -ne $word) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word) } catch {} }
    $doc = $null; $word = $null
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

# Instancias wps/et/wpp orfas travam o arquivo de saida. Antes de matar processo,
# conferir MainWindowTitle: vazio = automacao headless, preenchido = documento
# aberto por uma pessoa (matar o segundo perde o trabalho de alguem).

if (-not [string]::IsNullOrWhiteSpace($pendRotulo)) { $pend.Add($pendRotulo) }

if ($script:rotuloFaltando.Count -gt 0) {
    $pend.Add("Rotulos ausentes no bloco 'rotulos' do JSON (" + ($script:rotuloFaltando -join ", ") +
              "): sairam no fallback ASCII, SEM ACENTUACAO. Corrigir antes de enviar ao cliente.")
}

$aClass = @(Get-Prop $amb "aClassificar" @())
if ((Count-Of $aClass) -gt 0) {
    $pend.Add("Fluxos sem area de negocio classificada (" + (Count-Of $aClass) + "): preencher mapa_area_negocio na config antes de enviar ao cliente.")
}

Write-Output ""
Write-Output "--- PENDENCIAS ---"
# Dedupe exata, como rede de seguranca. A duplicidade de assunto e resolvida na
# origem (ver o guard de "atividades em andamento" acima): dedupe por semelhanca de
# texto nao funciona aqui, porque duas frases sobre o mesmo assunto divergem nos
# primeiros caracteres.
$vistos = New-Object Collections.Generic.List[string]
$final = New-Object Collections.Generic.List[string]
foreach ($p in $pend) {
    $k = (Strip-Acentos ([string]$p)).ToLowerInvariant().Trim()
    if (-not $vistos.Contains($k)) { $vistos.Add($k); $final.Add($p) }
}
if ($final.Count -eq 0) { Write-Output "(nenhuma)" }
else { foreach ($p in $final) { Write-Output ("- " + $p) } }
Write-Output "Conferencia humana obrigatoria antes de enviar ao cliente."
