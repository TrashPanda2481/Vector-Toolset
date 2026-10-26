<#
.SYNOPSIS
    Vector Toolset - deploy to a USB stick
.DESCRIPTION
    Partitions a USB stick and lays down the whole toolkit:
      - VECTORPE   (FAT32, EFI System Partition): the WinPE media. With
                    -WithLinuxBoot it also holds GRUB and the GRUB menu.
      - VECTORDATA (exFAT): the tools, config, scripts, and launcher (plus the
                    Linux payload ISOs under -WithLinuxBoot). Every OS mounts this.

    By default the stick boots straight into WinPE via the Microsoft-signed
    Windows Boot Manager, so Secure Boot can stay ON. Pass -WithLinuxBoot to make
    GRUB the bootloader with the full multiboot menu (Memtest, Clonezilla, ShredOS,
    etc.); GRUB is not Microsoft-signed, so that stick needs Secure Boot OFF.

    THIS WIPES THE TARGET DISK. It is written to be hard to point at the wrong
    one: it needs an explicit -DiskNumber, refuses a non-USB disk unless you pass
    -Force, and requires you to type the disk number to confirm.

    Run from an ELEVATED prompt. Requires a WinPE media build first:
    build\Build-WinPE.ps1 (produces build\winpe-work\media). -WithLinuxBoot also
    needs GRUB built (build\Build-Grub.ps1) and payload ISOs (build\Get-Payload.ps1).
.PARAMETER DiskNumber
    The target disk number (from Get-Disk). Required. Run with no arguments to
    list disks first.
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
.PARAMETER PayloadSource
    Optional folder of Linux boot ISOs to copy into VECTORDATA\payload. Only used
    with -WithLinuxBoot.
.PARAMETER WithLinuxBoot
    Install GRUB as the bootloader and lay down the Linux payload ISOs, giving the
    full multiboot menu. Requires Secure Boot OFF on the target. Without this, the
    stick boots straight into WinPE and Secure Boot can stay on.
.PARAMETER Force
    Allow a target whose BusType is not USB. Use with great care.
#>
param(
    [int]$DiskNumber = -1,
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$PayloadSource,
    [switch]$WithLinuxBoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
function Fail($m) { Write-Host "  ERROR: $m" -ForegroundColor Red; exit 1 }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail "Run from an elevated prompt (Administrator)." }

$media = Join-Path $ToolsetRoot 'build\winpe-work\media'
if (-not (Test-Path (Join-Path $media 'sources\boot.wim'))) {
    Fail "WinPE media not found at $media. Build it first: build\Build-WinPE.ps1"
}
$relOut = Join-Path $ToolsetRoot 'launcher\bin\Release\net48'
if (-not (Test-Path (Join-Path $relOut 'Vector.Launcher.exe'))) {
    Fail "Launcher not built. Run: dotnet build launcher\Vector.Launcher.csproj -c Release"
}

Write-Host ""
Write-Host "=== Vector Toolset - Deploy to USB ===" -ForegroundColor Cyan
Write-Host ""

# With no disk number, list disks and stop so the operator can choose.
if ($DiskNumber -lt 0) {
    Write-Host "  Disks (pick the USB stick's Number, then re-run with -DiskNumber N):" -ForegroundColor Yellow
    Get-Disk | Sort-Object Number | Format-Table Number, FriendlyName,
        @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, BusType, @{n='System';e={$_.IsBoot -or $_.IsSystem}} -AutoSize | Out-String | Write-Host
    Write-Host "  Example: build\Deploy-USB.ps1 -DiskNumber 3" -ForegroundColor DarkGray
    exit 0
}

# Validate the target.
$disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disk) { Fail "No disk with Number $DiskNumber." }
if ($disk.IsBoot -or $disk.IsSystem) { Fail "Disk $DiskNumber is the boot/system disk. Refusing." }
if ($disk.BusType -ne 'USB' -and -not $Force) {
    Fail "Disk $DiskNumber BusType is '$($disk.BusType)', not USB. If you are certain, re-run with -Force."
}

$sizeGB = [math]::Round($disk.Size/1GB,1)
Write-Host "  TARGET: Disk $DiskNumber  -  $($disk.FriendlyName)  -  $sizeGB GB  -  $($disk.BusType)" -ForegroundColor Yellow
Write-Host "  EVERYTHING ON THIS DISK WILL BE ERASED." -ForegroundColor Red
Write-Host ""
$confirm = Read-Host "  Type the disk number ($DiskNumber) to confirm the wipe"
if ($confirm.Trim() -ne "$DiskNumber") { Write-Host "  Cancelled." -ForegroundColor Yellow; exit 0 }

# Sizes.
$peSizeGB = 4

Write-Host ""
Write-Host "  [1/7] Wiping and initializing GPT..." -ForegroundColor Yellow
if ((Get-Disk -Number $DiskNumber).IsReadOnly) { Set-Disk -Number $DiskNumber -IsReadOnly $false }
# Wipe with diskpart 'clean'. Right after, the disk is briefly RAW, but Windows
# auto-initializes a removable disk to MBR within a second or two - so the style
# we then observe is a race. diskpart 'convert gpt' needs MBR, Initialize-Disk
# needs RAW, and Set-Disk cannot convert MBR->GPT - so loop and dispatch on
# whatever style is actually present until the disk is GPT:
#   RAW -> Initialize-Disk GPT ; MBR -> diskpart convert gpt ; GPT -> done.
$dpClean = Join-Path $env:TEMP 'vector-deploy-clean.txt'
"select disk $DiskNumber`r`nclean`r`nexit" | Set-Content -Path $dpClean -Encoding ASCII
& diskpart /s $dpClean | Out-Null
Remove-Item $dpClean -Force -ErrorAction SilentlyContinue

for ($i = 0; $i -lt 6; $i++) {
    $disk = Get-Disk -Number $DiskNumber
    if ($disk.PartitionStyle -eq 'GPT') { break }
    if ($disk.IsReadOnly) { Set-Disk -Number $DiskNumber -IsReadOnly $false }
    if ($disk.PartitionStyle -eq 'RAW') {
        Initialize-Disk -Number $DiskNumber -PartitionStyle GPT -ErrorAction SilentlyContinue | Out-Null
    }
    elseif ($disk.PartitionStyle -eq 'MBR') {
        $dpCvt = Join-Path $env:TEMP 'vector-deploy-cvt.txt'
        "select disk $DiskNumber`r`nconvert gpt`r`nexit" | Set-Content -Path $dpCvt -Encoding ASCII
        & diskpart /s $dpCvt | Out-Null
        Remove-Item $dpCvt -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
}
$style = (Get-Disk -Number $DiskNumber).PartitionStyle
if ($style -ne 'GPT') { Fail "Disk $DiskNumber is '$style' after wipe; could not convert to GPT." }

function New-VectorPartition {
    param([int]$Disk, [UInt64]$Size, [string]$GptType, [string]$Fs, [string]$Label)
    if ($Size -gt 0) { $p = New-Partition -DiskNumber $Disk -Size $Size -GptType $GptType }
    else { $p = New-Partition -DiskNumber $Disk -UseMaximumSize }
    $p | Add-PartitionAccessPath -AssignDriveLetter | Out-Null
    # Wait for the drive letter (it is not assigned synchronously).
    $letter = $null
    for ($i = 0; $i -lt 25 -and -not $letter; $i++) {
        Start-Sleep -Milliseconds 300
        $letter = (Get-Partition -DiskNumber $Disk -PartitionNumber $p.PartitionNumber).DriveLetter
    }
    if (-not $letter) { Fail "Could not assign a drive letter to the new $Label partition." }
    Format-Volume -DriveLetter $letter -FileSystem $Fs -NewFileSystemLabel $Label -Force -Confirm:$false | Out-Null
    return $letter
}

Write-Host "  [2/7] Creating partitions..." -ForegroundColor Yellow
# VECTORPE: EFI System Partition (FAT32), holds GRUB and the WinPE media.
$peType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$pe   = New-VectorPartition -Disk $DiskNumber -Size ($peSizeGB * 1GB) -GptType $peType -Fs FAT32 -Label VECTORPE
# VECTORDATA: exFAT, the rest.
$data = New-VectorPartition -Disk $DiskNumber -Size 0 -GptType '' -Fs exFAT -Label VECTORDATA

Write-Host "    VECTORPE = ${pe}:   VECTORDATA = ${data}:" -ForegroundColor DarkGray

Write-Host "  [3/7] Copying WinPE media to VECTORPE..." -ForegroundColor Yellow
Copy-Item (Join-Path $media '*') "${pe}:\" -Recurse -Force

Write-Host "  [4/7] Installing the bootloader..." -ForegroundColor Yellow
$efiBoot = "${pe}:\EFI\BOOT"
New-Item -ItemType Directory -Force -Path $efiBoot | Out-Null
if ($WithLinuxBoot) {
    # GRUB multiboot: GRUB is the EFI bootloader and chainloads WinPE. GRUB is not
    # Microsoft-signed, so the target machine needs Secure Boot OFF.
    $grubEfi = Get-ChildItem (Join-Path $ToolsetRoot 'boot\grub') -Filter '*x64.efi' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $grubEfi) { Fail "GRUB binaries not found in boot\grub. Build them first (build\Build-Grub.ps1, or build\Make-Stick.ps1 -WithLinuxBoot), or deploy without -WithLinuxBoot for a WinPE-direct stick." }
    Copy-Item $grubEfi.FullName (Join-Path $efiBoot 'BOOTX64.EFI') -Force
    # GRUB config, theme, and fonts under the prefix (EFI\BOOT).
    Copy-Item (Join-Path $ToolsetRoot 'boot\grub.cfg') $efiBoot -Force
    if (Test-Path (Join-Path $ToolsetRoot 'boot\theme')) { Copy-Item (Join-Path $ToolsetRoot 'boot\theme') $efiBoot -Recurse -Force }
    $fontsSrc = Join-Path $ToolsetRoot 'boot\grub\fonts'
    if (Test-Path $fontsSrc) { Copy-Item $fontsSrc $efiBoot -Recurse -Force }
    Write-Host "    GRUB installed (multiboot menu). Target needs Secure Boot OFF." -ForegroundColor DarkGray
} else {
    # WinPE-direct (default): copy WinPE's own Microsoft-signed boot manager to the
    # firmware fallback path, so the stick boots straight into WinPE and Secure Boot
    # can stay ON.
    $winpeBootmgr = "${pe}:\EFI\Microsoft\Boot\bootmgfw.efi"
    if (-not (Test-Path $winpeBootmgr)) { Fail "WinPE boot manager not found at $winpeBootmgr - the WinPE media copy may have failed." }
    Copy-Item $winpeBootmgr (Join-Path $efiBoot 'BOOTX64.EFI') -Force
    Write-Host "    WinPE-direct boot (Microsoft-signed). Secure Boot can stay ON." -ForegroundColor DarkGray
}

Write-Host "  [5/7] Populating VECTORDATA (tools, config, scripts, launcher)..." -ForegroundColor Yellow
# Launcher for the plugged-into-live-Windows mode.
$destLauncher = "${data}:\launcher"
New-Item -ItemType Directory -Force -Path $destLauncher | Out-Null
Copy-Item (Join-Path $relOut '*') $destLauncher -Recurse -Force
foreach ($d in 'tools','config','scripts','branding') {
    $src = Join-Path $ToolsetRoot $d
    if (Test-Path $src) { Copy-Item $src "${data}:\" -Recurse -Force }
}
# The root marker (kept, hidden later) and a friendly, visible launcher entry.
Copy-Item (Join-Path $ToolsetRoot '.toolset-root') "${data}:\" -Force
Copy-Item (Join-Path $ToolsetRoot 'Launch.bat') "${data}:\Start Vector Toolset.bat" -Force

Write-Host "  [6/7] Copying payload ISOs..." -ForegroundColor Yellow
if ($WithLinuxBoot) {
    $payloadDest = "${data}:\payload"
    New-Item -ItemType Directory -Force -Path $payloadDest | Out-Null
    if ($PayloadSource -and (Test-Path $PayloadSource)) {
        # Copy the ISOs and the Memtest86+ hybrid binaries (memtest.efi/.bin), which
        # the GRUB menu references directly from payload\ and are not .iso files.
        $items = Get-ChildItem $PayloadSource -File | Where-Object { $_.Extension -in '.iso', '.efi', '.bin' }
        foreach ($it in $items) { Copy-Item $it.FullName $payloadDest -Force }
        Write-Host ("    Copied {0} payload files from {1}" -f $items.Count, $PayloadSource) -ForegroundColor DarkGray
    } else {
        Write-Host "    No PayloadSource given - drop Clonezilla/GParted/etc. ISOs into ${data}:\payload later." -ForegroundColor DarkGray
    }
} else {
    Write-Host "    Skipped - WinPE-direct build has no Linux boot menu (use -WithLinuxBoot to include it)." -ForegroundColor DarkGray
}

Write-Host "  [7/7] Tidying up (hiding system folders, unmounting boot partition)..." -ForegroundColor Yellow
# Hide the machinery on VECTORDATA so Explorer shows only the tools folder and the
# launcher entry. Hidden+System items do not appear with default Explorer settings,
# yet the launcher still reads them and GRUB still reads the payload (Windows
# attributes do not affect either).
foreach ($h in 'launcher','config','branding','scripts','payload','.toolset-root') {
    $hp = Join-Path "${data}:\" $h
    if (Test-Path $hp) {
        $it = Get-Item $hp -Force
        $it.Attributes = $it.Attributes -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    }
}
# Hide the boot partition from Windows: an ESP with no drive letter does not show
# in Explorer and cannot be casually written to. The firmware and GRUB reach it by
# the VECTORPE label, not a Windows drive letter.
$pePart = Get-Partition -DriveLetter $pe -ErrorAction SilentlyContinue
if ($pePart) {
    Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $pePart.PartitionNumber -AccessPath "${pe}:\" -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  Done. Stick ready:" -ForegroundColor Green
Write-Host "    VECTORPE   (hidden ESP)  - WinPE media and bootloader"
Write-Host "    VECTORDATA (${data}:) - visible tools\ + 'Start Vector Toolset.bat'; system files hidden"
Write-Host ""
if ($WithLinuxBoot) {
    Write-Host "  Boot it (UEFI, Secure Boot OFF - GRUB is unsigned) to test. Safely eject when done." -ForegroundColor Cyan
} else {
    Write-Host "  Boot it (UEFI; Secure Boot can stay ON) to test. Safely eject when done." -ForegroundColor Cyan
}
