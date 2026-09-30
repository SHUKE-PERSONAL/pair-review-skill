<#
  Split the screen 50/50: a dedicated pair-review browser showing the exported
  walkthrough on top, this terminal on the bottom (easier to read a diff this way).

  The browser runs on its own profile with a CDP port, so focus.mjs can scroll and
  highlight it without touching the operator's normal browser or keyboard focus.
  Re-running with another walkthrough reuses the open window.

  Usage (from the repo root):
    powershell -NoProfile -ExecutionPolicy Bypass \
      -File <skill>/scripts/split-view.ps1 -Html .diffwalk/<ticket>-walkthrough.html
#>
param(
    [Parameter(Mandatory = $true)] [string] $Html,
    [int] $Port = 9333
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PairReviewWin {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int t,bool r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
}
"@

$SW_RESTORE = 9
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$halfH = [int]($wa.Height / 2)
$profileDir = Join-Path $env:LOCALAPPDATA 'pair-review-browser'
$path = (Resolve-Path $Html).Path

$term = Get-Process |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -in @('WindowsTerminal', 'wt', 'conhost') } |
    Select-Object -First 1
if ($term)
{
    [PairReviewWin]::ShowWindow($term.MainWindowHandle, $SW_RESTORE) | Out-Null
    [PairReviewWin]::MoveWindow($term.MainWindowHandle, $wa.X, $wa.Y + $halfH, $wa.Width, $wa.Height - $halfH, $true) | Out-Null
    "terminal: $($term.ProcessName) -> bottom"
}
else
{
    "terminal window not found"
}

$alive = $true
try { Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 | Out-Null } catch { $alive = $false }

if ($alive)
{
    node (Join-Path $PSScriptRoot 'focus.mjs') --open $path --port $Port
}
else
{
    $exe = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe)
    {
        "neither Chrome nor Edge found"
        return
    }
    $url = 'file:///' + ($path -replace '\\', '/')
    Start-Process $exe -ArgumentList "--remote-debugging-port=$Port", "--user-data-dir=`"$profileDir`"", '--no-first-run', '--no-default-browser-check', '--new-window', $url
}

$br = $null
for ($i = 0; $i -lt 20 -and -not $br; $i++)
{
    Start-Sleep -Milliseconds 500
    $br = Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
        Where-Object { $_.CommandLine -like "*$profileDir*" -and $_.CommandLine -notlike '*--type=*' } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
}
if ($br)
{
    [PairReviewWin]::ShowWindow($br.MainWindowHandle, $SW_RESTORE) | Out-Null
    [PairReviewWin]::MoveWindow($br.MainWindowHandle, $wa.X, $wa.Y, $wa.Width, $halfH, $true) | Out-Null
    "browser: $($br.ProcessName) (CDP $Port) -> top"
}
else
{
    "pair-review browser window not found"
}
