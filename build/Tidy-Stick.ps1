<#
.SYNOPSIS
    Vector Toolset - tidy an already-deployed stick (no re-deploy)
.DESCRIPTION
    Applies the same declutter that Deploy-USB now does at the end, to a stick that
    was built before that change:
      - replaces a stale Launch.bat with a visible "Start Vector Toolset.bat"
      - hides the machinery on VECTORDATA (Hidden+System on launcher, config,
        branding, scripts, payload, .toolset-root) so Explorer shows only tools\
      - removes the VECTORPE (ESP) drive letter so the boot partition is hidden
        from Windows (this part needs an elevated prompt)

    VECTORDATA hiding works from a normal prompt; hiding the ESP needs elevation.
    Nothing here touches the boot files, so a tidied stick still boots the same.
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
#>
param([string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent))

function Warn($m) { Write-Host "  $m" -ForegroundColor Yellow }

Write-Host ""
Write-Host "=== Vector Toolset - tidy stick ===" -ForegroundColor Cyan

$data = (Get-Volume -FileSystemLabel VECTORDATA -ErrorAction SilentlyContinue).DriveLetter
if (-not $data) { Write-Host "  ERROR: VECTORDATA not found. Is the stick plugged in?" -ForegroundColor Red; exit 1 }
$dataRoot = "${data}:\"
Write-Host "  VECTORDATA at ${data}:" -ForegroundColor DarkGray

# 1. Friendly, visible launcher entry (drop any stale Launch.bat).
if (Test-Path (Join-Path $dataRoot 'Launch.bat')) { Remove-Item (Join-Path $dataRoot 'Launch.bat') -Force }
Copy-Item (Join-Path $ToolsetRoot 'Launch.bat') (Join-Path $dataRoot 'Start Vector Toolset.bat') -Force
Write-Host "  Wrote 'Start Vector Toolset.bat'." -ForegroundColor DarkGray

# 2. Hide the machinery; leave tools\ visible.
foreach ($h in 'launcher','config','branding','scripts','payload','.toolset-root') {
    $hp = Join-Path $dataRoot $h
    if (Test-Path $hp) {
        $it = Get-Item $hp -Force
        $it.Attributes = $it.Attributes -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    }
}
Write-Host "  Hid launcher/config/branding/scripts/payload/.toolset-root." -ForegroundColor DarkGray

# 3. Hide the ESP by removing its drive letter (needs admin).
$diskNum = (Get-Partition -DriveLetter $data).DiskNumber
$esp = Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue |
    Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
if ($esp -and $esp.DriveLetter) {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($admin) {
        Remove-PartitionAccessPath -DiskNumber $diskNum -PartitionNumber $esp.PartitionNumber -AccessPath "$($esp.DriveLetter):\" -ErrorAction SilentlyContinue
        Write-Host "  Removed the ESP drive letter ($($esp.DriveLetter):)." -ForegroundColor DarkGray
    } else {
        Warn "The boot partition is mounted at $($esp.DriveLetter): - re-run elevated to hide it."
    }
} else {
    Write-Host "  Boot partition already has no drive letter (hidden)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Done. Explorer now shows a clean tools\ folder + the launcher on ${data}:." -ForegroundColor Green
Write-Host ""
