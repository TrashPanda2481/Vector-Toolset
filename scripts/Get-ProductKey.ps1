<#
.SYNOPSIS
    Vector Toolset - Windows Product Key Finder
.DESCRIPTION
    Extracts the Windows product key from the current machine's registry
    or from a mounted offline Windows hive.
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$HivePath
)

function Decode-ProductKey {
    param([byte[]]$DigitalProductId)

    if (-not $DigitalProductId -or $DigitalProductId.Length -lt 67) { return $null }
    $keyOffset = 52
    $isWin8 = [math]::Floor($DigitalProductId[$keyOffset + 14] / 6) -band 1
    $DigitalProductId[$keyOffset + 14] = ($DigitalProductId[$keyOffset + 14] -band 0xF7) -bor (($isWin8 -band 2) * 4)

    $chars = 'BCDFGHJKMPQRTVWXY2346789'
    $key = ''

    for ($i = 24; $i -ge 0; $i--) {
        $current = 0
        for ($j = 14; $j -ge 0; $j--) {
            $current = $current * 256
            $current = $DigitalProductId[$j + $keyOffset] + $current
            $DigitalProductId[$j + $keyOffset] = [math]::Floor($current / 24)
            $current = $current % 24
        }
        $key = $chars[$current] + $key
    }

    if ($isWin8) {
        $keypart1 = $key.Substring(1, $current)
        $key = $keypart1 + 'N' + $key.Substring($current + 1)
    }

    # Insert dashes
    for ($i = 4; $i -ge 1; $i--) {
        $key = $key.Insert($i * 5, '-')
    }
    return $key
}

Write-Host "`n=== Product Key Finder ===" -ForegroundColor Cyan
Write-Host ""

if ($HivePath) {
    Write-Host "  Loading offline hive: $HivePath"
    $tempKey = 'HKLM\OFFLINE_SOFT'
    reg load $tempKey "$HivePath" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Could not load hive. Is the path correct?" -ForegroundColor Red
        Write-Host "  Example: .\Get-ProductKey.ps1 -HivePath 'D:\Windows\System32\config\SOFTWARE'"
        Read-Host "`n  Press Enter to close"
        return
    }
    $regPath = 'OFFLINE_SOFT\Microsoft\Windows NT\CurrentVersion'
    $productName = (Get-ItemProperty "HKLM:\$regPath" -ErrorAction SilentlyContinue).ProductName
    $digitalId = (Get-ItemProperty "HKLM:\$regPath" -ErrorAction SilentlyContinue).DigitalProductId
    reg unload $tempKey 2>$null
} else {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $productName = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).ProductName
    $digitalId = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).DigitalProductId
}

Write-Host "  Product: $productName"
Write-Host ""

# Method 1: Decode from DigitalProductId
if ($digitalId) {
    $key = Decode-ProductKey -DigitalProductId ([byte[]]$digitalId)
    if ($key -and $key -notmatch '^B+') {
        Write-Host "  Product Key:  $key" -ForegroundColor Green
    }
}

# Method 2: Try SoftwareLicensingService (online only)
if (-not $HivePath) {
    $sls = Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue
    if ($sls.OA3xOriginalProductKey) {
        Write-Host "  OEM Key:      $($sls.OA3xOriginalProductKey)" -ForegroundColor Green
    }
}

# Office keys
Write-Host ""
Write-Host "  Checking for Office keys..."
$officeVersions = @('16.0', '15.0', '14.0')
$officePaths = @('SOFTWARE\Microsoft\Office', 'SOFTWARE\WOW6432Node\Microsoft\Office')
$foundOffice = $false

foreach ($op in $officePaths) {
    foreach ($ver in $officeVersions) {
        $regKey = "HKLM:\$op\$ver\Registration"
        if (Test-Path $regKey) {
            Get-ChildItem $regKey -ErrorAction SilentlyContinue | ForEach-Object {
                $dpid = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DigitalProductId
                $prodName = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ProductName
                if ($dpid -and $prodName) {
                    $oKey = Decode-ProductKey -DigitalProductId ([byte[]]$dpid)
                    if ($oKey -and $oKey -notmatch '^B+') {
                        Write-Host "  $prodName`:  $oKey" -ForegroundColor Green
                        $foundOffice = $true
                    }
                }
            }
        }
    }
}

if (-not $foundOffice) {
    Write-Host "  No Office product keys found." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Done. Press Enter to close." -ForegroundColor Cyan
Read-Host
