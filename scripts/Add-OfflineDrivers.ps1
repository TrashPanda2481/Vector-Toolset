<#
.SYNOPSIS
    Vector Toolset - Offline Driver Injection
.DESCRIPTION
    Injects a folder of drivers into an offline Windows install using DISM.
    Point it at the target Windows drive (its root, which contains \Windows)
    and a folder of .inf drivers. Useful when a machine will not boot for
    lack of a storage or chipset driver.
.PARAMETER ToolsetRoot
    Path to the toolkit root (set automatically by the launcher).
.PARAMETER DriverSource
    Folder of drivers to inject. Defaults to the toolkit driver-db folder.
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$DriverSource
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  This tool needs Administrator. Relaunching..." -ForegroundColor Yellow
    $relArgs = "-ExecutionPolicy Bypass -NoProfile -NoExit -File `"$PSCommandPath`" -ToolsetRoot `"$ToolsetRoot`""
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $relArgs } catch { Write-Host "  Elevation cancelled." -ForegroundColor Red }
    return
}

Write-Host ""
Write-Host "=== Vector Toolset - Offline Driver Injection ===" -ForegroundColor Cyan
Write-Host ""

# Target Windows drive
$d = Read-Host "  Target Windows drive letter (the drive that holds \Windows, for example D)"
$d = $d.Trim().TrimEnd(':')
if ([string]::IsNullOrWhiteSpace($d) -or -not (Test-Path "${d}:\Windows")) {
    Write-Host "  No \Windows folder found on ${d}:. Aborting." -ForegroundColor Red
    Read-Host "  Press Enter to close"
    return
}

# Driver source
if ([string]::IsNullOrWhiteSpace($DriverSource)) {
    $default = Join-Path $ToolsetRoot 'driver-db'
    Write-Host ""
    Write-Host "  Driver folder to inject. Default: $default"
    $inp = Read-Host "  Driver folder (Enter for default)"
    $DriverSource = if ([string]::IsNullOrWhiteSpace($inp)) { $default } else { $inp.Trim() }
}

if (-not (Test-Path $DriverSource)) {
    Write-Host "  Driver folder not found: $DriverSource" -ForegroundColor Red
    Read-Host "  Press Enter to close"
    return
}

$infCount = @(Get-ChildItem -Path $DriverSource -Filter *.inf -Recurse -ErrorAction SilentlyContinue).Count
Write-Host ""
Write-Host "  Target : ${d}:\ (offline Windows)"
Write-Host "  Source : $DriverSource ($infCount .inf files found)"
Write-Host ""

$forceUnsigned = (Read-Host "  Allow unsigned drivers? (y/N)").Trim().ToUpper() -eq 'Y'
$confirm = (Read-Host "  Inject now? (y/N)").Trim().ToUpper()
if ($confirm -ne 'Y') { Write-Host "  Cancelled." -ForegroundColor Yellow; Read-Host "  Press Enter to close"; return }

Write-Host ""
Write-Host "  Running DISM Add-Driver..." -ForegroundColor Yellow
$dismArgs = @("/Image:${d}:\", "/Add-Driver", "/Driver:$DriverSource", "/Recurse")
if ($forceUnsigned) { $dismArgs += "/ForceUnsigned" }
& dism.exe @dismArgs

Write-Host ""
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Done. Drivers injected into ${d}:\Windows." -ForegroundColor Green
} else {
    Write-Host "  DISM returned exit code $LASTEXITCODE. Review the output above." -ForegroundColor Red
}
Write-Host ""
Read-Host "  Press Enter to close"
