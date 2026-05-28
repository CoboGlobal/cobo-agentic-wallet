# Install the latest caw CLI on Windows.
# Re-running is safe: existing binaries are overwritten in place.
#
# Usage (one-liner):
#   irm https://download.agenticwallet.cobo.com/binary-release/install.ps1 | iex
#
# Override version or paths via environment variables before invoking:
#   $env:CAW_VERSION = 'v0.2.85'
#   $env:CAW_BASE_URL = 'https://download.agenticwallet.cobo.com/binary-release'
#   $env:INSTALL_ROOT = "$env:USERPROFILE\.cobo-agentic-wallet"
#
# TSS Node pre-warm is skipped on Windows — onboarding downloads the TSS
# binary on demand.

$ErrorActionPreference = 'Stop'

function Get-EnvOr {
    param([string]$name, [string]$fallback)
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ([string]::IsNullOrEmpty($value)) { return $fallback }
    return $value
}

$CawBaseUrl   = Get-EnvOr 'CAW_BASE_URL'   'https://download.agenticwallet.cobo.com/binary-release'
$CawVersion   = Get-EnvOr 'CAW_VERSION'    'v0.2.86'
$InstallRoot  = Get-EnvOr 'INSTALL_ROOT'   (Join-Path $env:USERPROFILE '.cobo-agentic-wallet')
$BinDir       = Get-EnvOr 'BIN_DIR'        (Join-Path $InstallRoot 'bin')
$LogDir       = Get-EnvOr 'LOG_DIR'        (Join-Path $InstallRoot 'logs')

function Get-Arch {
    switch -Regex ($env:PROCESSOR_ARCHITECTURE) {
        '^(AMD64|x86_64)$' { return 'amd64' }
        '^(ARM64)$'        { return 'arm64' }
        default {
            throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE"
        }
    }
}

function Get-Sha256 {
    param([string]$path)
    return (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower()
}

function Invoke-Download {
    param(
        [Parameter(Mandatory)] [string]$url,
        [Parameter(Mandatory)] [string]$dest
    )
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    # Force TLS 1.2 on older Windows / PowerShell 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

function Expand-CawTarball {
    param(
        [Parameter(Mandatory)] [string]$tarball,
        [Parameter(Mandatory)] [string]$destDir
    )
    $tmp = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP "caw-install-$([Guid]::NewGuid().ToString('N'))")
    try {
        # Windows 10 1803+ and Windows Server 2019+ ship `tar.exe`.
        & tar.exe -xzf $tarball -C $tmp.FullName
        if ($LASTEXITCODE -ne 0) { throw "tar extraction failed (exit $LASTEXITCODE)" }

        $exe = Get-ChildItem -Path $tmp.FullName -Recurse -File |
            Where-Object { $_.Name -in @('caw.exe', 'caw') } |
            Select-Object -First 1
        if (-not $exe) {
            $exe = Get-ChildItem -Path $tmp.FullName -Recurse -File -Filter 'caw-*' |
                Where-Object { $_.Name -notlike '*.sha256' } |
                Select-Object -First 1
        }
        if (-not $exe) { throw "caw binary not found in tarball" }

        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Copy-Item -Path $exe.FullName -Destination (Join-Path $destDir 'caw.exe') -Force
    } finally {
        Remove-Item -Recurse -Force $tmp.FullName -ErrorAction SilentlyContinue
    }
}

function Add-CawToUserPath {
    param([Parameter(Mandatory)] [string]$dir)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $segments = @()
    if ($userPath) { $segments = $userPath.Split(';') | Where-Object { $_ -ne '' } }
    if ($segments -contains $dir) {
        Write-Host "$dir is already on user PATH"
        return $false
    }
    $segments += $dir
    [Environment]::SetEnvironmentVariable('Path', ($segments -join ';'), 'User')
    Write-Host "Added $dir to user PATH (open a new terminal to use 'caw')"
    return $true
}

$arch       = Get-Arch
$os         = 'windows'
$tarballUrl = "$CawBaseUrl/$CawVersion/caw-$os-$arch-$CawVersion.tar.gz"
$shaUrl     = "$tarballUrl.sha256"

foreach ($d in @($BinDir, $LogDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

Write-Host "[1/3] Downloading caw $CawVersion ($os/$arch)..."
$tmpTar = Join-Path $env:TEMP "caw-$CawVersion.tar.gz"
$tmpSum = "$tmpTar.sha256"
Invoke-Download -url $tarballUrl -dest $tmpTar
Invoke-Download -url $shaUrl     -dest $tmpSum

$expected = ((Get-Content $tmpSum -Raw) -split '\s+')[0].ToLower()
$actual   = Get-Sha256 $tmpTar
if ($expected -ne $actual) {
    Remove-Item $tmpTar, $tmpSum -ErrorAction SilentlyContinue
    throw "Checksum mismatch: expected $expected, got $actual"
}
Write-Host "Checksum OK ($($actual.Substring(0, 12))...)"

Write-Host "[2/3] Extracting to $BinDir..."
Expand-CawTarball -tarball $tmpTar -destDir $BinDir
Remove-Item $tmpTar, $tmpSum -ErrorAction SilentlyContinue

Write-Host "[3/3] Updating user PATH..."
$pathUpdated = Add-CawToUserPath -dir $BinDir

$cawExe = Join-Path $BinDir 'caw.exe'
$installedVersion = (& $cawExe --version) 2>$null
if (-not $installedVersion) { $installedVersion = '(unknown)' }
Write-Host ""
Write-Host "Done."
Write-Host "  caw $installedVersion -> $cawExe"
if ($pathUpdated) {
    Write-Host ""
    Write-Host "Open a new terminal (or run: refreshenv) to pick up the PATH change."
}
