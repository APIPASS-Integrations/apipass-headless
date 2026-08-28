# New-ExtratoPptx.ps1
# Gera o PPT do extrato mensal de consumo a partir de um JSON de dados.
# Escrito em ASCII puro de proposito: todo texto acentuado vem do JSON (lido como UTF-8),
# nunca hardcoded aqui, para evitar mismatch de encoding entre o editor e o powershell.exe.
#
# Mecanica validada em 03/08/2026 contra o deck real da Conta D. Ver
# references/render-lamina.md para o porque de cada constante.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DataJson,
    [Parameter(Mandatory=$true)][string]$TemplatePptx,
    [Parameter(Mandatory=$true)][string]$OutPptx,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [switch]$ExportReview
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$ptBR = [Globalization.CultureInfo]::GetCultureInfo("pt-BR")

# COM do WPS falha de formas pouco informativas; sem o stack trace fica cego.
trap {
    Write-Output ("ERRO: " + $_.Exception.Message)
    Write-Output "--- stack ---"
    Write-Output $_.ScriptStackTrace
    exit 1
}

# ---------- constantes COM ----------
$xlPrinter   = 2        # CopyPicture Appearance. xlScreen(1) recorta na janela invisivel do app.
$xlPicture   = -4147    # CopyPicture Format. xlBitmap(2) com xlPrinter lanca erro de intervalo.
$xlNone      = -4142
$alignRight  = -4152
$alignLeft   = -4131
$msoPicture  = 13
$GRAY_HEADER = 9211020   # BGR ~ #8C8C8C
$ZEBRA       = 15461355  # BGR ~ #EBEBEB. #F5F5F5 e claro demais: some quando a
                         # imagem e reduzida para caber no slide.
$HEADER_BLUE = 15652797  # BGR ~ #BDD7EE, o azul do cabecalho nos recortes do cliente

# A tabela e montada maior que o tamanho final no slide para que o export a 96 DPI
# sobre resolucao e a reducao deixe o texto nitido em vez de borrado.
# A razao FONT/ROWH define a proporcao da imagem: o print original da plataforma tem
# ~2.42 de proporcao (960x397 para 21 linhas). Com 18/26 chegamos perto disso.
$FONT_PT = 18.0
$ROWH_PT = 26.0

# area util de um slide 960x540 para a imagem de dados
$SLIDE_W  = 960.0
$SLIDE_H  = 540.0
$MARGIN_B = 12.0

# ---------- helpers ----------
function Strip-Diacritics([string]$s) {
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
function Norm([string]$s) { return (Strip-Diacritics $s).ToUpperInvariant().Trim() }
function Fmt-Int($n) { return ([long]$n).ToString("#,##0", $ptBR) }
function Fmt-Traf($bytes) {
    $b = [double]$bytes
    $gib = 1073741824.0; $mib = 1048576.0; $kib = 1024.0
    if ($b -ge $gib) { return ([math]::Round($b / $gib, 2)).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture) + " GB" }
    if ($b -ge $mib) { return ([math]::Round($b / $mib, 2)).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture) + " MB" }
    return ([math]::Round($b / $kib, 2)).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture) + " KB"
}

# Renderiza um range do Excel como PNG. Este e o coracao do script.
function Export-RangeAsPng($ws, $rng, [string]$outPng) {
    if (Test-Path $outPng) { Remove-Item $outPng -Force }
    $w = [double]$rng.Width
    $h = [double]$rng.Height
    $rng.CopyPicture($xlPrinter, $xlPicture) | Out-Null
    # O ChartObject PRECISA nascer com as dimensoes exatas do range:
    # Chart.Paste() estica a imagem para preencher o chart, entao qualquer
    # diferenca de tamanho vira distorcao ou corte.
    $co = $ws.ChartObjects().Add(20, ($h + 80), $w, $h)
    try {
        $ch = $co.Chart
        try { $ch.ChartArea.Border.LineStyle = $xlNone } catch {}
        $ch.Paste()
        $ch.Export($outPng, "PNG") | Out-Null
    }
    finally { $co.Delete() }
    if (-not (Test-Path $outPng)) { throw "falha ao exportar $outPng" }
}

# Escreve uma tabela na planilha. NAO devolve o range: chamadas COM vazam valores
# no pipeline do PowerShell, o que transformaria o retorno num array. O chamador
# reconstroi o range a partir de startRow + rows.Count.
# $cols: array de hashtables @{ header=""; align="L"|"R" }
# $rows: array de arrays de string (ja formatados)
function Write-Table($ws, $startRow, $cols, $rows, [bool]$zebra, [bool]$grayHeader) {
    $nc = $cols.Count
    # NumberFormat "@" (texto) ANTES de escrever: sem isso o Excel reinterpreta
    # "R$ 0,0X" como moeda e arredonda para "R$ 0,01" -- corrompendo o valor
    # unitario num slide que vai para o cliente.
    $ws.Range($ws.Cells.Item($startRow,1), $ws.Cells.Item(($startRow + $rows.Count),$nc)).NumberFormat = "@"
    for ($c = 1; $c -le $nc; $c++) {
        $cell = $ws.Cells.Item($startRow, $c)
        $cell.Value2 = [string]$cols[$c-1].header
        $cell.Font.Name = "Segoe UI"
        $cell.Font.Size = $FONT_PT
        if ($grayHeader) { $cell.Font.Color = $GRAY_HEADER } else { $cell.Font.Bold = $true }
        if ($cols[$c-1].align -eq "R") { $cell.HorizontalAlignment = $alignRight } else { $cell.HorizontalAlignment = $alignLeft }
    }
    for ($r = 0; $r -lt $rows.Count; $r++) {
        $i = $startRow + 1 + $r
        for ($c = 1; $c -le $nc; $c++) {
            $cell = $ws.Cells.Item($i, $c)
            $cell.Value2 = [string]$rows[$r][$c-1]
            $cell.Font.Name = "Segoe UI"
            $cell.Font.Size = $FONT_PT
            if ($cols[$c-1].align -eq "R") { $cell.HorizontalAlignment = $alignRight } else { $cell.HorizontalAlignment = $alignLeft }
        }
        if ($zebra -and ($r % 2 -eq 0)) {
            $ws.Range($ws.Cells.Item($i,1), $ws.Cells.Item($i,$nc)).Interior.Color = $ZEBRA
        }
    }
    # As tabelas de recorte de planilha (faturamento, chamados) tem grade no
    # original; as laminas da plataforma nao tem borda, so a faixa zebrada.
    if (-not $zebra) {
        $all = $ws.Range($ws.Cells.Item($startRow,1), $ws.Cells.Item(($startRow + $rows.Count),$nc))
        $all.Borders.LineStyle = 1
        $all.Borders.Weight = 2
        $all.Borders.Color = 8421504
        # cabecalho azul claro, como no recorte original do cliente
        $ws.Range($ws.Cells.Item($startRow,1), $ws.Cells.Item($startRow,$nc)).Interior.Color = $HEADER_BLUE
    }
    $ws.Columns.AutoFit() | Out-Null
}

# NAO existe uma funcao que devolva o Range: um Range do COM implementa IEnumerable,
# e o PowerShell desenrola o valor de retorno de uma funcao, transformando o Range
# num array de celulas. Cada chamador constroi o proprio range inline.

function Set-ShapeTextByPrefix($slide, [string]$asciiPrefix, [string]$newText, [ref]$hits) {
    foreach ($sh in @($slide.Shapes)) {
        if ($sh.HasTextFrame -ne -1) { continue }
        if ($sh.TextFrame.HasText -ne -1) { continue }
        $cur = Norm $sh.TextFrame.TextRange.Text
        if ($cur.StartsWith($asciiPrefix)) {
            $sh.TextFrame.TextRange.Text = $newText
            $hits.Value = $hits.Value + 1
            return $true
        }
    }
    return $false
}

# Troca a imagem de um slide preservando a geometria da original.
# Se $pngPath for vazio, apaga a imagem e deixa um aviso visivel no lugar.
function Set-SlidePicture($slide, [string]$pngPath, [string]$placeholderText) {
    # Apaga SOMENTE a imagem de dados, que e a de maior area. Os slides tambem
    # carregam a marca d'agua do logo APIPASS (~152x125 no topo-esquerdo) como
    # imagem; apagar todas remove o logo do deck.
    $target = $null
    $maxArea = 0.0
    foreach ($sh in @($slide.Shapes)) {
        if ($sh.Type -ne $msoPicture) { continue }
        $area = [double]$sh.Width * [double]$sh.Height
        if ($area -gt $maxArea) { $maxArea = $area; $target = $sh }
    }

    $geo = $null
    if ($null -ne $target) {
        $geo = @([double]$target.Left, [double]$target.Top, [double]$target.Width, [double]$target.Height)
        $target.Delete()
    } else {
        $geo = @(15.0, 120.0, 930.0, 300.0)
    }

    if ([string]::IsNullOrEmpty($pngPath)) {
        $tb = $slide.Shapes.AddTextbox(1, $geo[0] + 20, $geo[1] + 40, $geo[2] - 40, 60)
        $tb.TextFrame.TextRange.Text = $placeholderText
        $tb.TextFrame.TextRange.Font.Size = 20
        $tb.TextFrame.TextRange.Font.Bold = $true
        $tb.TextFrame.TextRange.Font.Color.RGB = 255   # vermelho, BGR
        return $false
    }

    # A proporcao vem do proprio arquivo PNG, nao de propriedades COM: o WPS
    # devolve tipos inconsistentes em Shape.Width/Height dependendo de como o
    # shape foi criado, e um [double] sobre isso estoura.
    $img = [System.Drawing.Image]::FromFile($pngPath)
    $pw = [double]$img.Width
    $ph = [double]$img.Height
    $img.Dispose()

    # Encaixa dentro da caixa da imagem ORIGINAL, preservando a proporcao.
    # Respeitar geo[3] (altura original) e essencial: no slide de Faturamento a
    # caixa termina acima do texto do aceite, e esticar ate o fim do slide faz a
    # tabela cobrir esse texto.
    $top   = [double]$geo[1]
    $boxW  = [double]$geo[2]
    if ($boxW -le 0 -or $boxW -gt 930) { $boxW = 930.0 }
    $boxH  = [double]$geo[3]
    $maxH  = $SLIDE_H - $top - $MARGIN_B
    if ($boxH -le 0 -or $boxH -gt $maxH) { $boxH = $maxH }
    if ($boxH -lt 60) { $boxH = 60.0 }

    $scale   = [math]::Min(($boxW / $pw), ($boxH / $ph))
    $targetW = $pw * $scale
    $targetH = $ph * $scale
    $left    = ($SLIDE_W - $targetW) / 2.0

    # AddPicture(FileName, LinkToFile, SaveWithDocument, Left, Top, Width, Height)
    $slide.Shapes.AddPicture($pngPath, 0, -1, $left, $top, $targetW, $targetH) | Out-Null
    return $true
}

# ---------- entrada ----------
if (-not (Test-Path $DataJson))     { throw "JSON de dados nao encontrado: $DataJson" }
if (-not (Test-Path $TemplatePptx)) { throw "template pptx nao encontrado: $TemplatePptx" }
if (-not (Test-Path $WorkDir))      { New-Item -ItemType Directory -Force $WorkDir | Out-Null }

$data = [System.IO.File]::ReadAllText($DataJson, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$itensPorLamina = 20
if ($data.itensPorLamina) { $itensPorLamina = [int]$data.itensPorLamina }

$pendencias = New-Object System.Collections.ArrayList

# ---------- 1. renderizar imagens no Excel ----------
$laminaPngs = New-Object System.Collections.ArrayList
$faturamentoPng = ""
$chamadosPng = ""

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false
$wb = $null
try {
    $wb = $xl.Workbooks.Add()

    # --- laminas de "extrato de consumo geral"
    $fluxos = @($data.fluxos)
    if ($fluxos.Count -eq 0) {
        [void]$pendencias.Add("Nenhum fluxo no JSON - as laminas de consumo geral nao foram geradas.")
    } else {
        # a tela da plataforma ordena por REQUESTS desc
        $fluxos = $fluxos | Sort-Object -Property @{Expression={[long]$_.requests}; Descending=$true}
        $cols = @(
            @{header=$data.rotulos.projeto;   align="L"},
            @{header=$data.rotulos.fluxo;     align="L"},
            @{header=$data.rotulos.stage;     align="L"},
            @{header=$data.rotulos.execucoes; align="R"},
            @{header=$data.rotulos.requests;  align="R"},
            @{header=$data.rotulos.trafego;   align="R"}
        )
        $nLaminas = [math]::Ceiling($fluxos.Count / [double]$itensPorLamina)
        for ($p = 0; $p -lt $nLaminas; $p++) {
            $chunk = $fluxos | Select-Object -Skip ($p * $itensPorLamina) -First $itensPorLamina
            $rows = New-Object System.Collections.ArrayList
            foreach ($f in $chunk) {
                [void]$rows.Add(@(
                    [string]$f.projeto,
                    [string]$f.fluxo,
                    [string]$f.stage,
                    (Fmt-Int $f.execucoes),
                    (Fmt-Int $f.requests),
                    (Fmt-Traf $f.trafegoBytes)
                ))
            }
            $ws = $wb.Worksheets.Add()
            Write-Table $ws 1 $cols $rows $true $true | Out-Null
            $rng = $ws.Range($ws.Cells.Item(1,1), $ws.Cells.Item((1 + $rows.Count), $cols.Count))
            $rng.RowHeight = $ROWH_PT
            $png = Join-Path $WorkDir ("lamina-{0:d2}.png" -f ($p + 1))
            Export-RangeAsPng $ws $rng $png | Out-Null
            [void]$laminaPngs.Add($png)
        }
        Write-Output ("LAMINAS_GERADAS=" + $laminaPngs.Count + " (de " + $fluxos.Count + " linhas fluxo x stage)")
    }

    # --- tabela de faturamento (sempre derivavel do nosso proprio calculo)
    if ($data.faturamento) {
        $cols = @(
            @{header=$data.faturamento.rotulos.servico;  align="L"},
            @{header=$data.faturamento.rotulos.qtde;     align="R"},
            @{header=$data.faturamento.rotulos.unitario; align="R"},
            @{header=$data.faturamento.rotulos.total;    align="R"}
        )
        $rows = New-Object System.Collections.ArrayList
        foreach ($fx in @($data.faturamento.fixos)) {
            [void]$rows.Add(@([string]$fx.servico, "", "", [string]$fx.total))
        }
        $t = $data.faturamento.tier
        [void]$rows.Add(@([string]$t.label, [string]$t.qtde, [string]$t.unitario, [string]$t.total))
        [void]$rows.Add(@("", "", [string]$data.faturamento.rotulos.totalGeral, [string]$data.faturamento.totalGeral))
        $ws = $wb.Worksheets.Add()
        Write-Table $ws 1 $cols $rows $false $false | Out-Null
        $rng = $ws.Range($ws.Cells.Item(1,1), $ws.Cells.Item((1 + $rows.Count), $cols.Count))
        $rng.RowHeight = $ROWH_PT
        $faturamentoPng = Join-Path $WorkDir "faturamento.png"
        Export-RangeAsPng $ws $rng $faturamentoPng | Out-Null
        Write-Output "FATURAMENTO_PNG=ok"
    } else {
        [void]$pendencias.Add("Bloco 'faturamento' ausente no JSON - slide de Faturamento ficou sem tabela.")
    }

    # --- tabela de chamados (depende de export manual do Movidesk)
    if ($data.chamados -and @($data.chamados).Count -gt 0) {
        $hdrs = @($data.chamadosColunas)
        $cols = New-Object System.Collections.ArrayList
        foreach ($h in $hdrs) { [void]$cols.Add(@{header=[string]$h; align="L"}) }
        $rows = New-Object System.Collections.ArrayList
        foreach ($ch in @($data.chamados)) {
            $line = New-Object System.Collections.ArrayList
            foreach ($h in $hdrs) { [void]$line.Add([string]$ch.$h) }
            [void]$rows.Add($line.ToArray())
        }
        $ws = $wb.Worksheets.Add()
        Write-Table $ws 1 $cols.ToArray() $rows $false $false | Out-Null
        $rng = $ws.Range($ws.Cells.Item(1,1), $ws.Cells.Item((1 + $rows.Count), $cols.Count))
        $rng.RowHeight = $ROWH_PT
        $chamadosPng = Join-Path $WorkDir "chamados.png"
        Export-RangeAsPng $ws $rng $chamadosPng | Out-Null
        Write-Output ("CHAMADOS_PNG=ok (" + @($data.chamados).Count + " chamados)")
    } else {
        [void]$pendencias.Add("Sem chamados no JSON (nao ha MCP do Movidesk) - slide de Suporte marcado como PENDENTE.")
    }

    $wb.Close($false); $wb = $null
}
finally {
    if ($wb -ne $null) { try { $wb.Close($false) } catch {} }
    try { $xl.Quit() } catch {}
    [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
}

# ---------- 2. montar o PPT ----------
if (Test-Path $OutPptx) {
    try { Remove-Item $OutPptx -Force -ErrorAction Stop }
    catch { throw "nao consegui sobrescrever $OutPptx - feche o arquivo (ou mate processos wps/wpp orfaos) e rode de novo" }
}
Copy-Item $TemplatePptx $OutPptx

$pp = New-Object -ComObject PowerPoint.Application
$pr = $null
try {
    $pr = $pp.Presentations.Open($OutPptx, $false, $false, $false)
    $hits = 0

    # --- slide 1: capa
    [void](Set-ShapeTextByPrefix $pr.Slides.Item(1) "EXTRATO DE CONSUMO" $data.capaTexto ([ref]$hits))

    # --- localizar as laminas de consumo geral pelo titulo
    $laminaIdxs = New-Object System.Collections.ArrayList
    for ($i = 1; $i -le $pr.Slides.Count; $i++) {
        foreach ($sh in @($pr.Slides.Item($i).Shapes)) {
            if ($sh.HasTextFrame -ne -1) { continue }
            if ($sh.TextFrame.HasText -ne -1) { continue }
            if ((Norm $sh.TextFrame.TextRange.Text).StartsWith("EXTRATO DE CONSUMO GERAL")) {
                [void]$laminaIdxs.Add($i); break
            }
        }
    }
    if ($laminaIdxs.Count -eq 0) { throw "nao encontrei nenhum slide 'Extrato de consumo geral' no template" }
    $firstLamina = [int]$laminaIdxs[0]

    # --- slides de resumo (antes das laminas): textos + placeholders dos prints manuais
    for ($i = 2; $i -lt $firstLamina; $i++) {
        $sl = $pr.Slides.Item($i)
        $titulo = ""
        foreach ($sh in @($sl.Shapes)) {
            if ($sh.HasTextFrame -ne -1) { continue }
            if ($sh.TextFrame.HasText -ne -1) { continue }
            $t = Norm $sh.TextFrame.TextRange.Text
            if ($t.StartsWith("EXTRATO DE CONSUMO TOTAL") -or $t.StartsWith("EXECUCOES A SEREM REMOVIDAS") -or $t.StartsWith("EXTRATO DE ACIONAMENTOS") -or $t.StartsWith("FATURAMENTO")) { $titulo = $t }
        }

        if ($titulo.StartsWith("EXTRATO DE CONSUMO TOTAL")) {
            [void](Set-ShapeTextByPrefix $sl "TOTAL DO PERIODO" $data.slideTotal.totalPeriodo ([ref]$hits))
            [void](Set-SlidePicture $sl "" $data.avisos.colarPrintTotal)
            [void]$pendencias.Add("Slide '" + $data.titulos.total + "': colar o print do dashboard do ambiente (filtro do mes completo).")
        }
        elseif ($titulo.StartsWith("EXECUCOES A SEREM REMOVIDAS")) {
            # a ordem importa: "TOTAL FINAL DO PERIODO" contem "DO PERIODO",
            # por isso trocamos o mais especifico primeiro.
            [void](Set-ShapeTextByPrefix $sl "TOTAL FINAL DO PERIODO" $data.slideRemovidas.totalFinal ([ref]$hits))
            [void](Set-ShapeTextByPrefix $sl "TOTAL DO PERIODO" $data.slideRemovidas.totalPeriodo ([ref]$hits))
            [void](Set-SlidePicture $sl "" $data.avisos.colarPrintProjeto)
            [void]$pendencias.Add("Slide '" + $data.titulos.removidas + "': colar o print do dashboard filtrado pelo projeto descontado.")
        }
        elseif ($titulo.StartsWith("EXTRATO DE ACIONAMENTOS")) {
            if ([string]::IsNullOrEmpty($chamadosPng)) {
                [void](Set-SlidePicture $sl "" $data.avisos.faltaMovidesk)
            } else {
                [void](Set-SlidePicture $sl $chamadosPng "")
            }
        }
        elseif ($titulo.StartsWith("FATURAMENTO")) {
            if ($data.aceiteTexto) {
                [void](Set-ShapeTextByPrefix $sl "RECEBEMOS O ACEITE" $data.aceiteTexto ([ref]$hits))
            } else {
                [void]$pendencias.Add("Data de aceite da fatura anterior nao informada - texto do slide de Faturamento nao foi atualizado.")
            }
            if ([string]::IsNullOrEmpty($faturamentoPng)) {
                [void](Set-SlidePicture $sl "" $data.avisos.faltaFaturamento)
            } else {
                [void](Set-SlidePicture $sl $faturamentoPng "")
            }
        }
    }

    # --- ajustar a quantidade de laminas e trocar as imagens
    if ($laminaPngs.Count -gt 0) {
        # deixa exatamente uma lamina como molde
        for ($k = $laminaIdxs.Count - 1; $k -ge 1; $k--) {
            $pr.Slides.Item([int]$laminaIdxs[$k]).Delete()
        }
        # duplica ate atingir a quantidade necessaria
        for ($k = 2; $k -le $laminaPngs.Count; $k++) {
            $pr.Slides.Item($firstLamina).Duplicate() | Out-Null
        }
        for ($k = 0; $k -lt $laminaPngs.Count; $k++) {
            $sl = $pr.Slides.Item($firstLamina + $k)
            [void](Set-SlidePicture $sl ([string]$laminaPngs[$k]) "")
        }
        Write-Output ("SLIDES_LAMINA=" + $laminaPngs.Count + " a partir do slide " + $firstLamina)
    }

    Write-Output ("TEXTOS_TROCADOS=" + $hits)
    Write-Output ("TOTAL_SLIDES=" + $pr.Slides.Count)

    if ($ExportReview) {
        $revDir = Join-Path $WorkDir "review"
        if (-not (Test-Path $revDir)) { New-Item -ItemType Directory -Force $revDir | Out-Null }
        for ($i = 1; $i -le $pr.Slides.Count; $i++) {
            $pr.Slides.Item($i).Export((Join-Path $revDir ("slide-{0:d2}.png" -f $i)), "PNG", 1600, 900)
        }
        Write-Output ("REVIEW_PNGS=" + $revDir)
    }

    $pr.Save()
    $pr.Close(); $pr = $null
}
finally {
    if ($pr -ne $null) { try { $pr.Close() } catch {} }
    try { $pp.Quit() } catch {}
    [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
}

Write-Output ("PPTX=" + $OutPptx)
Write-Output "--- PENDENCIAS ---"
if ($pendencias.Count -eq 0) { Write-Output "(nenhuma)" }
foreach ($p in $pendencias) { Write-Output ("- " + $p) }
