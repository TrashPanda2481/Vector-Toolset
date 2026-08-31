<#
.SYNOPSIS
    Vector Toolset - WinPE image builder
.DESCRIPTION
    Builds the Vector WinPE boot image. Steps: copype creates a work area,
    mount boot.wim, add the optional components the launcher needs (.NET,
    PowerShell, WMI, scripting, storage), inject any drivers, bake the Vector
    core (launcher + built-in scripts + config) into the image, set the
    launcher as the WinPE shell, then commit and unmount. Optionally build a
    bootable test ISO.

    Run from an ELEVATED prompt - DISM image mounting requires Administrator.
    Requires the Windows ADK plus the WinPE add-on (Deployment Tools and
    Windows Preinstallation Environment features).
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
.PARAMETER WorkDir
    Working directory for the build. Defaults to build\winpe-work under root.
.PARAMETER Iso
    Also build a bootable test ISO (build\Vector-WinPE.iso).
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$WorkDir,
    [switch]$Iso
)

$ErrorActionPreference = 'Stop'
function Fail($msg) { Write-Host "  ERROR: $msg" -ForegroundColor Red; exit 1 }

# Administrator is required for DISM mount/unmount.
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail "Run this from an elevated prompt (Administrator)." }

# Locate the ADK.
$adkRoot   = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
$winpeRoot = Join-Path $adkRoot 'Windows Preinstallation Environment'
$dtRoot    = Join-Path $adkRoot 'Deployment Tools'
$dandiEnv  = Join-Path $dtRoot 'DandISetEnv.bat'
$ocs       = Join-Path $winpeRoot 'amd64\WinPE_OCs'
$copype    = Join-Path $winpeRoot 'copype.cmd'
foreach ($p in @($copype, $ocs, $dandiEnv)) {
    if (-not (Test-Path $p)) { Fail "ADK component missing: $p. Install the ADK plus the WinPE add-on." }
}

if (-not $WorkDir) { $WorkDir = Join-Path $ToolsetRoot 'build\winpe-work' }
$mount   = Join-Path $WorkDir 'mount'
$bootWim = Join-Path $WorkDir 'media\sources\boot.wim'

Write-Host ""
Write-Host "=== Vector Toolset - WinPE builder ===" -ForegroundColor Cyan
Write-Host "  Work dir: $WorkDir"
Write-Host ""

# Clean any previous run (discard a stale mount first).
if (Test-Path $mount) {
    Write-Host "  Cleaning a previous mount..."
    & dism.exe /Unmount-Image /MountDir:"$mount" /Discard 2>$null | Out-Null
}
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }

# 1. copype (runs inside the Deployment and Imaging Tools environment).
Write-Host "  [1/7] copype amd64" -ForegroundColor Yellow
cmd /c "`"$dandiEnv`" && copype amd64 `"$WorkDir`"" | Out-Null
if (-not (Test-Path $bootWim)) { Fail "copype did not produce boot.wim" }

# 2. Mount boot.wim.
Write-Host "  [2/7] Mounting boot.wim" -ForegroundColor Yellow
if (-not (Test-Path $mount)) { New-Item -ItemType Directory -Force -Path $mount | Out-Null }
& dism.exe /Mount-Image /ImageFile:"$bootWim" /Index:1 /MountDir:"$mount"
if ($LASTEXITCODE -ne 0) { Fail "mount failed (exit $LASTEXITCODE)" }

# 3. Optional components. Order matters: WMI, then NetFX, then the rest.
Write-Host "  [3/7] Adding optional components" -ForegroundColor Yellow
$components = @(
    'WinPE-WMI','WinPE-NetFX','WinPE-Scripting','WinPE-PowerShell',
    'WinPE-StorageWMI','WinPE-DismCmdlets','WinPE-SecureStartup','WinPE-EnhancedStorage','WinPE-FMAPI'
)
foreach ($c in $components) {
    $base = Join-Path $ocs "$c.cab"
    $lang = Join-Path $ocs "en-us\${c}_en-us.cab"
    if (-not (Test-Path $base)) { Write-Host "    skip $c (not present)" -ForegroundColor DarkGray; continue }
    Write-Host "    + $c"
    & dism.exe /Image:"$mount" /Add-Package /PackagePath:"$base" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "adding $c failed" }
    if (Test-Path $lang) { & dism.exe /Image:"$mount" /Add-Package /PackagePath:"$lang" | Out-Null }
}

# 4. Drivers (optional): drop .inf driver folders into build\drivers.
$drivers = Join-Path $ToolsetRoot 'build\drivers'
if ((Test-Path $drivers) -and @(Get-ChildItem $drivers -Filter *.inf -Recurse -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host "  [4/7] Injecting drivers from build\drivers" -ForegroundColor Yellow
    & dism.exe /Image:"$mount" /Add-Driver /Driver:"$drivers" /Recurse | Out-Null
} else {
    Write-Host "  [4/7] No drivers to inject" -ForegroundColor DarkGray
}

# 5. Bake the Vector core into the image at X:\Vector.
Write-Host "  [5/7] Baking the Vector core" -ForegroundColor Yellow
$relOut = Join-Path $ToolsetRoot 'launcher\bin\Release\net48'
if (-not (Test-Path (Join-Path $relOut 'Vector.Launcher.exe'))) {
    Fail "Launcher not built. Run: dotnet build launcher\Vector.Launcher.csproj -c Release"
}
$dest = Join-Path $mount 'Vector'
$destLauncher = Join-Path $dest 'launcher'
New-Item -ItemType Directory -Force -Path $destLauncher | Out-Null
Copy-Item (Join-Path $relOut '*') $destLauncher -Recurse -Force
foreach ($d in 'scripts','config','branding') {
    $src = Join-Path $ToolsetRoot $d
    if (Test-Path $src) { Copy-Item $src $dest -Recurse -Force }
}
Copy-Item (Join-Path $ToolsetRoot '.toolset-root') $dest -Force -ErrorAction SilentlyContinue

# 6. Set the launcher as the WinPE shell. wpeinit first (PnP and network),
#    then the launcher. When the launcher exits, WinPE restarts.
Write-Host "  [6/7] Setting the launcher as the WinPE shell" -ForegroundColor Yellow
$winpeshl = "[LaunchApps]`r`n" +
            "`"%SYSTEMROOT%\System32\wpeinit.exe`"`r`n" +
            "`"%SYSTEMDRIVE%\Vector\launcher\Vector.Launcher.exe`"`r`n"
[System.IO.File]::WriteAllText((Join-Path $mount 'Windows\System32\winpeshl.ini'), $winpeshl)

# Give the RAM disk room for the launcher and running tools.
& dism.exe /Image:"$mount" /Set-ScratchSpace:512 | Out-Null

# 7. Commit and unmount.
Write-Host "  [7/7] Committing and unmounting" -ForegroundColor Yellow
& dism.exe /Unmount-Image /MountDir:"$mount" /Commit
if ($LASTEXITCODE -ne 0) { Fail "unmount/commit failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "  WinPE image ready: $bootWim" -ForegroundColor Green

# Optional bootable test ISO via the ADK helper.
if ($Iso) {
    Write-Host "  Building test ISO" -ForegroundColor Yellow
    $isoPath = Join-Path $ToolsetRoot 'build\Vector-WinPE.iso'
    if (Test-Path $isoPath) { Remove-Item $isoPath -Force }
    cmd /c "`"$dandiEnv`" && MakeWinPEMedia /ISO `"$WorkDir`" `"$isoPath`"" | Out-Null
    if (Test-Path $isoPath) { Write-Host "  Test ISO: $isoPath" -ForegroundColor Green } else { Write-Host "  ISO build did not produce a file" -ForegroundColor Red }
}

Write-Host ""
Write-Host "  Done. Next: the GRUB2 boot layer, then Deploy-USB." -ForegroundColor Cyan
