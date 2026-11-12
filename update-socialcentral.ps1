[CmdletBinding()]
param(
    [string]$AddOnsDir = $(if ($env:WOW_FOREVER_ADDONS) { $env:WOW_FOREVER_ADDONS } else { "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns" }),
    [string]$Repo = "raphaelredes/SocialCentral-Releases",
    [switch]$CheckOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function ConvertTo-SemVerTuple {
    param([string]$VersionText)
    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return @(0, 0, 0)
    }
    $clean = $VersionText.Trim() -replace '^[vV]', ''
    $m = [regex]::Match($clean, '^(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) {
        return @(0, 0, 0)
    }
    return @(
        [int]$m.Groups[1].Value,
        [int]$m.Groups[2].Value,
        [int]$m.Groups[3].Value
    )
}

function Compare-SemVer {
    param([string]$VerA, [string]$VerB)
    $a = ConvertTo-SemVerTuple $VerA
    $b = ConvertTo-SemVerTuple $VerB
    for ($i = 0; $i -lt 3; $i++) {
        if ($a[$i] -lt $b[$i]) { return -1 }
        if ($a[$i] -gt $b[$i]) { return 1 }
    }
    return 0
}

function Get-InstalledVersion {
    param([string]$AddonPath)
    $toc = Join-Path $AddonPath "SocialCentral.toc"
    if (-not (Test-Path $toc)) {
        return "0.0.0"
    }
    $raw = Get-Content -LiteralPath $toc -Raw -Encoding UTF8
    $m = [regex]::Match($raw, '(?mi)^##\s*Version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
    if ($m.Success) {
        return $m.Groups[1].Value
    }
    return "0.0.0"
}

$targetAddon = Join-Path $AddOnsDir "SocialCentral"
$installedVer = Get-InstalledVersion -AddonPath $targetAddon
Write-Host "Installed version : $installedVer ($targetAddon)"

$apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$headers = @{
    "User-Agent" = "SocialCentral-Updater"
    "Accept"     = "application/vnd.github+json"
}

try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
} catch {
    throw "Failed to check latest release from GitHub ($apiUrl): $($_.Exception.Message)"
}

$remoteTag = [string]$release.tag_name
$remoteVer = ($remoteTag -replace '^[vV]', '').Trim()
if ([string]::IsNullOrWhiteSpace($remoteVer)) {
    throw "Latest GitHub release does not declare a valid tag_name."
}

$cmp = Compare-SemVer -VerA $remoteVer -VerB $installedVer
Write-Host "Latest GitHub tag : $remoteTag ($($release.html_url))"

if ($CheckOnly) {
    if ($cmp -gt 0) {
        Write-Host "UPDATE AVAILABLE: $installedVer -> $remoteVer"
        Write-Host "Run without -CheckOnly to download and install cleanly into $targetAddon."
    } elseif ($cmp -eq 0) {
        Write-Host "UP TO DATE: SocialCentral $installedVer is already the latest version."
    } else {
        Write-Host "LOCAL NEWER OR DEV BUILD: installed=$installedVer, remote=$remoteVer"
    }
    exit 0
}

if (($cmp -le 0) -and (-not $Force)) {
    Write-Host "SocialCentral is already up to date ($installedVer). Use -Force to reinstall."
    exit 0
}

if (-not (Test-Path $AddOnsDir)) {
    throw "WoW AddOns directory not found: $AddOnsDir"
}

if (-not $targetAddon.EndsWith("\Interface\AddOns\SocialCentral", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unexpected target path: $targetAddon"
}

$zipAsset = $release.assets | Where-Object { $_.name -match '^SocialCentral-v?[\d.]+\.zip$' } | Select-Object -First 1
$downloadUrl = if ($zipAsset) { $zipAsset.browser_download_url } else { $release.zipball_url }
if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    throw "No downloadable archive found on release $remoteTag."
}

$tempRoot = Join-Path $env:TEMP ("SocialCentralUpdater_" + [guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "SocialCentral.zip"
$extractDir = Join-Path $tempRoot "extract"
$backupDir = Join-Path $tempRoot "backup"

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    Write-Host "Downloading $downloadUrl ..."
    Invoke-WebRequest -Uri $downloadUrl -Headers $headers -OutFile $zipPath

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $tocFile = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "SocialCentral.toc" | Select-Object -First 1
    if (-not $tocFile) {
        throw "Downloaded archive does not contain SocialCentral.toc."
    }
    $sourceRoot = $tocFile.DirectoryName

    # Security & Blizzard cleanliness whitelist: strictly runtime files enter the game AddOns folder.
    $runtimeFiles = @("SocialCentral.toc", "LICENSE")
    $runtimeDirs = @("Locales", "Core", "Providers", "UI", "Media")

    $luaFiles = Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter "*.lua"
    foreach ($lua in $luaFiles) {
        $luaText = Get-Content -LiteralPath $lua.FullName -Raw -Encoding UTF8
        foreach ($forbidden in @('\bhooksecurefunc\s*\(\s*"SetItemRef"', 'patreon\.com', 'paypal\.com', 'ko-fi\.com')) {
            if ($luaText -match $forbidden) {
                throw "Safety check rejected archive Lua file $($lua.Name) matching $forbidden."
            }
        }
    }

    if (Test-Path $targetAddon) {
        Move-Item -LiteralPath $targetAddon -Destination $backupDir -Force
    }

    try {
        New-Item -ItemType Directory -Path $targetAddon -Force | Out-Null

        foreach ($file in $runtimeFiles) {
            $src = Join-Path $sourceRoot $file
            if (Test-Path $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $targetAddon $file) -Force
            }
        }
        foreach ($dir in $runtimeDirs) {
            $srcDir = Join-Path $sourceRoot $dir
            if (Test-Path $srcDir) {
                Copy-Item -LiteralPath $srcDir -Destination (Join-Path $targetAddon $dir) -Recurse -Force
            }
        }
    } catch {
        if (Test-Path $targetAddon) {
            Remove-Item -LiteralPath $targetAddon -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $backupDir) {
            Move-Item -LiteralPath $backupDir -Destination $targetAddon -Force
        }
        throw
    }

    Write-Host "Successfully updated SocialCentral to v$remoteVer at: $targetAddon"
    Write-Host "If World of Warcraft is running, type /reload in chat."
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
