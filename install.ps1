# Copyright 2025-2026 Log10x, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ---
#
# This installation script is open source under Apache 2.0.
# The Log10x software it installs is proprietary and requires a commercial
# license for production use. Visit https://log10x.com/pricing for details.
#
# Log10x Installer for Windows
# Usage: irm https://raw.githubusercontent.com/log-10x/pipeline-releases/main/install.ps1 | iex
#
# Options (set as environment variables before running):
#   $env:TENX_VERSION  = "1.0.0"   # specific version (default: latest)
#   $env:TENX_FLAVOR   = "cloud"   # cloud or edge (default: cloud)
#   $env:TENX_NO_CONFIG = "true"   # skip config download

$ErrorActionPreference = "Stop"

$Version = if ($env:TENX_VERSION) { $env:TENX_VERSION } else { "0.9.0" }
$Flavor = if ($env:TENX_FLAVOR) { $env:TENX_FLAVOR } else { "cloud" }
$SkipConfig = $env:TENX_NO_CONFIG -eq "true"
$Repo = "log-10x/pipeline-releases"

Write-Host ""
Write-Host "  Log10x Installer for Windows" -ForegroundColor Cyan
Write-Host "  Version: $Version | Flavor: $Flavor" -ForegroundColor DarkGray
Write-Host ""

# --- Resolve latest version if needed ---
if ($Version -eq "latest") {
    Write-Host "  Resolving latest version..." -ForegroundColor DarkGray
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    $Version = $release.tag_name
    Write-Host "  Latest version: $Version" -ForegroundColor Green
}

# --- Check for existing installation ---
$InstallDir = "C:\Program Files\tenx-$Flavor"
if (Test-Path $InstallDir) {
    Write-Host "  Existing installation found at $InstallDir" -ForegroundColor Yellow
    Write-Host "  Remove it first or use a different flavor." -ForegroundColor Yellow
    exit 1
}

# --- Find MSI artifact ---
Write-Host "  Fetching release artifacts..." -ForegroundColor DarkGray
$release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/tags/$Version"
$msiAsset = $release.assets | Where-Object { $_.name -match "tenx-$Flavor.*\.msi" } | Select-Object -First 1

if (-not $msiAsset) {
    Write-Host "  ERROR: No MSI artifact found for tenx-$Flavor version $Version" -ForegroundColor Red
    exit 1
}

# --- Create temp directory ---
$TempDir = Join-Path $env:TEMP "tenx-install-$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # --- Download MSI ---
    $msiPath = Join-Path $TempDir $msiAsset.name
    Write-Host "  Downloading $($msiAsset.name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $msiPath -UseBasicParsing

    # --- Install MSI silently ---
    Write-Host "  Installing..." -ForegroundColor Cyan
    $proc = Start-Process msiexec -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "  ERROR: MSI installation failed (exit code $($proc.ExitCode))" -ForegroundColor Red
        exit 1
    }

    # --- Download config ---
    if (-not $SkipConfig) {
        $ConfigDir = "C:\ProgramData\tenx"
        New-Item -ItemType Directory -Path "$ConfigDir\config" -Force | Out-Null
        New-Item -ItemType Directory -Path "$ConfigDir\symbols" -Force | Out-Null

        $configUrl = "https://github.com/$Repo/releases/download/$Version/tenx-config-$Version.tar.gz"
        $configPath = Join-Path $TempDir "tenx-config.tar.gz"
        Write-Host "  Downloading configuration..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $configUrl -OutFile $configPath -UseBasicParsing
        tar -xzf $configPath -C "$ConfigDir\config"

        $symbolsUrl = "https://github.com/$Repo/releases/download/$Version/tenx-symbols-$Version.10x.tar"
        $symbolsPath = Join-Path $TempDir "tenx-symbols.tar"
        Write-Host "  Downloading symbol libraries..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $symbolsUrl -OutFile $symbolsPath -UseBasicParsing
        Copy-Item $symbolsPath "$ConfigDir\symbols\"
    }

    # --- Set environment variables (machine-level) ---
    Write-Host "  Configuring environment variables..." -ForegroundColor Cyan
    [Environment]::SetEnvironmentVariable("TENX_HOME", $InstallDir, "Machine")
    [Environment]::SetEnvironmentVariable("TENX_BIN", "$InstallDir\tenx-$Flavor.exe", "Machine")
    [Environment]::SetEnvironmentVariable("TENX_MODULES", "$InstallDir\lib\app\modules", "Machine")
    [Environment]::SetEnvironmentVariable("TENX_CONFIG", "C:\ProgramData\tenx\config", "Machine")
    [Environment]::SetEnvironmentVariable("TENX_SYMBOLS_PATH", "C:\ProgramData\tenx\symbols", "Machine")

    # Add to PATH if not already present
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$InstallDir", "Machine")
    }

    Write-Host ""
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Install path:  $InstallDir" -ForegroundColor White
    Write-Host "  Config path:   C:\ProgramData\tenx" -ForegroundColor White
    Write-Host ""
    Write-Host "  Open a NEW terminal window, then run:" -ForegroundColor Yellow
    Write-Host "    tenx --version" -ForegroundColor White
    Write-Host ""

} finally {
    # --- Cleanup ---
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
}
