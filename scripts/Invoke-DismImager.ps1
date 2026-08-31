<#
.SYNOPSIS
    Vector Toolset - DISM Imager
.DESCRIPTION
    Captures a Windows volume to a .wim image, or applies a .wim image to an
    already prepared volume and makes it bootable with bcdboot. This is a
    file-level imager, not a block-level cloner. For full-disk cloning use
    the Clonezilla boot entry.

    Apply expects the target disk to be partitioned and formatted already
    (with diskpart or MiniTool Partition Wizard). It does not repartition on
    its own, by design, so it can never wipe the wrong disk.
.PARAMETER ToolsetRoot
    Path to the toolkit root (set automatically by the launcher).
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent)
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  This tool needs Administrator. Relaunching..." -ForegroundColor Yellow
    $relArgs = "-ExecutionPolicy Bypass -NoProfile -NoExit -File `"$PSCommandPath`" -ToolsetRoot `"$ToolsetRoot`""
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $relArgs } catch { Write-Host "  Elevation cancelled." -ForegroundColor Red }
    return
}

function Get-DriveLetter([string]$prompt) {
    $d = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($d)) { return $null }
    return $d.Trim().TrimEnd(':')
}

function Invoke-Capture {
    Write-Host ""
    Write-Host "  --- Capture image ---" -ForegroundColor Cyan
    $src = Get-DriveLetter "  Source volume to capture (for example C)"
    if (-not $src -or -not (Test-Path "${src}:\")) { Write-Host "  Invalid source." -ForegroundColor Red; return }

    $name = Read-Host "  Image name (label, for example 'Dell 5090 clean')"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Vector capture" }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $imagesDir = Join-Path $ToolsetRoot 'images'
    try {
        if (-not (Test-Path $imagesDir)) { New-Item -ItemType Directory -Path $imagesDir -Force -ErrorAction Stop | Out-Null }
    } catch {
        $imagesDir = $env:TEMP
    }
    $default = Join-Path $imagesDir ("Capture-" + $stamp + ".wim")
    Write-Host "  Output image. Default: $default"
    $out = Read-Host "  Output .wim path (Enter for default)"
    if ([string]::IsNullOrWhiteSpace($out)) { $out = $default }

    Write-Host ""
    Write-Host "  Capturing ${src}:\ to $out" -ForegroundColor Yellow
    Write-Host "  This reads the whole volume and can take a while." -ForegroundColor DarkGray
    & dism.exe /Capture-Image /ImageFile:"$out" /CaptureDir:"${src}:\" /Name:"$name" /Compress:max
    Write-Host ""
    if ($LASTEXITCODE -eq 0) { Write-Host "  Capture complete: $out" -ForegroundColor Green }
    else { Write-Host "  DISM returned exit code $LASTEXITCODE." -ForegroundColor Red }
}

function Invoke-Apply {
    Write-Host ""
    Write-Host "  --- Apply image ---" -ForegroundColor Cyan
    Write-Host "  WARNING: applying overwrites the contents of the target volume." -ForegroundColor Yellow
    Write-Host "  The target disk must already be partitioned and formatted." -ForegroundColor Yellow
    Write-Host ""

    $wim = Read-Host "  Path to the .wim image"
    if ([string]::IsNullOrWhiteSpace($wim) -or -not (Test-Path $wim)) { Write-Host "  Image not found." -ForegroundColor Red; return }

    Write-Host ""
    Write-Host "  Image contents:" -ForegroundColor DarkGray
    & dism.exe /Get-ImageInfo /ImageFile:"$wim"
    $index = Read-Host "  Image index to apply (usually 1)"
    if ([string]::IsNullOrWhiteSpace($index)) { $index = "1" }

    $target = Get-DriveLetter "  Target volume to apply into (for example W)"
    if (-not $target -or -not (Test-Path "${target}:\")) { Write-Host "  Invalid target." -ForegroundColor Red; return }

    # Never let a live Windows session apply an image over its own system drive.
    $inWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
    $sysDrive = ($env:SystemDrive).TrimEnd(':')
    if (-not $inWinPE -and $target.ToUpper() -eq $sysDrive.ToUpper()) {
        Write-Host "  REFUSING: ${target}: is the running Windows system drive." -ForegroundColor Red
        Write-Host "  Boot the stick into WinPE to reimage the system drive." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  About to overwrite everything on ${target}:\ with image index $index." -ForegroundColor Red
    $confirm = Read-Host "  Type the target letter ($target) to confirm"
    if ($confirm.Trim().TrimEnd(':').ToUpper() -ne $target.ToUpper()) {
        Write-Host "  Confirmation did not match. Aborting." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Applying image..." -ForegroundColor Yellow
    & dism.exe /Apply-Image /ImageFile:"$wim" /Index:$index /ApplyDir:"${target}:\"
    if ($LASTEXITCODE -ne 0) { Write-Host "  Apply failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }
    Write-Host "  Image applied." -ForegroundColor Green

    Write-Host ""
    $makeBoot = (Read-Host "  Make the target bootable with bcdboot? (Y/n)").Trim().ToUpper()
    if ($makeBoot -eq 'N') { return }

    if (-not (Test-Path "${target}:\Windows")) {
        Write-Host "  No \Windows on ${target}:. Skipping bcdboot." -ForegroundColor Yellow
        return
    }
    $sys = Get-DriveLetter "  Boot/system partition letter (the small EFI or system volume)"
    if (-not $sys) { Write-Host "  Skipped bcdboot." -ForegroundColor Yellow; return }

    Write-Host "  Writing boot files..." -ForegroundColor Yellow
    & bcdboot.exe "${target}:\Windows" /s "${sys}:" /f ALL
    if ($LASTEXITCODE -eq 0) { Write-Host "  Boot files written. Target should now boot." -ForegroundColor Green }
    else { Write-Host "  bcdboot returned exit code $LASTEXITCODE." -ForegroundColor Red }
}

while ($true) {
    Write-Host ""
    Write-Host "=== Vector Toolset - DISM Imager ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Capture a volume to a .wim image"
    Write-Host "  2) Apply a .wim image to a prepared volume"
    Write-Host "  Q) Quit"
    Write-Host ""
    $choice = (Read-Host "  Choose").Trim().ToUpper()
    switch ($choice) {
        '1' { Invoke-Capture }
        '2' { Invoke-Apply }
        'Q' { return }
        default { Write-Host "  Unknown choice." -ForegroundColor Yellow }
    }
    Write-Host ""
    Read-Host "  Press Enter to return to the menu"
}
