<#
.SYNOPSIS
    Vector Toolset - Full Diagnostic Report
.DESCRIPTION
    Collects system info, disk health, network adapters, driver status,
    battery health, and temperatures. Outputs a branded HTML report.
.PARAMETER ToolsetRoot
    Path to the toolkit root (set automatically by the launcher).
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'

# -- Load shop config --
$shopFile = Join-Path $ToolsetRoot 'config\shop.json'
$shop = @{ shopName = 'Vector Toolset'; tagline = 'Diagnostics and Repair' }
if (Test-Path $shopFile) {
    try { $shop = Get-Content $shopFile -Raw | ConvertFrom-Json } catch {}
}
$ShopName = if ($shop.shopName) { $shop.shopName } elseif ($shop.product) { $shop.product } else { 'Vector Toolset' }

Write-Host "`n=== $ShopName - Diagnostic Report ===" -ForegroundColor Cyan
Write-Host ""

# -- System info --
Write-Host "  Collecting system info..."
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$mb = Get-CimInstance Win32_BaseBoard

$sysInfo = @{
    Hostname     = $env:COMPUTERNAME
    Manufacturer = $cs.Manufacturer
    Model        = $cs.Model
    Serial       = $bios.SerialNumber
    BIOSVersion  = $bios.SMBIOSBIOSVersion
    Motherboard  = "$($mb.Manufacturer) $($mb.Product)"
    CPU          = $cpu.Name.Trim()
    Cores        = "$($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"
    RAM          = "$([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB"
    OS           = "$($os.Caption) ($($os.Version))"
    Architecture = $os.OSArchitecture
}

# -- RAM modules --
Write-Host "  Collecting RAM details..."
$ram = Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    @{
        Slot     = $_.DeviceLocator
        Size     = "$([math]::Round($_.Capacity / 1GB, 1)) GB"
        Speed    = "$($_.Speed) MHz"
        Type     = $_.PartNumber.Trim()
    }
}

# -- Disks --
Write-Host "  Collecting disk info..."
$disks = Get-CimInstance Win32_DiskDrive | ForEach-Object {
    $disk = $_
    $smart = 'N/A'
    $temp = 'N/A'

    # Try smartctl if available
    $smartctl = Get-Command smartctl.exe -ErrorAction SilentlyContinue
    if ($smartctl) {
        $health = & smartctl.exe -H $disk.DeviceID 2>$null | Select-String 'PASSED|FAILED'
        if ($health) { $smart = $health.ToString().Trim() -replace '.*:\s*', '' }
        $tempLine = & smartctl.exe -A $disk.DeviceID 2>$null | Select-String 'Temperature' | Select-Object -First 1
        if ($tempLine) {
            $nums = [regex]::Matches($tempLine.ToString(), '\d+')
            if ($nums.Count -gt 0) { $temp = "$($nums[$nums.Count - 1].Value) C" }
        }
    }

    @{
        Model     = $disk.Model
        Serial    = $disk.SerialNumber.Trim()
        Size      = "$([math]::Round($disk.Size / 1GB, 0)) GB"
        Interface = $disk.InterfaceType
        SMART     = $smart
        Temp      = $temp
    }
}

# -- Partitions --
Write-Host "  Collecting partition info..."
$volumes = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
    @{
        Drive     = $_.DeviceID
        Label     = $_.VolumeName
        FileSystem = $_.FileSystem
        Size      = "$([math]::Round($_.Size / 1GB, 1)) GB"
        Free      = "$([math]::Round($_.FreeSpace / 1GB, 1)) GB"
        PctFree   = if ($_.Size -gt 0) { "$([math]::Round($_.FreeSpace / $_.Size * 100, 0))%" } else { 'N/A' }
    }
}

# -- Network --
Write-Host "  Collecting network info..."
$nics = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled } | ForEach-Object {
    @{
        Name    = $_.Description
        MAC     = $_.MACAddress
        IP      = ($_.IPAddress | Where-Object { $_ -notmatch ':' }) -join ', '
        DHCP    = if ($_.DHCPEnabled) { 'Yes' } else { 'No' }
        Gateway = ($_.DefaultIPGateway) -join ', '
        DNS     = ($_.DNSServerSearchOrder) -join ', '
    }
}

# -- GPU --
Write-Host "  Collecting GPU info..."
$gpus = Get-CimInstance Win32_VideoController | ForEach-Object {
    @{
        Name       = $_.Name
        RAM        = "$([math]::Round($_.AdapterRAM / 1GB, 1)) GB"
        Driver     = $_.DriverVersion
        Resolution = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
    }
}

# -- Battery --
Write-Host "  Collecting battery info..."
$battery = $null
$bat = Get-CimInstance Win32_Battery
if ($bat) {
    $battery = @{
        Status   = $bat.Status
        Charge   = "$($bat.EstimatedChargeRemaining)%"
        Runtime  = if ($bat.EstimatedRunTime -and $bat.EstimatedRunTime -lt 71582) {
                       "$($bat.EstimatedRunTime) min"
                   } else { 'AC Power' }
    }
    # Design vs full charge capacity (if available via WMI)
    $batFull = Get-CimInstance -Namespace 'root\WMI' -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
    $batDesign = Get-CimInstance -Namespace 'root\WMI' -ClassName BatteryStaticData -ErrorAction SilentlyContinue
    if ($batFull -and $batDesign -and $batDesign.DesignedCapacity -gt 0) {
        $health = [math]::Round($batFull.FullChargedCapacity / $batDesign.DesignedCapacity * 100, 0)
        $battery.Health = "$health%"
        $battery.DesignCapacity = "$($batDesign.DesignedCapacity) mWh"
        $battery.FullCharge = "$($batFull.FullChargedCapacity) mWh"
    }
}

# -- Problem drivers --
Write-Host "  Checking drivers..."
$problemDrivers = Get-CimInstance Win32_PnPEntity |
    Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
    ForEach-Object {
        @{
            Name      = $_.Name
            DeviceID  = $_.DeviceID
            ErrorCode = $_.ConfigManagerErrorCode
        }
    }

# -- Generate report --
Write-Host ""
Write-Host "  Generating report..."

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportDate = Get-Date -Format 'yyyy-MM-dd'

function HtmlRow($label, $value) {
    "  <tr><td class=`"lbl`">$label</td><td>$(Enc $value)</td></tr>"
}

function Enc([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

$alertsHtml = ''
if ($problemDrivers.Count -gt 0) {
    $alertsHtml += "<div class=`"alert warn`"><strong>$($problemDrivers.Count) device(s) with driver problems:</strong><ul>"
    foreach ($d in $problemDrivers) {
        $alertsHtml += "<li>$(Enc($d.Name)) (error $($d.ErrorCode))</li>"
    }
    $alertsHtml += '</ul></div>'
}

$failedDisks = @($disks | Where-Object { $_.SMART -eq 'FAILED' })
if ($failedDisks.Count -gt 0) {
    $alertsHtml += "<div class=`"alert crit`"><strong>$($failedDisks.Count) disk(s) FAILING SMART:</strong><ul>"
    foreach ($d in $failedDisks) {
        $alertsHtml += "<li>$(Enc($d.Model))</li>"
    }
    $alertsHtml += '</ul></div>'
}

if ($battery -and $battery.Health) {
    $healthNum = [int]($battery.Health -replace '%','')
    if ($healthNum -lt 50) {
        $alertsHtml += "<div class=`"alert crit`"><strong>Battery health critical: $($battery.Health)</strong> - recommend replacement</div>"
    } elseif ($healthNum -lt 75) {
        $alertsHtml += "<div class=`"alert warn`"><strong>Battery health degraded: $($battery.Health)</strong></div>"
    }
}

# -- HTML assembly --
$html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>Diagnostic Report - $ShopName</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; max-width: 820px; margin: 2em auto; color: #1a1a1a; font-size: 13px; padding: 0 20px; }
  h1 { color: #c25a10; border-bottom: 2px solid #c25a10; padding-bottom: 8px; font-size: 20px; }
  h2 { color: #c25a10; margin-top: 1.8em; font-size: 15px; }
  .meta { color: #666; font-size: 12px; margin-bottom: 20px; }
  table { border-collapse: collapse; width: 100%; margin: 8px 0 16px; }
  th, td { border: 1px solid #ddd; padding: 5px 10px; text-align: left; font-size: 12px; }
  th { background: #f0f4f8; font-weight: 600; }
  .lbl { font-weight: 600; width: 160px; background: #f8f9fa; }
  .ok { color: #1a7f37; font-weight: 600; }
  .warn { color: #9a6700; font-weight: 600; }
  .crit { color: #cf222e; font-weight: 600; }
  .alert { padding: 10px 14px; border-radius: 4px; margin: 12px 0; font-size: 12px; }
  .alert.warn { background: #fff8e1; border: 1px solid #e8a838; color: #7a5500; }
  .alert.crit { background: #fff0f0; border: 1px solid #e85454; color: #9a1c1c; }
  .alert ul { margin: 6px 0 0 18px; padding: 0; }
  .footer { margin-top: 30px; padding-top: 12px; border-top: 1px solid #ddd; color: #999; font-size: 11px; }
  @media print { body { margin: 0; } .alert { break-inside: avoid; } }
</style></head><body>
<h1>$ShopName - Diagnostic Report</h1>
<p class="meta">Generated: $timestamp &nbsp;|&nbsp; Hostname: $($sysInfo.Hostname)</p>

$alertsHtml

<h2>System</h2>
<table>
$(HtmlRow 'Manufacturer' $sysInfo.Manufacturer)
$(HtmlRow 'Model' $sysInfo.Model)
$(HtmlRow 'Serial' $sysInfo.Serial)
$(HtmlRow 'BIOS' $sysInfo.BIOSVersion)
$(HtmlRow 'Motherboard' $sysInfo.Motherboard)
$(HtmlRow 'CPU' $sysInfo.CPU)
$(HtmlRow 'Cores / Threads' $sysInfo.Cores)
$(HtmlRow 'RAM' $sysInfo.RAM)
$(HtmlRow 'OS' $sysInfo.OS)
</table>
"@

# RAM table
if ($ram.Count -gt 0) {
    $html += "<h2>Memory Modules</h2><table><tr><th>Slot</th><th>Size</th><th>Speed</th><th>Part Number</th></tr>"
    foreach ($r in $ram) {
        $html += "<tr><td>$(Enc $r.Slot)</td><td>$($r.Size)</td><td>$($r.Speed)</td><td>$(Enc $r.Type)</td></tr>"
    }
    $html += '</table>'
}

# Disks
$html += "<h2>Storage ($($disks.Count))</h2><table><tr><th>Model</th><th>Serial</th><th>Size</th><th>Interface</th><th>SMART</th><th>Temp</th></tr>"
foreach ($d in $disks) {
    $sc = if ($d.SMART -eq 'FAILED') { 'crit' } elseif ($d.SMART -eq 'PASSED') { 'ok' } else { '' }
    $html += "<tr><td>$(Enc $d.Model)</td><td>$(Enc $d.Serial)</td><td>$($d.Size)</td><td>$(Enc $d.Interface)</td><td class=`"$sc`">$($d.SMART)</td><td>$($d.Temp)</td></tr>"
}
$html += '</table>'

# Volumes
if ($volumes.Count -gt 0) {
    $html += "<h2>Volumes</h2><table><tr><th>Drive</th><th>Label</th><th>FS</th><th>Size</th><th>Free</th><th>% Free</th></tr>"
    foreach ($v in $volumes) {
        $fc = ''
        $pct = [int]($v.PctFree -replace '%','')
        if ($pct -lt 10) { $fc = 'crit' } elseif ($pct -lt 20) { $fc = 'warn' }
        $html += "<tr><td>$($v.Drive)</td><td>$(Enc $v.Label)</td><td>$(Enc $v.FileSystem)</td><td>$($v.Size)</td><td>$($v.Free)</td><td class=`"$fc`">$($v.PctFree)</td></tr>"
    }
    $html += '</table>'
}

# GPU
if ($gpus.Count -gt 0) {
    $html += "<h2>Graphics</h2><table><tr><th>GPU</th><th>VRAM</th><th>Driver</th><th>Resolution</th></tr>"
    foreach ($g in $gpus) {
        $html += "<tr><td>$(Enc $g.Name)</td><td>$($g.RAM)</td><td>$(Enc $g.Driver)</td><td>$($g.Resolution)</td></tr>"
    }
    $html += '</table>'
}

# Network
if ($nics.Count -gt 0) {
    $html += "<h2>Network</h2><table><tr><th>Adapter</th><th>MAC</th><th>IP</th><th>DHCP</th><th>Gateway</th></tr>"
    foreach ($n in $nics) {
        $html += "<tr><td>$(Enc $n.Name)</td><td>$($n.MAC)</td><td>$($n.IP)</td><td>$($n.DHCP)</td><td>$($n.Gateway)</td></tr>"
    }
    $html += '</table>'
}

# Battery
if ($battery) {
    $html += '<h2>Battery</h2><table>'
    $html += HtmlRow 'Status' $battery.Status
    $html += HtmlRow 'Charge' $battery.Charge
    $html += HtmlRow 'Runtime' $battery.Runtime
    if ($battery.Health) {
        $hc = ''
        $hv = [int]($battery.Health -replace '%','')
        if ($hv -lt 50) { $hc = 'crit' } elseif ($hv -lt 75) { $hc = 'warn' } else { $hc = 'ok' }
        $html += "  <tr><td class=`"lbl`">Health</td><td class=`"$hc`">$($battery.Health)</td></tr>"
        $html += HtmlRow 'Design Capacity' $battery.DesignCapacity
        $html += HtmlRow 'Full Charge Capacity' $battery.FullCharge
    }
    $html += '</table>'
}

# Problem devices
if ($problemDrivers.Count -gt 0) {
    $html += "<h2>Problem Devices ($($problemDrivers.Count))</h2><table><tr><th>Device</th><th>Error Code</th></tr>"
    foreach ($d in $problemDrivers) {
        $html += "<tr><td>$(Enc($d.Name))</td><td class=`"warn`">$($d.ErrorCode)</td></tr>"
    }
    $html += '</table>'
}

$html += @"
<div class="footer">
  $ShopName - Generated by Vector Toolset on $timestamp
</div>
</body></html>
"@

# Write output. Default to a reports folder on the toolset root so results
# persist on the data partition; fall back to TEMP if that is not writable.
if ([string]::IsNullOrEmpty($OutputPath)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportsDir = Join-Path $ToolsetRoot 'reports'
    try {
        if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force -ErrorAction Stop | Out-Null }
        $OutputPath = Join-Path $reportsDir "Diagnostic-$env:COMPUTERNAME-$stamp"
    } catch {
        $OutputPath = Join-Path $env:TEMP "Vector-Diagnostic-$env:COMPUTERNAME-$stamp"
    }
}
$htmlPath = "$OutputPath.html"
$html | Out-File -FilePath $htmlPath -Encoding utf8
Write-Host "  Report saved: $htmlPath" -ForegroundColor Green

# Open the report
Start-Process $htmlPath
Write-Host ""
Write-Host "  Done. Press Enter to close." -ForegroundColor Cyan
Read-Host
