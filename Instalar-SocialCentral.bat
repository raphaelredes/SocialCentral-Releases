<# :
@echo off
setlocal
title SocialCentral - Instalador Automatico (WoW Forever)
chcp 65001 >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$code = (Get-Content -LiteralPath '%~f0' -Raw -Encoding UTF8); Invoke-Expression $code"
exit /b %errorlevel%
#>

# ============================================================
# SocialCentral - Instalador Automatico (1-Clique)
# Compativel: Windows 10 / 11, WoW Forever (Interface 16001)
# ============================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Banner {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "    SocialCentral - Instalador Automatico (1-Clique)" -ForegroundColor Yellow
    Write-Host "             World of Warcraft: Forever                 " -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

Write-Banner

# 1. Localizar pasta do World of Warcraft: Forever
Write-Host "[1/3] Localizando pasta do World of Warcraft: Forever..." -ForegroundColor White

$targetAddons = $null

if ($env:WOW_FOREVER_ADDONS -and (Test-Path $env:WOW_FOREVER_ADDONS)) {
    $targetAddons = $env:WOW_FOREVER_ADDONS
}

if (-not $targetAddons) {
    $candidates = @(
        "Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns",
        "Program Files\World of Warcraft\_forever_\Interface\AddOns",
        "World of Warcraft\_forever_\Interface\AddOns",
        "Games\World of Warcraft\_forever_\Interface\AddOns",
        "Jogos\World of Warcraft\_forever_\Interface\AddOns"
    )

    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
    foreach ($d in $drives) {
        foreach ($c in $candidates) {
            $p = Join-Path $d.RootDirectory.FullName $c
            if (Test-Path $p) {
                $targetAddons = $p
                break
            }
        }
        if ($targetAddons) { break }
    }
}

if (-not $targetAddons) {
    Write-Host "AVISO: A pasta do WoW Forever nao foi encontrada automaticamente." -ForegroundColor Yellow
    Write-Host "Exemplo: C:\Program Files (x86)\World of Warcraft" -ForegroundColor Gray
    Write-Host ""
    $userPath = Read-Host "Por favor, digite ou cole o caminho da pasta do seu WoW"
    if ($userPath) {
        $p1 = Join-Path $userPath "_forever_\Interface\AddOns"
        $p2 = Join-Path $userPath "Interface\AddOns"
        if (Test-Path $p1) {
            $targetAddons = $p1
        } elseif (Test-Path $p2) {
            $targetAddons = $p2
        }
    }
}

if (-not $targetAddons -or -not (Test-Path $targetAddons)) {
    Write-Host ""
    Write-Host "ERRO: Nao foi possivel localizar a pasta Interface\AddOns do WoW." -ForegroundColor Red
    Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    exit 1
}

Write-Host "  -> Pasta localizada: $targetAddons" -ForegroundColor Green
Write-Host ""

# Testar permissao de gravacao na pasta AddOns (caso precise de Administrador)
$permTest = Join-Path $targetAddons (".sc_perm_" + [guid]::NewGuid().ToString("N"))
$needsElevation = $false
try {
    [System.IO.File]::WriteAllText($permTest, "test")
    Remove-Item -LiteralPath $permTest -Force -ErrorAction SilentlyContinue
} catch {
    $needsElevation = $true
}

if ($needsElevation) {
    Write-Host "[INFO] A pasta requer permissao de Administrador do Windows." -ForegroundColor Yellow
    Write-Host "       Solicitando elevacao UAC..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath -and (Test-Path "$PSScriptRoot\Instalar-SocialCentral.bat")) {
        $scriptPath = "$PSScriptRoot\Instalar-SocialCentral.bat"
    }
    if ($scriptPath) {
        Start-Process "cmd.exe" -ArgumentList "/c `"$scriptPath`"" -Verb RunAs
        exit 0
    }
}

$destDir = Join-Path $targetAddons "SocialCentral"

# 2. Identificar origem dos arquivos (Local ou Download GitHub)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$localSource = $null
if (Test-Path (Join-Path $scriptDir "SocialCentral.toc")) {
    $localSource = $scriptDir
} elseif (Test-Path (Join-Path $scriptDir "SocialCentral\SocialCentral.toc")) {
    $localSource = Join-Path $scriptDir "SocialCentral"
}

$tempRoot = $null

if ($localSource) {
    Write-Host "[2/3] Instalando a partir dos arquivos locais..." -ForegroundColor White
    $sourceDir = $localSource
} else {
    Write-Host "[2/3] Baixando a versao oficial mais recente do GitHub..." -ForegroundColor White

    $repo = "raphaelredes/SocialCentral-Releases"
    $apiUrl = "https://api.github.com/repos/$repo/releases/latest"
    $headers = @{
        "User-Agent" = "SocialCentral-Installer"
        "Accept"     = "application/vnd.github+json"
    }

    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
        $tag = [string]$release.tag_name
        Write-Host "  -> Versao encontrada no GitHub: $tag" -ForegroundColor Cyan

        $asset = $release.assets | Where-Object { $_.name -match 'SocialCentral.*\.zip$' } | Select-Object -First 1
        $downloadUrl = if ($asset) { $asset.browser_download_url } else { $release.zipball_url }

        $tempRoot = Join-Path $env:TEMP ("SocialCentralInstall_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $zipFile = Join-Path $tempRoot "SocialCentral.zip"
        $extractDir = Join-Path $tempRoot "extract"
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

        Write-Host "  -> Baixando arquivo da release..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $downloadUrl -Headers $headers -OutFile $zipFile

        Write-Host "  -> Extraindo arquivos..." -ForegroundColor Gray
        Expand-Archive -LiteralPath $zipFile -DestinationPath $extractDir -Force

        $toc = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "SocialCentral.toc" | Select-Object -First 1
        if (-not $toc) {
            throw "O arquivo SocialCentral.toc nao foi encontrado no pacote baixado."
        }
        $sourceDir = $toc.DirectoryName
    } catch {
        Write-Host ""
        Write-Host "ERRO ao baixar do GitHub: $($_.Exception.Message)" -ForegroundColor Red
        if ($tempRoot -and (Test-Path $tempRoot)) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        exit 1
    }
}

# 3. Copiar arquivos para a pasta do WoW
Write-Host "[3/3] Instalando SocialCentral em: $destDir ..." -ForegroundColor White

$runtimeFiles = @("SocialCentral.toc", "LICENSE", "CHANGELOG.md", "README.md")
$runtimeDirs = @("Locales", "Core", "Providers", "UI", "Media")

try {
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    foreach ($file in $runtimeFiles) {
        $src = Join-Path $sourceDir $file
        if (Test-Path $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $destDir $file) -Force
        }
    }

    foreach ($dir in $runtimeDirs) {
        $srcDir = Join-Path $sourceDir $dir
        if (Test-Path $srcDir) {
            $destSub = Join-Path $destDir $dir
            if (-not (Test-Path $destSub)) {
                New-Item -ItemType Directory -Path $destSub -Force | Out-Null
            }
            Copy-Item -LiteralPath "$srcDir\*" -Destination $destSub -Recurse -Force
        }
    }
} finally {
    if ($tempRoot -and (Test-Path $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "     SUCESSO: SocialCentral foi instalado com sucesso!      " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasta de destino:" -ForegroundColor White
Write-Host "  $destDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "DICA: Se o World of Warcraft ja estiver aberto:" -ForegroundColor Yellow
Write-Host "      Basta digitar /reload no chat do jogo." -ForegroundColor Yellow
Write-Host ""
Write-Host "Pressione qualquer tecla para fechar esta janela..." -ForegroundColor Gray
if (-not [Console]::IsInputRedirected) {
    try { $null = [Console]::ReadKey($true) } catch {}
}
exit 0
