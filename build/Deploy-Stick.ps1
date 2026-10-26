<#
.SYNOPSIS
    Vector Toolset - build WinPE and deploy (part 2 of 2, ELEVATED prompt)
.DESCRIPTION
    Runs the elevated half of the pipeline: bakes the WinPE image with the current
    launcher, then partitions and writes the USB stick. Run part 1 first:
      build\Make-Stick.ps1   (normal prompt: launcher, tools, payload, GRUB)

    Run this from an ELEVATED prompt - DISM image mounting and disk partitioning
    both require Administrator.

    With no -DiskNumber it lists the disks and stops, so you can pick the USB.
.PARAMETER DiskNumber
    Target USB disk number (from the list). Omit to just list disks.
.PARAMETER PayloadSource
    Folder of Linux ISOs to copy. Defaults to build\payload. Only used with
    -WithLinuxBoot.
.PARAMETER WithLinuxBoot
    Build a GRUB multiboot stick (Memtest, Clonezilla, ShredOS, etc.) instead of
    the default WinPE-direct stick. The GRUB stick needs Secure Boot OFF to boot
    and needs part 1 to have been run with -WithLinuxBoot (GRUB + payload built).
.PARAMETER SkipWinPE
    Skip the WinPE rebake (boot.wim is already current). Faster for a data-only
    redeploy; leave it off after any launcher change.
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
#>
param(
    [int]$DiskNumber = -1,
    [string]$PayloadSource,
    [switch]$WithLinuxBoot,
    [switch]$SkipWinPE,
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
function Step($n, $t) { Write-Host ""; Write-Host ("=== [{0}] {1} ===" -f $n, $t) -ForegroundColor Cyan }
function Fail($m) { Write-Host "  ERROR: $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=== Vector Toolset - Deploy-Stick (deploy, part 2 of 2) ===" -ForegroundColor Cyan

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail "Run this from an ELEVATED prompt (Administrator). Part 1 (Make-Stick.ps1) runs from a normal prompt." }

if (-not $PayloadSource) { $PayloadSource = Join-Path $ToolsetRoot 'build\payload' }

# The launcher must be built (Make-Stick does this). Fail early with a clear hint.
if (-not (Test-Path (Join-Path $ToolsetRoot 'launcher\bin\Release\net48\Vector.Launcher.exe'))) {
    Fail "Launcher not built. Run part 1 first: build\Make-Stick.ps1"
}

if ($SkipWinPE) {
    Step 1 'Building the WinPE image (skipped)'
} else {
    Step 1 'Building the WinPE image (Build-WinPE.ps1)'
    & (Join-Path $ToolsetRoot 'build\Build-WinPE.ps1') -ToolsetRoot $ToolsetRoot
    if ($LASTEXITCODE -ne 0) { Fail 'WinPE build failed' }
}

Step 2 'Deploying to the USB (Deploy-USB.ps1)'
& (Join-Path $ToolsetRoot 'build\Deploy-USB.ps1') -DiskNumber $DiskNumber -PayloadSource $PayloadSource -WithLinuxBoot:$WithLinuxBoot -ToolsetRoot $ToolsetRoot

if ($DiskNumber -lt 0) {
    Write-Host ""
    Write-Host "  Pick the USB disk number above, then re-run:" -ForegroundColor Cyan
    Write-Host "    build\Deploy-Stick.ps1 -DiskNumber <N>" -ForegroundColor DarkGray
    Write-Host ""
}
