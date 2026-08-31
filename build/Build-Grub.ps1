<#
.SYNOPSIS
    Vector Toolset - build the standalone GRUB EFI
.DESCRIPTION
    Produces boot\grub\grubx64.efi (a self-contained UEFI GRUB with the needed
    modules and an embedded config baked in) plus boot\grub\fonts\unicode.pf2.
    Deploy-USB.ps1 copies these onto the stick as EFI\BOOT\BOOTX64.EFI, the menu,
    the theme, and the font.

    GRUB's build tools are Linux tools, so this uses WSL (an Ubuntu or Debian
    distro must be installed). The embedded config (boot\grub\embedded.cfg) runs
    first, finds the VECTORPE partition by label, then loads the real menu
    (boot\grub.cfg).
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
#>
param([string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent))

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) { Write-Host "  ERROR: WSL not found. Install WSL with an Ubuntu/Debian distro." -ForegroundColor Red; exit 1 }

# Translate the Windows repo path to a WSL /mnt path.
$drive   = ($ToolsetRoot.Substring(0,1)).ToLower()
$rest    = $ToolsetRoot.Substring(2) -replace '\\','/'
$wslRoot = "/mnt/$drive$rest"

# Modules for the UEFI build. ntldr is BIOS-only and is intentionally left out;
# UEFI boots WinPE with chainloader instead.
$modules = 'part_gpt part_msdos fat ntfs exfat iso9660 loopback chain search search_label configfile normal linux echo test all_video video gfxterm gfxmenu png font halt reboot terminal gettext'

$cmd = "set -e; " +
    "apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq grub-efi-amd64-bin grub-common >/dev/null; " +
    "mkdir -p '$wslRoot/boot/grub/fonts'; " +
    "grub-mkstandalone -O x86_64-efi -o '$wslRoot/boot/grub/grubx64.efi' --modules='$modules' 'boot/grub/grub.cfg=$wslRoot/boot/grub/embedded.cfg'; " +
    "cp /usr/share/grub/unicode.pf2 '$wslRoot/boot/grub/fonts/unicode.pf2'; " +
    "echo BUILD_DONE"

Write-Host ""
Write-Host "  Building grubx64.efi via WSL (installs grub tools as root)..." -ForegroundColor Yellow
& wsl.exe -u root -- bash -c $cmd
if ($LASTEXITCODE -ne 0) { Write-Host "  GRUB build failed." -ForegroundColor Red; exit 1 }

$efi  = Join-Path $ToolsetRoot 'boot\grub\grubx64.efi'
$font = Join-Path $ToolsetRoot 'boot\grub\fonts\unicode.pf2'
Write-Host ""
Write-Host ("  grubx64.efi: " + $(if (Test-Path $efi)  { [math]::Round((Get-Item $efi).Length/1MB,1).ToString()  + ' MB' } else { 'MISSING' })) -ForegroundColor Green
Write-Host ("  unicode.pf2: " + $(if (Test-Path $font) { [math]::Round((Get-Item $font).Length/1MB,1).ToString() + ' MB' } else { 'MISSING' })) -ForegroundColor Green
Write-Host "  Deploy-USB will install these as the bootloader." -ForegroundColor Cyan
