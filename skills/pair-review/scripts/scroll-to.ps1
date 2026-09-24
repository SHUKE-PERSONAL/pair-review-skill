<#
  Jump the already-open walkthrough browser to a specific change anchor
  (e.g. #change-003) so the operator sees the right block without manual
  scrolling, right as the agent starts explaining that unit.

  Usage (from the repo root):
    powershell -NoProfile -ExecutionPolicy Bypass \
      -File <skill>/scripts/scroll-to.ps1 -Html .diffwalk/<ticket>-walkthrough.html -Anchor change-003
#>
param(
    [Parameter(Mandatory = $true)] [string] $Html,
    [Parameter(Mandatory = $true)] [string] $Anchor
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ScrollToWin {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@

$SW_RESTORE = 9
$browsers = 'msedge', 'chrome', 'firefox'

$br = Get-Process $browsers -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $br)
{
    "browser window not found"
    return
}

$path = (Resolve-Path $Html).Path -replace '\\', '/'
$url = "file:///$path#$Anchor"

[ScrollToWin]::ShowWindow($br.MainWindowHandle, $SW_RESTORE) | Out-Null
[ScrollToWin]::SetForegroundWindow($br.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 300

[System.Windows.Forms.SendKeys]::SendWait('^l')
Start-Sleep -Milliseconds 150
[System.Windows.Forms.SendKeys]::SendWait($url)
Start-Sleep -Milliseconds 150
# One Enter often just dismisses the omnibox autocomplete suggestion instead
# of navigating; a second Enter reliably commits the typed URL.
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Milliseconds 150
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')

"browser -> $url"
