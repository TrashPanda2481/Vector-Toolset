<#
.SYNOPSIS
    Vector Toolset - Windows Repair
.DESCRIPTION
    A menu wrapper around the built-in repair tools: SFC, DISM health,
    and chkdsk. Works on a live Windows system or, from WinPE, against a
    mounted offline Windows volume.
.PARAMETER ToolsetRoot
    Path to the toolkit root (set automatically by the launcher).
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent)
)

# Needs Administrator for DISM, SFC, and chkdsk.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  This tool needs Administrator. Relaunching..." -ForegroundColor Yellow
    $relArgs = "-ExecutionPolicy Bypass -NoProfile -NoExit -File `"$PSCommandPath`" -ToolsetRoot `"$ToolsetRoot`""
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $relArgs } catch { Write-Host "  Elevation cancelled." -ForegroundColor Red }
    return
}

function Read-WindowsDrive {
    Write-Host ""
    Write-Host "  Offline mode. Enter the drive letter of the target Windows install"
    Write-Host "  (for example D). Leave blank to cancel."
    $d = Read-Host "  Windows drive"
    if ([string]::IsNullOrWhiteSpace($d)) { return $null }
    $d = $d.Trim().TrimEnd(':')
    if (-not (Test-Path "${d}:\Windows")) {
        Write-Host "  No \Windows folder found on ${d}:. Check the letter." -ForegroundColor Red
        return $null
    }
    return $d
}

$inWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'

while ($true) {
    Write-Host ""
    Write-Host "=== Vector Toolset - Windows Repair ===" -ForegroundColor Cyan
    Write-Host ("  Mode: " + $(if ($inWinPE) { 'WinPE (offline)' } else { 'Live Windows' }))
    Write-Host ""
    Write-Host "  1) SFC - scan and repair system files"
    Write-Host "  2) DISM - check image health"
    Write-Host "  3) DISM - restore image health"
    Write-Host "  4) chkdsk - read-only scan"
    Write-Host "  5) chkdsk - scan and fix (schedules on reboot for the system drive)"
    Write-Host "  Q) Quit"
    Write-Host ""
    $choice = (Read-Host "  Choose").Trim().ToUpper()

    switch ($choice) {
        '1' {
            if ($inWinPE) {
                $d = Read-WindowsDrive
                if ($d) { & sfc.exe /scannow /offbootdir=${d}:\ /offwindir=${d}:\Windows }
            } else {
                & sfc.exe /scannow
            }
        }
        '2' {
            if ($inWinPE) {
                $d = Read-WindowsDrive
                if ($d) { & dism.exe /Image:${d}:\ /Cleanup-Image /CheckHealth }
            } else {
                & dism.exe /Online /Cleanup-Image /CheckHealth
                & dism.exe /Online /Cleanup-Image /ScanHealth
            }
        }
        '3' {
            if ($inWinPE) {
                $d = Read-WindowsDrive
                if ($d) {
                    Write-Host "  For offline RestoreHealth you may need a known-good source (install.wim)." -ForegroundColor DarkGray
                    & dism.exe /Image:${d}:\ /Cleanup-Image /RestoreHealth
                }
            } else {
                & dism.exe /Online /Cleanup-Image /RestoreHealth
            }
        }
        '4' {
            $d = Read-Host "  Drive letter to scan (for example C)"
            $d = $d.Trim().TrimEnd(':')
            if ($d) { & chkdsk.exe "${d}:" }
        }
        '5' {
            $d = Read-Host "  Drive letter to scan and fix (for example C)"
            $d = $d.Trim().TrimEnd(':')
            if ($d) {
                Write-Host "  chkdsk /f may schedule on the next reboot if the drive is in use." -ForegroundColor Yellow
                & chkdsk.exe "${d}:" /f
            }
        }
        'Q' { return }
        default { Write-Host "  Unknown choice." -ForegroundColor Yellow }
    }

    Write-Host ""
    Read-Host "  Press Enter to return to the menu"
}
