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
#   $env:TENX_VERSION  = "1.0.0"         # specific version (default: latest)
#   $env:TENX_FLAVOR   = "runtime-jvm"   # runtime-jvm (default) or compiler. See FLAVORS.md.
#   $env:TENX_NO_CONFIG = "true"         # skip config download
#   $env:TENX_PRINT_ARTIFACT = "true"    # resolve the MSI, print it, install nothing
#
# Windows gets two of the three flavors:
#
#                 | JVM           | native
#   compile+run   | compiler      | -- impossible, compiling loads classes dynamically
#   run only      | runtime-jvm   | -- NOT BUILT for Windows
#
# There is no Windows native image, so 'runtime' is not installable here and
# 'runtime-jvm' is the default: it is the runtime, executed on a bundled JRE.

$ErrorActionPreference = "Stop"

$Version = if ($env:TENX_VERSION) { $env:TENX_VERSION } else { "1.1.50" }
# Default is runtime-jvm, matching install.sh, whose default is the runtime.
# Most people installing 10x want to RUN it; 'generate'/compile/link is the
# smaller audience and is what 'compiler' is for.
$RequestedFlavor = if ($env:TENX_FLAVOR) { "$env:TENX_FLAVOR".Trim().ToLowerInvariant() } else { "runtime-jvm" }
$SkipConfig = $env:TENX_NO_CONFIG -eq "true"
$PrintArtifact = $env:TENX_PRINT_ARTIFACT -eq "true"
$Repo = "log-10x/pipeline-releases"

# --- Validate the flavor, and map it to a package id ---
#
# Two things happen here, and the ordering matters: nothing downstream may see a
# value that did not come out of this switch.
#
# 1. VALIDATION. Before 48cf776 this script had no flavor check at all, and the
#    unvalidated $env:TENX_FLAVOR reached three places, one of them a .NET regex:
#
#      $InstallDir = "C:\Program Files\tenx-$Flavor"     (a directory name)
#      $_.name -match "tenx-$Flavor.*\.msi"              (a REGEX, not a token)
#      TENX_BIN = "$InstallDir\tenx-$Flavor.exe"         (machine-wide, permanent)
#
#    -match is case-insensitive and unanchored, so the flavor was a pattern, and
#    `Select-Object -First 1` took whatever it hit. Against the real asset list
#    of release 1.1.37, TENX_FLAVOR=e resolved tenx-edge-1.1.37.msi: the edge MSI
#    into "C:\Program Files\tenx-e", with a machine-wide TENX_BIN pointing at
#    tenx-e.exe, a file that never exists. The install reported success.
#    TENX_FLAVOR='cloud|edge' resolved an .rpm and would have handed it to
#    msiexec /i.
#
#    `switch` on string labels is exact, case-insensitive comparison -- not a
#    pattern match -- so it closes that off the same way the `-notcontains`
#    literal-array gate it replaces did. Every path out of it either assigns
#    $PackageId from a literal or exits 1. It runs before either
#    Invoke-RestMethod, so a bad flavor still costs zero network.
#
# 2. MAPPING. $PackageId is the release-asset and on-disk token, and it is
#    deliberately NOT the flavor name: the MSI is tenx-cloud-<v>.msi and it
#    installs to "C:\Program Files\tenx-cloud" whatever the flag is called.
#    See FLAVORS.md.
switch ($RequestedFlavor) {
    "compiler" { $Flavor = "compiler"; $PackageId = "cloud"; break }
    "cloud"    {
        Write-Host "  Note: TENX_FLAVOR=cloud is the old name for 'compiler'." -ForegroundColor DarkGray
        $Flavor = "compiler"; $PackageId = "cloud"
        break
    }
    "runtime-jvm" { $Flavor = "runtime-jvm"; $PackageId = "edge"; break }
    "edge" {
        # This was a hard error, and that error is the bug this branch fixes.
        #
        # 'edge' was retired as a flavor NAME when its musl justification turned
        # out to be false. Retiring the name was right. What went with it by
        # accident was the only runtime Windows has: the tenx-edge MSI never
        # stopped being published, and Windows has no native image, so after the
        # rename this script could install the compiler and nothing else. Anyone
        # who wanted to just RUN 10x on Windows was told their flavor was invalid.
        Write-Host "  Note: TENX_FLAVOR=edge is the old name for 'runtime-jvm'." -ForegroundColor DarkGray
        $Flavor = "runtime-jvm"; $PackageId = "edge"
        break
    }
    { $_ -in "runtime", "native" } {
        # Deliberately NOT folded into the default 'invalid flavor' case. The
        # flavor is spelled correctly and exists; the ARTIFACT does not, on this
        # platform only. Telling a Windows user their spelling is invalid sends
        # them to re-read the docs, where 'runtime' is exactly what they will
        # find, because it is the default everywhere else.
        Write-Host "  ERROR: the native runtime is not built for Windows." -ForegroundColor Red
        Write-Host ""  -ForegroundColor Red
        Write-Host "  'runtime' is a real flavor and it is the default on Linux and macOS," -ForegroundColor Red
        Write-Host "  but it is a GraalVM native image and no Windows one is produced. The" -ForegroundColor Red
        Write-Host "  release carries no tenx-*-windows-*-native asset." -ForegroundColor Red
        Write-Host ""  -ForegroundColor Red
        Write-Host "  Use TENX_FLAVOR=runtime-jvm. Same capabilities -- reporter, receiver," -ForegroundColor Yellow
        Write-Host "  retriever, MCP server, CLI -- run on a bundled JRE, shipped as an MSI." -ForegroundColor Yellow
        Write-Host "  It is the default for this installer." -ForegroundColor Yellow
        exit 1
    }
    default {
        Write-Host "  ERROR: invalid TENX_FLAVOR '$RequestedFlavor'. Allowed: compiler, runtime-jvm" -ForegroundColor Red
        exit 1
    }
}

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
# The MSI decides this path, and it is named for the package id, not the
# flavor. C:\Program Files\tenx-cloud is what tenx-cloud-<v>.msi creates.
#
# runtime-jvm and compiler have DIFFERENT prefixes here (tenx-edge, tenx-cloud),
# unlike Linux where the native runtime and runtime-jvm share /opt/tenx-edge. So
# on Windows the two can coexist, and this guard only ever fires on reinstalling
# the same flavor.
#
# TENX_PRINT_ARTIFACT skips the guard: it resolves an asset, it does not care
# what is on disk, and refusing to answer because something is installed would
# make it useless for asserting the mapping on a machine that has 10x.
$InstallDir = "C:\Program Files\tenx-$PackageId"
if (-not $PrintArtifact -and (Test-Path $InstallDir)) {
    Write-Host "  Existing installation found at $InstallDir" -ForegroundColor Yellow
    Write-Host "  Remove it first or use a different flavor." -ForegroundColor Yellow
    exit 1
}

# --- Find MSI artifact ---
Write-Host "  Fetching release artifacts..." -ForegroundColor DarkGray
$release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/tags/$Version"
# Defence in depth: $PackageId can only be a literal assigned by the switch
# above, so escaping it changes nothing today. It is here so that adding a
# package id containing a regex metacharacter cannot quietly turn this back into
# a pattern match.
$PackageIdPattern = [regex]::Escape($PackageId)
$msiAsset = $release.assets | Where-Object { $_.name -match "tenx-$PackageIdPattern.*\.msi" } | Select-Object -First 1

if (-not $msiAsset) {
    Write-Host "  ERROR: No MSI artifact found for tenx-$PackageId version $Version" -ForegroundColor Red
    exit 1
}

# --- TENX_PRINT_ARTIFACT: resolve the MSI, print it, install nothing ---
#
# The counterpart of install.sh --print-artifact, and it exists for the same
# reason: so the flavor->asset mapping is asserted against a real release rather
# than assumed. It also makes this script testable off Windows -- everything
# above is flavor validation and a GitHub API read, both of which run anywhere
# pwsh runs, so `docker run mcr.microsoft.com/powershell` can check that
# runtime-jvm resolves tenx-edge-<v>.msi and compiler resolves tenx-cloud-<v>.msi.
# Nothing below this point can run outside Windows: msiexec, "C:\Program Files",
# and machine-scope [Environment]::SetEnvironmentVariable are all Windows-only.
if ($PrintArtifact) {
    Write-Host "  flavor:     $Flavor"
    Write-Host "  package id: $PackageId"
    Write-Host "  version:    $Version"
    Write-Host "  artifact:   $($msiAsset.name)"
    Write-Host "  url:        $($msiAsset.browser_download_url)"
    exit 0
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

    # --- Verify the MSI laid down what the environment is about to point at ---
    #
    # TENX_BIN is composed here while the file it names comes from the MSI.
    # Writing it machine-wide without checking is how a successful-looking
    # install ends up with a permanent pointer to a file that does not exist.
    #
    # The exe is named for the PACKAGE ID, not the flavor: tenx-cloud-<v>.msi
    # lays down tenx-cloud.exe. Composing it from $Flavor here would make this
    # guard fire on every correct install of --flavor compiler.
    $TenxExe = "$InstallDir\tenx-$PackageId.exe"
    if (-not (Test-Path $TenxExe)) {
        Write-Host ""
        Write-Host "  ERROR: The MSI installed, but $TenxExe is missing." -ForegroundColor Red
        Write-Host "  Package id '$PackageId' does not match the contents of $($msiAsset.name)." -ForegroundColor Red
        Write-Host "  Environment variables were NOT set." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    # --- Set environment variables (machine-level) ---
    Write-Host "  Configuring environment variables..." -ForegroundColor Cyan
    [Environment]::SetEnvironmentVariable("TENX_HOME", $InstallDir, "Machine")
    [Environment]::SetEnvironmentVariable("TENX_BIN", $TenxExe, "Machine")
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
