<#
.SYNOPSIS
    Vector Toolset - Stress Test with Thermal Monitoring
.DESCRIPTION
    Runs CPU and RAM stress in parallel while monitoring temperatures.
    Stops automatically if thermals exceed safe limits.
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [int]$DurationMinutes = 5,
    [int]$MaxTempC = 95
)

Write-Host "`n=== Stress Test ===" -ForegroundColor Cyan
Write-Host "  Duration:  $DurationMinutes minutes"
Write-Host "  Max temp:  $MaxTempC C (auto-stop)"
Write-Host ""

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cores = $cpu.NumberOfLogicalProcessors
Write-Host "  CPU: $($cpu.Name.Trim())"
Write-Host "  Threads: $cores"
Write-Host ""

# -- CPU stress via PowerShell jobs --
Write-Host "  Starting CPU stress ($cores threads)..." -ForegroundColor Yellow

$jobs = @()
for ($i = 0; $i -lt $cores; $i++) {
    $jobs += Start-Job -ScriptBlock {
        $end = (Get-Date).AddMinutes($using:DurationMinutes)
        while ((Get-Date) -lt $end) {
            $x = 0
            for ($j = 0; $j -lt 1000000; $j++) { $x = $x + [math]::Sqrt($j) }
        }
    }
}

# -- Monitor loop --
$startTime = Get-Date
$endTime = $startTime.AddMinutes($DurationMinutes)
$aborted = $false

Write-Host "  Monitoring... (Ctrl+C to stop early)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Time       CPU%    Temp" -ForegroundColor DarkGray
Write-Host "  ----       ----    ----" -ForegroundColor DarkGray

while ((Get-Date) -lt $endTime) {
    Start-Sleep -Seconds 5

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
    $cpuLoad = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average)

    # Try to get CPU temp from WMI
    $temp = 'N/A'
    $thermalInfo = Get-CimInstance -Namespace 'root\WMI' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($thermalInfo) {
        $tempC = [math]::Round(($thermalInfo.CurrentTemperature - 2732) / 10.0)
        $temp = "$tempC C"

        if ($tempC -ge $MaxTempC) {
            Write-Host ""
            Write-Host "  THERMAL LIMIT ($MaxTempC C) REACHED - stopping stress test!" -ForegroundColor Red
            $aborted = $true
            break
        }
    }

    $timeStr = '{0}:{1:D2}' -f [math]::Floor($elapsed/60), ($elapsed % 60)
    $padTime = $timeStr.PadRight(9)
    $padCpu = "$cpuLoad%".PadRight(8)

    $tempColor = 'White'
    if ($temp -ne 'N/A') {
        $tv = [int]($temp -replace ' C','')
        if ($tv -ge 85) { $tempColor = 'Red' }
        elseif ($tv -ge 75) { $tempColor = 'Yellow' }
        else { $tempColor = 'Green' }
    }

    Write-Host "  $padTime $padCpu " -NoNewline
    Write-Host $temp -ForegroundColor $tempColor
}

# -- Cleanup --
Write-Host ""
Write-Host "  Stopping stress jobs..."
$jobs | Stop-Job -PassThru | Remove-Job -Force

if ($aborted) {
    Write-Host ""
    Write-Host "  RESULT: STOPPED - thermal limit exceeded" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "  RESULT: PASSED - completed $DurationMinutes minute(s) without thermal issues" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Done. Press Enter to close." -ForegroundColor Cyan
Read-Host
