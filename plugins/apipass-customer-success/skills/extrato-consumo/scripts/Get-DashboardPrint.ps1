# Get-DashboardPrint.ps1
# Abre uma URL numa janela de navegador sem barra de endereco (--app), posiciona a
# janela num monitor escolhido, espera o carregamento e captura a area de conteudo
# num PNG. Serve para os slides do dashboard, que nao sao replicaveis (ver
# references/render-lamina.md).
#
# Reaproveita o PERFIL PADRAO do Chrome de proposito: e o que carrega a sessao
# logada na plataforma. Nao use -UserDataDir, senao cai numa tela de login.
#
# ATENCAO: rouba o foco durante a captura. Use -MonitorIndex para jogar a janela
# num monitor secundario e nao atrapalhar quem estiver usando a maquina.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$OutPng,
    [int]$MonitorIndex = 0,
    [int]$WaitSeconds = 12,
    [int]$CropTop = 0,
    [int]$CropBottom = 0,
    # Diretorio do perfil do Chrome que tem a sessao da plataforma ("Default",
    # "Profile 2", ...). NAO presuma "Default": em maquina com varios perfis a
    # sessao costuma estar em outro, e o resultado e uma tela de login.
    # Para descobrir: ler profile.info_cache em
    # %LOCALAPPDATA%\Google\Chrome\User Data\Local State e olhar qual
    # Network\Cookies foi modificado mais recentemente.
    [string]$ChromeProfile = "",
    # Captura uma janela do Chrome JA ABERTA E LOGADA em vez de abrir uma nova.
    # Necessario quando a aplicacao guarda o token em sessionStorage: sessionStorage
    # e por janela, entao qualquer janela nova nasce deslogada e nenhum truque de
    # perfil resolve. Neste modo -Url e ignorada: quem navega e filtra e a pessoa.
    [switch]$UseExistingWindow,
    [string]$WindowTitleMatch = "APIPASS",
    [switch]$KeepOpen
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Cap {
    public delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    public struct RECT { public int Left, Top, Right, Bottom; }
    public struct POINT { public int X, Y; }
}
"@

function Get-ChromeWindows {
    $found = New-Object System.Collections.ArrayList
    $cb = [Win32Cap+EnumProc]{
        param($h, $p)
        if ([Win32Cap]::IsWindowVisible($h)) {
            $sb = New-Object System.Text.StringBuilder 256
            [void][Win32Cap]::GetClassName($h, $sb, 256)
            if ($sb.ToString() -eq "Chrome_WidgetWin_1") { [void]$found.Add($h) }
        }
        return $true
    }
    [void][Win32Cap]::EnumWindows($cb, [IntPtr]::Zero)
    return $found
}

$chrome = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) {
    $chrome = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $chrome)) { throw "nem Chrome nem Edge encontrados" }
}

$screens = [System.Windows.Forms.Screen]::AllScreens
if ($MonitorIndex -ge $screens.Count) { throw "MonitorIndex $MonitorIndex nao existe (ha $($screens.Count) monitores)" }
$area = $screens[$MonitorIndex].Bounds
Write-Output ("MONITOR[$MonitorIndex]=" + $area.Width + "x" + $area.Height + " em (" + $area.X + "," + $area.Y + ")")

if ($UseExistingWindow) {
    $proc = @(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*$WindowTitleMatch*" })
    if ($proc.Count -eq 0) {
        Write-Output ("RESULTADO=FALHOU: nenhuma janela do Chrome com titulo contendo '" + $WindowTitleMatch + "'.")
        Write-Output "ACAO=abra o dashboard no Chrome, aplique o filtro do mes, e rode de novo."
        exit 4
    }
    $target = $proc[0].MainWindowHandle
    Write-Output ("JANELA_EXISTENTE='" + $proc[0].MainWindowTitle + "' handle=" + $target)
    [void][Win32Cap]::ShowWindow($target, 9)   # SW_RESTORE
    # Maximiza no monitor escolhido: sem isso o print sai do tamanho em que a janela
    # estava, e as laminas de meses diferentes ficam com proporcoes diferentes.
    [void][Win32Cap]::MoveWindow($target, $area.X, $area.Y, $area.Width, $area.Height, $true)
    [void][Win32Cap]::ShowWindow($target, 3)   # SW_MAXIMIZE
    [void][Win32Cap]::SetForegroundWindow($target)
    Start-Sleep -Seconds 2
}
else {

$before = @(Get-ChromeWindows)
Write-Output ("JANELAS_ANTES=" + $before.Count)

# --app abre sem barra de endereco nem abas: a area de cliente e so a pagina.
$args = @("--app=$Url", "--new-window", "--window-position=$($area.X),$($area.Y)", "--window-size=$($area.Width),$($area.Height)")
if ($ChromeProfile -ne "") { $args = @("--profile-directory=$ChromeProfile") + $args }
Write-Output ("PERFIL=" + $(if ($ChromeProfile -eq "") { "(padrao do Chrome)" } else { $ChromeProfile }))
Start-Process -FilePath $chrome -ArgumentList $args | Out-Null

$target = [IntPtr]::Zero
$deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 400
    $now = @(Get-ChromeWindows)
    foreach ($h in $now) {
        if ($before -notcontains $h) { $target = $h; break }
    }
    if ($target -ne [IntPtr]::Zero) { break }
}
if ($target -eq [IntPtr]::Zero) { throw "nao encontrei a janela nova do navegador - a pagina abriu numa aba existente?" }

$sb = New-Object System.Text.StringBuilder 512
[void][Win32Cap]::GetWindowText($target, $sb, 512)
Write-Output ("JANELA='" + $sb.ToString() + "'")

[void][Win32Cap]::ShowWindow($target, 3)   # SW_MAXIMIZE
[void][Win32Cap]::MoveWindow($target, $area.X, $area.Y, $area.Width, $area.Height, $true)
[void][Win32Cap]::SetForegroundWindow($target)

Write-Output ("AGUARDANDO ${WaitSeconds}s o carregamento...")
Start-Sleep -Seconds $WaitSeconds

}   # fim do modo "abrir janela nova"

$rc = New-Object Win32Cap+RECT
[void][Win32Cap]::GetClientRect($target, [ref]$rc)
$origin = New-Object Win32Cap+POINT
$origin.X = 0; $origin.Y = 0
[void][Win32Cap]::ClientToScreen($target, [ref]$origin)

$x = $origin.X
$y = $origin.Y + $CropTop
$w = $rc.Right - $rc.Left
$h = ($rc.Bottom - $rc.Top) - $CropTop - $CropBottom
if ($w -le 0 -or $h -le 0) { throw "area de captura invalida: ${w}x${h}" }
Write-Output ("CAPTURANDO ${w}x${h} em (${x},${y})")

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
$g.Dispose()

# Duas validacoes, porque uma nao basta:
#  1. cores distintas -> pega tela em branco / pagina que nao carregou
#  2. fracao de pixels claros -> pega TELA DE LOGIN. O dashboard e predominantemente
#     branco; a tela de login da APIPASS e azul-marinho em quase toda a area. Sem
#     esta checagem o script reporta OK e a tela de login vai para o extrato do cliente.
$distinct = @{}
$amostras = 0
$claros = 0
for ($px = 0; $px -lt $bmp.Width; $px += 53) {
    for ($py = 0; $py -lt $bmp.Height; $py += 47) {
        $c = $bmp.GetPixel($px, $py)
        $distinct[($c.R.ToString() + "," + $c.G.ToString() + "," + $c.B.ToString())] = 1
        $amostras++
        if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { $claros++ }
    }
}
$fracaoClara = 0.0
if ($amostras -gt 0) { $fracaoClara = [math]::Round($claros / [double]$amostras, 3) }

$dir = Split-Path $OutPng -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
if (Test-Path $OutPng) { Remove-Item $OutPng -Force }
$bmp.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# Nunca fechar a janela da pessoa: no modo -UseExistingWindow ela e a sessao logada.
if (-not $KeepOpen -and -not $UseExistingWindow) {
    [void][Win32Cap]::PostMessage($target, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_CLOSE
}

Write-Output ("PNG=" + $OutPng + " bytes=" + (Get-Item $OutPng).Length)
Write-Output ("CORES_DISTINTAS=" + $distinct.Count + "  FRACAO_CLARA=" + $fracaoClara)

if ($distinct.Count -le 3) {
    Write-Output "RESULTADO=FALHOU: captura em branco. A pagina carregou? Aumente -WaitSeconds."
    exit 2
}
if ($fracaoClara -lt 0.40) {
    # ATENCAO ao diagnostico deste guard (medido em 13/08/2026, dashboard de suporte):
    # imagem escura NAO significa necessariamente tela de login. Nesta maquina o
    # CopyFromScreen captura SDR escuro quando o monitor esta em HDR, e o conteudo
    # estava correto e autenticado. O guard acertou em BARRAR; a mensagem aponta o
    # motivo errado. Antes de refazer login, verifique se o HDR esta ligado.
    # Alternativa para conteudo LOCAL (SVG/HTML): Chrome headless com
    # --force-device-scale-factor renderiza fora da tela e nao sofre esse efeito
    # (receita em report-estrategico-trimestral/references/render-report.md).
    # Para dashboard AUTENTICADO isso ainda NAO foi testado -- dependeria do headless
    # herdar a sessao (que e cookie), o que nao foi verificado. Nao presuma.
    Write-Output "RESULTADO=FALHOU: a imagem e escura na maior parte da area. Causas possiveis: TELA DE LOGIN, ou HDR do monitor fazendo a captura sair escura com o conteudo correto."
    Write-Output "ACAO=1) confira se o HDR do monitor esta ligado; 2) se nao, faca login em https://<conta>.app.apipass.com.br no Chrome (perfil padrao), marque 'Mantenha-me conectado', e rode de novo. Para imagem limpa, o Exportar PDF da propria tela e o caminho seguro."
    Write-Output "NAO use este PNG no extrato."
    exit 3
}
Write-Output "RESULTADO=OK"
