<#
.SYNOPSIS
    Vector Toolset - fetch the Linux payload ISOs
.DESCRIPTION
    Downloads the GRUB payload from the pinned sources in build\payload.json:
    Clonezilla, GParted, SystemRescue, and ShredOS as ISOs, plus Memtest86+
    (its 64-bit EFI and BIOS binaries extracted from the release zip). Output
    goes to build\payload (gitignored). Deploy-USB.ps1 -PayloadSource build\payload
    copies them onto the stick. The out names match the entries in boot/grub.cfg.
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
.PARAMETER OutDir
    Where to put the payload. Defaults to build\payload.
.PARAMETER Only
    Optional comma-separated list of ids to fetch.
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutDir,
    [string]$Only
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Vector-Toolset'
if (-not $OutDir) { $OutDir = Join-Path $ToolsetRoot 'build\payload' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$tmp = Join-Path $env:TEMP 'vector-payload'
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

$sources = (Get-Content (Join-Path $ToolsetRoot 'build\payload.json') -Raw | ConvertFrom-Json).tools
$onlyList = if ($Only) { $Only.Split(',') | ForEach-Object { $_.Trim() } } else { $null }

function Resolve-GitHubAsset([string]$repo, [string]$rx) {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = $ua } -UseBasicParsing
    $a = $rel.assets | Where-Object { $_.name -match $rx } | Select-Object -First 1
    if (-not $a) { throw "no asset matched /$rx/ in $($rel.tag_name)" }
    return $a.browser_download_url
}

function Resolve-SourceForge([string]$page) {
    # SourceForge serves an HTML interstitial to scripted clients. That page carries
    # a meta-refresh to a signed download URL (a ?ts= token) that 302s to a real
    # mirror. Fetch the interstitial, pull the refresh target, and HTML-decode it.
    $html = (Invoke-WebRequest -Uri $page -UserAgent $ua -UseBasicParsing).Content
    $m = [regex]::Match($html, '(?i)refresh"\s*content="\d+;\s*url=([^"]+)"')
    if (-not $m.Success) { throw "no meta-refresh on SourceForge page" }
    return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
}

Write-Host ""
Write-Host "=== Vector Toolset - payload fetch ===" -ForegroundColor Cyan
Write-Host ""

$ok = 0; $fail = 0
foreach ($id in $sources.PSObject.Properties.Name) {
    if ($onlyList -and ($onlyList -notcontains $id)) { continue }
    $s = $sources.$id
    try {
        Write-Host ("  {0,-14} " -f $id) -NoNewline

        if ($s.type -eq 'memtest') {
            # Download the binaries zip (from memtest.org) and extract the 64-bit
            # EFI and BIOS images.
            $url = $s.url
            $zip = Join-Path $tmp 'memtest.zip'
            Invoke-WebRequest -Uri $url -OutFile $zip -UserAgent $ua -UseBasicParsing -ErrorAction Stop
            $ex = Join-Path $tmp 'memtest'
            if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $ex -Force
            # v8.x ships one hybrid binary per arch (e.g. mt86p_810_x86_64) that is
            # valid as BOTH a BIOS boot image and a PE32+ EFI app. The same file
            # serves the chainloader (UEFI) and linux16 (BIOS) GRUB entries.
            $src = Get-ChildItem $ex -Recurse -File | Where-Object { $_.Name -match 'x86_64' } | Select-Object -First 1
            if (-not $src) { $src = Get-ChildItem $ex -Recurse -File | Where-Object { $_.Name -match '(x64|amd64|_64)' } | Select-Object -First 1 }
            if (-not $src) { throw "no x86_64 memtest binary in zip" }
            Copy-Item $src.FullName (Join-Path $OutDir 'memtest.efi') -Force
            Copy-Item $src.FullName (Join-Path $OutDir 'memtest.bin') -Force
            Write-Host ("OK  memtest.efi + memtest.bin (from {0})" -f $src.Name) -ForegroundColor Green
        }
        else {
            $url = switch ($s.type) {
                'github'      { Resolve-GitHubAsset $s.repo $s.asset }
                'sourceforge' { Resolve-SourceForge $s.url }
                default       { $s.url }
            }
            $out = Join-Path $OutDir $s.out
            Invoke-WebRequest -Uri $url -OutFile $out -UserAgent $ua -UseBasicParsing -ErrorAction Stop
            $mb = [math]::Round((Get-Item $out).Length / 1MB, 0)
            Write-Host ("OK  {0}  ({1} MB)" -f $s.out, $mb) -ForegroundColor Green
        }
        $ok++
    }
    catch {
        Write-Host ("FAIL  {0}" -f $_.Exception.Message) -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host ("  Fetched: {0}   Failed: {1}" -f $ok, $fail) -ForegroundColor Cyan
Write-Host ("  Payload in: {0}" -f $OutDir) -ForegroundColor DarkGray
Write-Host ""
