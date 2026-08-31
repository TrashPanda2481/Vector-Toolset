<#
.SYNOPSIS
    Vector Toolset - build everything (part 1 of 2, NORMAL prompt)
.DESCRIPTION
    Runs the non-elevated half of the build pipeline in order:
      preflight -> build launcher -> fetch tools -> fetch payload -> build GRUB

    Run this from a NORMAL (non-elevated) prompt: the tool fetch uses Scoop, which
    refuses to run as Administrator. When it finishes, run the elevated half:
      build\Deploy-Stick.ps1 -DiskNumber <N>

.PARAMETER SkipTools
    Skip Get-Tools.ps1 (the tools are already in tools\).
.PARAMETER SkipPayload
    Skip Get-Payload.ps1 (the ISOs are already in build\payload\).
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
#>
param(
    [switch]$SkipTools,
    [switch]$SkipPayload,
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
function Step($n, $t) { Write-Host ""; Write-Host ("=== [{0}] {1} ===" -f $n, $t) -ForegroundColor Cyan }
function Fail($m) { Write-Host "  ERROR: $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=== Vector Toolset - Make-Stick (build, part 1 of 2) ===" -ForegroundColor Cyan

# Scoop refuses to run elevated, so this half must be a normal prompt.
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin -and -not $SkipTools) {
    Fail "Run this from a NORMAL (non-elevated) prompt - Scoop will not run as admin. (Or pass -SkipTools if the tools are already fetched.) The elevated half is Deploy-Stick.ps1."
}

Step 'preflight' 'Checking prerequisites'
$copype = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\copype.cmd"
$missing = @()
if (-not (Test-Path $copype)) { $missing += 'Windows ADK + the WinPE add-on (copype.cmd not found)' }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { $missing += 'WSL with an Ubuntu/Debian distro (GRUB is built there)' }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { $missing += 'the .NET SDK (dotnet on PATH)' }
$hasScoop = (Get-Command scoop -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE 'scoop\shims\scoop.ps1'))
if (-not $SkipTools -and -not $hasScoop) { $missing += 'Scoop for some tools (install: irm get.scoop.sh | iex)' }
if ($missing.Count -gt 0) {
    Write-Host "  Missing prerequisites:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    Fail "Install the above, then re-run. See docs\BUILD_PLAN.md."
}
Write-Host "  All prerequisites present." -ForegroundColor Green

Step 1 'Building the launcher (Release)'
& dotnet build (Join-Path $ToolsetRoot 'launcher\Vector.Launcher.csproj') -c Release --nologo -v q
if ($LASTEXITCODE -ne 0) { Fail 'launcher build failed' }
Write-Host "  Launcher built." -ForegroundColor Green

if ($SkipTools) { Step 2 'Fetching tools (skipped)' }
else { Step 2 'Fetching tools (Get-Tools.ps1)'; & (Join-Path $ToolsetRoot 'build\Get-Tools.ps1') -ToolsetRoot $ToolsetRoot }

if ($SkipPayload) { Step 3 'Fetching Linux payload (skipped)' }
else { Step 3 'Fetching Linux payload (Get-Payload.ps1)'; & (Join-Path $ToolsetRoot 'build\Get-Payload.ps1') -ToolsetRoot $ToolsetRoot }

Step 4 'Building GRUB (Build-Grub.ps1, via WSL)'
& (Join-Path $ToolsetRoot 'build\Build-Grub.ps1') -ToolsetRoot $ToolsetRoot
if ($LASTEXITCODE -ne 0) { Fail 'GRUB build failed' }

Write-Host ""
Write-Host "  Part 1 done: launcher, tools, payload, and GRUB are ready." -ForegroundColor Green
Write-Host "  Next, from an ELEVATED prompt, build WinPE and deploy:" -ForegroundColor Cyan
Write-Host "    build\Deploy-Stick.ps1                 (lists USB disks)" -ForegroundColor DarkGray
Write-Host "    build\Deploy-Stick.ps1 -DiskNumber <N> (builds WinPE, then wipes and writes that disk)" -ForegroundColor DarkGray
Write-Host ""
