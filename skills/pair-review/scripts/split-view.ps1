<#
  Split the screen 50/50: a browser showing the exported walkthrough on top,
  this terminal on the bottom (easier to read a diff this way).

  Usage (from the repo root):
    powershell -NoProfile -ExecutionPolicy Bypass \
      -File <skill>/scripts/split-view.ps1 -Html .diffwalk/<ticket>-walkthrough.html
#>
param(
    [Parameter(Mandatory = $true)] [string] $Html
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PairReviewWin {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int t,bool r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@

$SW_RESTORE = 9
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$halfH = [int]($wa.Height / 2)

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

$path = (Resolve-Path $Html).Path
$browsers = 'msedge', 'chrome', 'firefox'
$before = @((Get-Process $browsers -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }).Id)

Start-Process $path
Start-Sleep -Seconds 5

$br = Get-Process $browsers -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and ($before -notcontains $_.Id) } |
    Select-Object -First 1
if (-not $br)
{
    # Re-used an already-open browser: fall back to its existing window.
    $br = Get-Process $browsers -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
}
if ($br)
{
    [PairReviewWin]::ShowWindow($br.MainWindowHandle, $SW_RESTORE) | Out-Null
    [PairReviewWin]::MoveWindow($br.MainWindowHandle, $wa.X, $wa.Y, $wa.Width, $halfH, $true) | Out-Null
    [PairReviewWin]::SetForegroundWindow($br.MainWindowHandle) | Out-Null
    "browser: $($br.ProcessName) -> top"
}
else
{
    "browser window not found"
}
