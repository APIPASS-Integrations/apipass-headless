# Extrai texto de um PDF sem dependencia externa: acha os blocos stream/endstream,
# infla os que estao em FlateDecode (zlib = 2 bytes de header + deflate cru) e colhe
# as strings dos operadores de texto (Tj/TJ).
#
# LIMITE CONHECIDO (medido em 27/08/2026): este script e CEGO para os PDFs que este
# proprio ambiente gera. Rodado sobre "Report Estrategico 2026Q2 - Conta A.pdf",
# escrito minutos antes via Word COM / ExportAsFixedFormat (WPS Office), devolveu
# ZERO caractere. Funciona em PDF de terceiros -- no manual de tom de voz da marca
# (22 paginas) extraiu ~10k chars de 18 streams. A estrutura/codificacao que o WPS
# emite derrota a colheita de Tj/TJ; causa nao diagnosticada.
#
# ENTAO: para conferir o conteudo de um entregavel .docx -> .pdf, leia o .docx, nao o PDF:
#   unzip -p "arquivo.docx" word/document.xml   (unzip so existe no Bash, nao no PowerShell)
# O .docx e a origem do PDF, logo string ausente nele esta ausente no PDF.
#
# E ANTES DE CONFIAR NUM ZERO: confirme que a extracao produziu bytes. Um zero vindo de
# comando que falhou -- parametro obrigatorio faltando, ferramenta inexistente -- parece
# verificacao e nao e. Aconteceu duas vezes no mesmo dia.
param(
    [Parameter(Mandatory=$true)][string]$Pdf,
    [Parameter(Mandatory=$true)][string]$OutTxt
)
$ErrorActionPreference = "Stop"

$bytes = [IO.File]::ReadAllBytes($Pdf)
$latin = [Text.Encoding]::GetEncoding(28591)   # latin1: 1 byte = 1 char, nao corrompe binario
$raw = $latin.GetString($bytes)

function Inflate-Bytes([byte[]]$data) {
    # zlib: pula os 2 bytes de header e usa deflate cru
    try {
        $ms = New-Object IO.MemoryStream(,$data[2..($data.Length-1)])
        $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
        $out = New-Object IO.MemoryStream
        $ds.CopyTo($out)
        $ds.Dispose(); $ms.Dispose()
        return $out.ToArray()
    } catch { return $null }
}

$sb = New-Object Text.StringBuilder
$pos = 0
$nStreams = 0; $nInflated = 0; $nText = 0

while ($true) {
    $s = $raw.IndexOf("stream", $pos)
    if ($s -lt 0) { break }
    if ($s -ge 3 -and $raw.Substring($s-3,3) -eq "end") { $pos = $s + 6; continue }
    $dataStart = $s + 6
    if ($raw[$dataStart] -eq "`r") { $dataStart++ }
    if ($raw[$dataStart] -eq "`n") { $dataStart++ }
    $e = $raw.IndexOf("endstream", $dataStart)
    if ($e -lt 0) { break }
    $nStreams++
    $len = $e - $dataStart
    if ($len -gt 0) {
        $chunk = New-Object byte[] $len
        [Array]::Copy($bytes, $dataStart, $chunk, 0, $len)
        $inf = Inflate-Bytes $chunk
        if ($null -ne $inf -and $inf.Length -gt 0) {
            $nInflated++
            $txt = $latin.GetString($inf)
            if ($txt.Contains("Tj") -or $txt.Contains("TJ")) {
                $nText++
                [void]$sb.AppendLine($txt)
            }
        }
    }
    $pos = $e + 9
}

$content = $sb.ToString()

$outSb = New-Object Text.StringBuilder
$re = [regex]'\((?:\\.|[^\\()])*\)\s*Tj|\[(?:\s*\((?:\\.|[^\\()])*\)\s*-?[\d.]*\s*)+\]\s*TJ'
foreach ($m in $re.Matches($content)) {
    $seg = $m.Value
    $inner = [regex]::Matches($seg, '\((?:\\.|[^\\()])*\)')
    $line = ""
    foreach ($i in $inner) {
        $v = $i.Value.Substring(1, $i.Value.Length - 2)
        $v = [regex]::Replace($v, '\\([0-7]{1,3})', { param($mm) [char][Convert]::ToInt32($mm.Groups[1].Value, 8) })
        $v = $v -replace '\\n',"`n" -replace '\\r',"" -replace '\\t',"`t"
        $v = $v -replace '\\\(','(' -replace '\\\)',')' -replace '\\\\','\'
        $line += $v
    }
    [void]$outSb.AppendLine($line)
}

[IO.File]::WriteAllText($OutTxt, $outSb.ToString(), [Text.Encoding]::UTF8)
Write-Output ("streams: " + $nStreams + "  inflados: " + $nInflated + "  com texto: " + $nText)
Write-Output ("chars extraidos: " + $outSb.Length)
