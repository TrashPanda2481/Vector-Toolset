<#
.SYNOPSIS
    Vector Toolset - tool resolver
.DESCRIPTION
    Populates the tools folder from download strategies in build/sources.json.
    Handles GitHub latest-release assets and stable direct links (open source
    tools and NirSoft). Tools not covered by a strategy are reported as manual
    downloads, because they sit behind click-through or EULA pages.
.PARAMETER ToolsetRoot
    Path to the toolkit root. Defaults to the repo root (parent of build).
.PARAMETER Only
    Optional comma-separated list of tool ids to fetch (default: all in sources).
#>
param(
    [string]$ToolsetRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$Only
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Vector-Toolset'
$tmp = Join-Path $env:TEMP 'vector-dl'
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

# Make scoop reachable if it is installed (its shims may not be on this session PATH yet).
$scoopShims = Join-Path $env:USERPROFILE 'scoop\shims'
if ((Test-Path $scoopShims) -and ($env:PATH -notlike "*$scoopShims*")) { $env:PATH = "$scoopShims;$env:PATH" }

$sourcesFile = Join-Path $ToolsetRoot 'build\sources.json'
$sources = (Get-Content $sourcesFile -Raw | ConvertFrom-Json).tools
$onlyList = if ($Only) { $Only.Split(',') | ForEach-Object { $_.Trim() } } else { $null }

function Flatten([string]$folder) {
    # If the folder holds exactly one subdirectory and no files, lift its contents up.
    $items = Get-ChildItem -Force $folder
    $dirs = @($items | Where-Object { $_.PSIsContainer })
    $files = @($items | Where-Object { -not $_.PSIsContainer })
    if ($dirs.Count -eq 1 -and $files.Count -eq 0) {
        Get-ChildItem -Force $dirs[0].FullName | ForEach-Object { Move-Item $_.FullName $folder -Force }
        Remove-Item $dirs[0].FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-GitHubAsset([string]$repo, [string]$assetRegex) {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = $ua } -UseBasicParsing
    $asset = $rel.assets | Where-Object { $_.name -match $assetRegex } | Select-Object -First 1
    if (-not $asset) { throw "no asset matched /$assetRegex/ in $($rel.tag_name)" }
    return @{ url = $asset.browser_download_url; name = $asset.name; ver = $rel.tag_name }
}

Write-Host ""
Write-Host "=== Vector Toolset - tool resolver ===" -ForegroundColor Cyan
Write-Host ""

$ok = 0; $fail = 0
$report = @()

foreach ($id in ($sources.PSObject.Properties.Name)) {
    if ($onlyList -and ($onlyList -notcontains $id)) { continue }
    $s = $sources.$id
    $folder = Join-Path $ToolsetRoot ($s.folder -replace '/', '\')
    try {
        Write-Host ("  {0,-20} " -f $id) -NoNewline

        $ver = ''
        $hash = $null
        if ($s.type -eq 'scoop') {
            if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw 'scoop not installed (run: irm get.scoop.sh | iex)' }
            if ($s.bucket) { & scoop bucket add $s.bucket *> $null }
            & scoop install $s.pkg *> $null
            $prefix = (& scoop prefix $s.pkg) 2>$null
            if (-not $prefix -or -not (Test-Path $prefix)) { throw "scoop install failed for $($s.pkg)" }
            if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
            Get-ChildItem -Force $folder -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $prefix '*') $folder -Recurse -Force
            $ver = 'scoop'
        }
        else {
            $url = $null; $fname = $null
            if ($s.type -eq 'github') {
                $a = Resolve-GitHubAsset $s.repo $s.asset
                $url = $a.url; $fname = $a.name; $ver = $a.ver
            } else {
                $url = $s.url; $fname = Split-Path $url -Leaf
            }

            $dl = Join-Path $tmp $fname
            Invoke-WebRequest -Uri $url -OutFile $dl -UserAgent $ua -UseBasicParsing -ErrorAction Stop

            # Integrity: verify a pinned sha256 if the source has one; always record it.
            $hash = (Get-FileHash -Path $dl -Algorithm SHA256).Hash
            if ($s.sha256 -and $hash -ne ([string]$s.sha256).ToUpper()) {
                throw "sha256 mismatch: expected $($s.sha256), got $hash"
            }

            if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

            if ($s.zip) {
                Get-ChildItem -Force $folder | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Expand-Archive -Path $dl -DestinationPath $folder -Force
                Flatten $folder
            } else {
                # Single-file tool: clear old copies and save under one stable name
                # so re-runs do not accumulate version-named duplicates.
                Get-ChildItem -Force $folder -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                $target = if ($s.exe) { $s.exe } else { $fname }
                Copy-Item $dl (Join-Path $folder $target) -Force
            }
        }

        $exes = @(Get-ChildItem -Recurse -Filter *.exe $folder -ErrorAction SilentlyContinue | Select-Object -First 3)
        $exeList = ($exes | ForEach-Object { $_.FullName.Substring($ToolsetRoot.Length).TrimStart('\') }) -join '; '
        Write-Host ("OK  {0}" -f $ver) -ForegroundColor Green
        if ($exeList) { Write-Host ("     exe: {0}" -f $exeList) -ForegroundColor DarkGray }
        if ($hash) { Write-Host ("     sha256: {0}" -f $hash) -ForegroundColor DarkGray }
        $report += [pscustomobject]@{ id = $id; status = 'OK'; exe = $exeList }
        $ok++
    }
    catch {
        Write-Host ("FAIL  {0}" -f $_.Exception.Message) -ForegroundColor Red
        $report += [pscustomobject]@{ id = $id; status = 'FAIL'; exe = $_.Exception.Message }
        $fail++
    }
}

# Sysinternals suite covers Autoruns, Process Explorer, and TCPView.
$suite = Join-Path $ToolsetRoot 'tools\diagnostics\Sysinternals'
if (Test-Path $suite) {
    $copies = @(
        @{ src = 'Autoruns64.exe'; dest = 'tools\security\Autoruns' },
        @{ src = 'procexp64.exe';  dest = 'tools\utilities\ProcessExplorer' },
        @{ src = 'Tcpview64.exe';  dest = 'tools\network\TCPView' }
    )
    foreach ($c in $copies) {
        $srcPath = Join-Path $suite $c.src
        if (Test-Path $srcPath) {
            $destDir = Join-Path $ToolsetRoot $c.dest
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item $srcPath (Join-Path $destDir $c.src) -Force
            Write-Host ("  {0,-20} OK  from Sysinternals suite" -f ([System.IO.Path]::GetFileNameWithoutExtension($c.src))) -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host ("  Fetched: {0}   Failed: {1}" -f $ok, $fail) -ForegroundColor Cyan
Write-Host ""

# Report portable tools still missing. These need a manual download from the
# source URL in the manifest, because they sit behind click-through or EULA pages.
$manifestFile = Join-Path $ToolsetRoot 'config\tools-manifest.json'
$j = Get-Content $manifestFile -Raw | ConvertFrom-Json
$manual = @()
foreach ($cat in $j.categories) {
    foreach ($t in $cat.tools) {
        if ($t.type -eq 'portable') {
            $full = Join-Path $ToolsetRoot ($t.path -replace '/', '\')
            if (-not (Test-Path $full)) { $manual += [pscustomobject]@{ name = $t.name; url = $t.source.url } }
        }
    }
}
if ($manual.Count -gt 0) {
    Write-Host ("  Manual download needed ({0}). Place each under its tools\ path:" -f $manual.Count) -ForegroundColor Yellow
    $manual | ForEach-Object { Write-Host ("    {0,-30} {1}" -f $_.name, $_.url) -ForegroundColor DarkGray }
    Write-Host ""
}
