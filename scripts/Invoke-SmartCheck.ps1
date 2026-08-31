<#
.SYNOPSIS
    Vector Toolset - Quick SMART Health Check
.DESCRIPTION
    Runs a pass/fail SMART check on every connected disk.
    Uses smartctl if available, falls back to WMI.
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent)
)

Write-Host "`n=== SMART Health Check ===" -ForegroundColor Cyan
Write-Host ""

$disks = Get-CimInstance Win32_DiskDrive | Where-Object { $_.MediaType -notlike '*Removable*' }

if ($disks.Count -eq 0) {
    Write-Host "  No fixed disks found." -ForegroundColor Yellow
    Read-Host "`n  Press Enter to close"
    return
}

$smartctlAvailable = $null -ne (Get-Command smartctl.exe -ErrorAction SilentlyContinue)

$results = @()
foreach ($disk in $disks) {
    $info = @{
        Device = $disk.DeviceID
        Model  = $disk.Model
        Size   = "$([math]::Round($disk.Size / 1GB, 0)) GB"
        Status = 'Unknown'
        Temp   = 'N/A'
        Hours  = 'N/A'
        Errors = 'N/A'
    }

    if ($smartctlAvailable) {
        $raw = & smartctl.exe -a $disk.DeviceID 2>$null
        $rawText = $raw -join "`n"

        if ($rawText -match 'PASSED') { $info.Status = 'PASSED' }
        elseif ($rawText -match 'FAILED') { $info.Status = 'FAILED' }

        $tempMatch = $raw | Select-String 'Temperature_Celsius|Airflow_Temperature' | Select-Object -First 1
        if ($tempMatch) {
            $fields = $tempMatch.ToString().Trim() -split '\s+'
            if ($fields.Count -ge 10) { $info.Temp = "$($fields[9]) C" }
        }

        $hoursMatch = $raw | Select-String 'Power_On_Hours' | Select-Object -First 1
        if ($hoursMatch) {
            $fields = $hoursMatch.ToString().Trim() -split '\s+'
            if ($fields.Count -ge 10) { $info.Hours = "$($fields[9]) hrs" }
        }

        $reallocMatch = $raw | Select-String 'Reallocated_Sector_Ct' | Select-Object -First 1
        if ($reallocMatch) {
            $fields = $reallocMatch.ToString().Trim() -split '\s+'
            if ($fields.Count -ge 10 -and $fields[9] -ne '0') {
                $info.Errors = "$($fields[9]) reallocated sectors"
            }
        }
    } else {
        # WMI fallback
        $wmiStatus = Get-CimInstance -Namespace 'root\WMI' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceName -match [regex]::Escape($disk.PNPDeviceID) }
        if ($wmiStatus) {
            $info.Status = if ($wmiStatus.PredictFailure) { 'FAILING' } else { 'OK' }
        }
    }

    $results += $info

    # Print this disk
    $color = switch ($info.Status) {
        'PASSED' { 'Green' }
        'OK'     { 'Green' }
        'FAILED' { 'Red' }
        'FAILING'{ 'Red' }
        default  { 'Yellow' }
    }

    Write-Host "  $($info.Model)" -ForegroundColor White -NoNewline
    Write-Host "  ($($info.Size), $($info.Device))"
    Write-Host "    Status: " -NoNewline; Write-Host $info.Status -ForegroundColor $color
    if ($info.Temp -ne 'N/A')   { Write-Host "    Temp:   $($info.Temp)" }
    if ($info.Hours -ne 'N/A')  { Write-Host "    Hours:  $($info.Hours)" }
    if ($info.Errors -ne 'N/A') { Write-Host "    Errors: $($info.Errors)" -ForegroundColor Yellow }
    Write-Host ""
}

$failed = @($results | Where-Object { $_.Status -eq 'FAILED' -or $_.Status -eq 'FAILING' })
if ($failed.Count -gt 0) {
    Write-Host "  WARNING: $($failed.Count) disk(s) reporting failure!" -ForegroundColor Red
} else {
    Write-Host "  All disks healthy." -ForegroundColor Green
}

if (-not $smartctlAvailable) {
    Write-Host ""
    Write-Host "  Note: smartctl not found - using basic WMI checks." -ForegroundColor DarkGray
    Write-Host "  For detailed SMART data, place smartctl.exe in tools\diagnostics\smartmontools\bin\." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Done. Press Enter to close." -ForegroundColor Cyan
Read-Host
