# Set-LastTabActive.ps1
# Traz a janela do Chrome para frente e ativa a ULTIMA aba (Ctrl+9).
#
# POR QUE ISSO EXISTE: a captura do Get-DashboardPrint.ps1 -UseExistingWindow
# fotografa a aba VISIVEL da janela, nao a aba que a extensao Claude in Chrome
# esta controlando. A extensao abre uma aba nova que NAO fica em foco, entao sem
# este passo voce captura a aba antiga -- e o print sai com o mes errado, sem
# nenhum erro aparente. Aconteceu de verdade: capturou "Este mes / 171.737" em
# vez de julho.
#
# Rode SEMPRE imediatamente antes de capturar.

[CmdletBinding()]
param(
    [string]$WindowTitleMatch = "APIPASS",
    [int]$WaitSeconds = 2
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TabFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@

$p = @(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*$WindowTitleMatch*" })
if ($p.Count -eq 0) {
    Write-Output ("RESULTADO=FALHOU: nenhuma janela do Chrome com titulo contendo '" + $WindowTitleMatch + "'")
    exit 1
}

$h = $p[0].MainWindowHandle
[void][TabFocus]::ShowWindow($h, 9)      # SW_RESTORE
[void][TabFocus]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 900

# Ctrl+9 no Chrome vai para a ULTIMA aba (nao para a nona) -- deterministico,
# e a aba da extensao e sempre a mais recente.
[System.Windows.Forms.SendKeys]::SendWait("^9")
Start-Sleep -Seconds $WaitSeconds

Write-Output ("OK=ultima aba ativada na janela '" + $p[0].MainWindowTitle + "'")
