#!/bin/bash
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
# license for production use. See https://log10x.com/pricing

set -e

GITHUB_REPO="log-10x/pipeline-releases"
VERSION="1.1.47"
FLAVOR="runtime"
DOWNLOAD_CONFIG="true"
DOWNLOAD_SYMBOLS="true"
SETUP_ENV_VARS="true"
PRINT_ARTIFACT="false"

USAGE="Usage: install.sh [--version <version>] [--flavor <compiler|runtime|runtime-jvm>] [--no-config] [--no-symbols] [--no-env-setup] [--print-artifact]

Flavors are two axes, not one list: what the build can DO (run only, or also
compile) and how it is EXECUTED (native image, or on a JVM).

                | JVM           | native
  compile+run   | compiler      | -- impossible, compiling loads classes dynamically
  run only      | runtime-jvm   | runtime

  runtime      (default) the native binary: reporter, receiver, retriever, MCP, CLI
  runtime-jvm  the same capabilities, run on a bundled JRE. Ships as .deb/.rpm
               (Linux), .msi (Windows), .dmg (macOS). Use it where no native
               binary is built -- that is Windows -- or where a JVM is wanted.
  compiler     everything runtime does, plus 'generate', compile, link. Ships as
               .deb/.rpm (Linux), .msi (Windows), .dmg (macOS). On macOS install
               it with 'brew install --cask log-10x/tap/log10x-cloud'.

Deprecated spellings, still accepted:
  cloud  -> compiler
  native -> runtime
  edge   -> runtime-jvm"

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
    	--no-config)
			DOWNLOAD_CONFIG="false"
			;;
		--no-symbols)
			DOWNLOAD_SYMBOLS="false"
			;;
		--no-env-setup)
			SETUP_ENV_VARS="false"
			;;
		--print-artifact)
			PRINT_ARTIFACT="true"
			;;
        --version)
            VERSION="$2"
            shift
            ;;
        --flavor)
            REQUESTED_FLAVOR=$(echo "$2" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
            case "$REQUESTED_FLAVOR" in
                compiler|runtime|runtime-jvm)
                    FLAVOR="$REQUESTED_FLAVOR"
                    ;;
                cloud)
                    # Old name. Kept working because this script is fetched from
                    # main by every docker-images build and by every published
                    # install one-liner; a hard break here breaks builds that
                    # nobody edited.
                    echo "Note: --flavor cloud is the old name for 'compiler'. Use --flavor compiler." >&2
                    FLAVOR="compiler"
                    ;;
                native)
                    echo "Note: --flavor native is the old name for 'runtime'. Use --flavor runtime." >&2
                    FLAVOR="runtime"
                    ;;
                edge)
                    # 'edge' was made a hard error when the jpackage JIT build was
                    # retired as a FLAVOR. Retiring the name was right; retiring the
                    # artifact was not, because it never stopped shipping -- every
                    # release still carries tenx-edge-<v>.{deb,rpm,msi,dmg} -- and it
                    # is the ONLY runtime that exists on Windows, which has no native
                    # binary. The hard error therefore left Windows able to install
                    # nothing but the compiler. So 'edge' maps, it does not fail.
                    echo "Note: --flavor edge is the old name for 'runtime-jvm'. Use --flavor runtime-jvm." >&2
                    FLAVOR="runtime-jvm"
                    ;;
                *)
                    echo "Invalid flavor: $REQUESTED_FLAVOR. Allowed values are 'compiler' / 'runtime' / 'runtime-jvm'."
                    exit 1
                    ;;
            esac
            shift
            ;;
        --help)
            echo "$USAGE"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "$USAGE"
            exit 1
            ;;
    esac
    shift
done

TENX_VERSION=$VERSION

# PACKAGE_ID is the RELEASE-ASSET AND ON-DISK token, and it is deliberately NOT
# the flavor name.
#
# Renaming the flavor flag is free. Renaming these strings is not, because they
# are baked into things this script cannot reach:
#
#   - every release asset already published (1.0.x through 1.1.37 all carry
#     tenx-cloud-* / tenx-edge-*), and --version accepts any of them
#   - the install prefix /opt/tenx-cloud and /opt/tenx-edge, which the jpackage
#     .deb/.rpm creates and which docker-images bakes into TENX_HOME/TENX_BIN
#   - the binary inside the package, /opt/tenx-cloud/bin/tenx-cloud
#   - the Homebrew cask/formula URLs in log-10x/homebrew-tap
#
# So: flavor names are the vocabulary users type, PACKAGE_ID is the wire format.
# See FLAVORS.md for the full mapping across all five vocabularies.
#
# runtime and runtime-jvm share PACKAGE_ID 'edge': they are the same capability
# set, packaged twice from the same release. The native binary is
# tenx-edge-<v>-<arch>-native; the JVM one is tenx-edge-<v>.{deb,rpm,msi,dmg}.
# One id, two asset shapes -- which is why the branch below still tests $FLAVOR,
# not $PACKAGE_ID, to pick the pattern. Both land in /opt/tenx-edge on Linux,
# which is what docker-images bakes into TENX_HOME.
case "$FLAVOR" in
	compiler)    PACKAGE_ID="cloud" ;;
	runtime)     PACKAGE_ID="edge" ;;
	runtime-jvm) PACKAGE_ID="edge" ;;
esac

TENX_FLAVOR="tenx-$PACKAGE_ID"

DOWNLOAD_MODULES="true"

# Only the native runtime is a bare binary with nothing alongside it, so only it
# needs tenx-modules-<v>.tar.gz fetched separately. The jpackage packages --
# compiler AND runtime-jvm -- carry their modules inside the .deb/.rpm, at
# /opt/<pkg>/lib/app/modules. Downloading over that would replace what the
# package manager owns with an untracked copy.
if [ "$FLAVOR" != "runtime" ]; then
	DOWNLOAD_MODULES="false"
fi

# Determine the OS type
UNAME_S="$(uname -s)"
if [ "$UNAME_S" = "Darwin" ]; then
    OS="macos"
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "Unable to detect operating system."
    exit 1
fi

ARCH="$(uname -m)"

case $ARCH in
	x86_64)
		;;
	aarch64|arm64)
		ARCH="aarch64"  # normalize
		;;
	*)
		echo "Unsupported arch $ARCH"
		exit 1
		;;
esac

echo "Detected machine as $OS $VERSION_ID $ARCH"

# Validate the runtime by what it actually requires, not by distro name.
#
# This used to be a three-name allowlist -- ubuntu, debian, macos -- which
# rejected every RPM-family distro by name while the binary ran on them fine.
# Since the runtime is the DEFAULT flavor, a RHEL/Rocky/Alma/Amazon Linux user
# following the documented one-liner was told "Unsupported operating system"
# for software that works on their machine.
#
# The real requirement is glibc >= 2.17. The Linux binary is built in Oracle
# Linux 8 specifically so its floor is low; gating on distro name threw that
# away. Verified by running tenx-edge-1.1.20 --version in each container:
#
#   rockylinux:9  OK    almalinux:9      OK    amazonlinux:2023  OK
#   oraclelinux:9 OK    fedora:40        OK    opensuse/leap:15  OK
#   debian:12     OK    ubuntu:22.04     OK    ubuntu:20.04      OK
#
# ubuntu:20.04 is the useful control: it ships glibc 2.31, so it runs the
# current binary and would NOT have run 1.1.6, which required 2.34.
if [ "$FLAVOR" == "runtime" ] && [ "$OS" != "macos" ]; then

	GLIBC_MIN_MAJOR=2
	GLIBC_MIN_MINOR=17

	# getconf is in glibc itself; ldd is the fallback. Neither present means a
	# non-glibc libc (Alpine/musl), where this binary genuinely will not run.
	DETECTED_GLIBC="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
	if [ -z "$DETECTED_GLIBC" ]; then
		# `|| true` is load-bearing: this script runs under `set -e`, and on a
		# musl system ldd prints "musl libc (x86_64)" with no version, so grep
		# matches nothing and exits 1. Without it the script dies HERE, silently,
		# before reaching the message below that explains what went wrong.
		# Verified on alpine:3 -- exit 1, no output past "Detected machine as".
		DETECTED_GLIBC="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
	fi

	if [ -z "$DETECTED_GLIBC" ]; then
		echo "Could not detect glibc on $OS. The runtime build requires glibc ${GLIBC_MIN_MAJOR}.${GLIBC_MIN_MINOR} or newer."
		echo "This looks like a musl system such as Alpine. No 10x build runs here:"
		echo "  - runtime      is linked against glibc"
		echo "  - runtime-jvm  ships only as .deb / .rpm, which Alpine does not install"
		echo "  - compiler     ships only as .deb / .rpm, same"
		echo "Run 10x in a glibc container instead, e.g. the log10x/edge-10x image."
		exit 1
	fi

	GLIBC_MAJOR="${DETECTED_GLIBC%%.*}"
	GLIBC_MINOR="${DETECTED_GLIBC#*.}"
	GLIBC_MINOR="${GLIBC_MINOR%%.*}"

	if [ "$GLIBC_MAJOR" -lt "$GLIBC_MIN_MAJOR" ] || \
	   { [ "$GLIBC_MAJOR" -eq "$GLIBC_MIN_MAJOR" ] && [ "$GLIBC_MINOR" -lt "$GLIBC_MIN_MINOR" ]; }; then
		echo "glibc $DETECTED_GLIBC is older than the ${GLIBC_MIN_MAJOR}.${GLIBC_MIN_MINOR} the runtime build requires."
		echo "Run 10x in a container instead, e.g. the log10x/edge-10x image."
		echo "(--flavor runtime-jvm is the same capability set on a bundled JRE, from"
		echo " .deb/.rpm, and --flavor compiler adds generate/compile/link. Both are"
		echo " jpackage builds with their own glibc floor, not validated below"
		echo " ${GLIBC_MIN_MAJOR}.${GLIBC_MIN_MINOR}.)"
		exit 1
	fi

	echo "Detected glibc $DETECTED_GLIBC (runtime requires ${GLIBC_MIN_MAJOR}.${GLIBC_MIN_MINOR}+)"
fi

ARTIFACT_PATTERN=""
MACOS_DMG="false"
MODULES_FILE="tenx-modules-${TENX_VERSION}.tar.gz"
CONFIG_FILE="tenx-config-${TENX_VERSION}.tar.gz"
SYMBOLS_FILE="tenx-symbols-${TENX_VERSION}.10x.tar"
LICENSE_FILE="LICENSE.txt"
INSTALL_CMD=""

# Set artifact pattern based on OS, flavor, and architecture.
#
# The literal `tenx-edge-` / `${TENX_FLAVOR}` tokens below are PACKAGE_ID, not
# the flavor name. They must keep matching the assets that log-10x/engine's
# release job actually uploads. If those asset names ever change, everything in
# the "Lockstep" list in FLAVORS.md changes with them, in the same release.
if [ "$FLAVOR" == "runtime" ]; then
	if [ "$OS" == "macos" ]; then
		if [[ "$ARCH" == "x86_64" ]]; then
			ARTIFACT_PATTERN="tenx-edge-${TENX_VERSION}-macos-amd64-native"
		else
			ARTIFACT_PATTERN="tenx-edge-${TENX_VERSION}-macos-arm64-native"
		fi
	elif [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_PATTERN="tenx-edge-${TENX_VERSION}-amd64-native"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_PATTERN="tenx-edge-${TENX_VERSION}-aarch64-native"
    fi
elif [ "$OS" == "macos" ]; then
	# --flavor compiler and --flavor runtime-jvm on macOS. Both are DMGs.
	#
	# Neither has a macOS artifact this script can install. They ship as
	# tenx-<id>-<v>.dmg / tenx-<id>-<v>-intel.dmg, a disk image carrying an .app
	# bundle -- not a bare binary like the native runtime, and not a package a
	# package manager takes. Before this branch existed the chain below fell
	# through to "Unsupported operating system: macos", which is false twice
	# over: macOS is supported, and the flag the docs hand every reader is the
	# one that hit it.
	#
	# The pattern is still set rather than exiting here, so --print-artifact can
	# resolve the DMG. For the compiler that asset is what log-10x/homebrew-tap's
	# cask points at, and it is the one whose name-drift fails SILENTLY today:
	# the tap job in log-10x/engine `find`s for it and exits 0 when nothing
	# matches. Being able to assert it against a real release is worth more than
	# an early exit; the install itself is refused a few lines below, after
	# --print-artifact.
	#
	# -intel is a suffix, so `${TENX_FLAVOR}-${TENX_VERSION}\.dmg` matches the
	# arm image only. Anchoring matters here: the looser [a-zA-Z0-9._-]*? form
	# used by the deb/rpm branches would match both DMGs from either arch, and
	# with PACKAGE_ID=edge it would also match tenx-edge-<v>-macos-arm64-native.
	if [[ "$ARCH" == "x86_64" ]]; then
		ARTIFACT_PATTERN="${TENX_FLAVOR}-${TENX_VERSION}-intel\.dmg"
	else
		ARTIFACT_PATTERN="${TENX_FLAVOR}-${TENX_VERSION}\.dmg"
	fi
	MACOS_DMG="true"
# The two branches below pick a PACKAGE FAMILY -- .deb or .rpm -- and they read
# ID plus ID_LIKE, not ID alone.
#
# ID alone was a four-name allowlist: ubuntu, debian, centos, fedora, rhel. That
# is the same distro-name gate 43d547a already removed from the native runtime,
# left behind here because the runtime was the only flavor most people reached
# for. runtime-jvm changes that: it exists precisely to be the .rpm/.deb runtime,
# so the gate is now on the new flavor's main path. Verified before this change:
#
#   docker run --rm rockylinux:9 ... --flavor runtime-jvm --print-artifact
#   -> ID="rocky" ID_LIKE="rhel centos fedora"
#   -> Unsupported operating system: rocky      exit 1
#
# rocky, almalinux, oraclelinux and amazonlinux all take .rpm and all declare
# rhel or fedora in ID_LIKE. /etc/os-release is sourced above, so ID_LIKE is
# already in scope.
elif [[ " $OS $ID_LIKE " == *" ubuntu "* || " $OS $ID_LIKE " == *" debian "* ]]; then
    if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?amd64\.deb"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?arm64\.deb"
    fi
    INSTALL_CMD="apt-get install -y"
elif [[ " $OS $ID_LIKE " == *" rhel "* || " $OS $ID_LIKE " == *" fedora "* || " $OS $ID_LIKE " == *" centos "* ]]; then
    if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?x86_64\.rpm"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?aarch64\.rpm"
    fi

    # `if [ command -v dnf &> /dev/null ]` -- the previous form -- is `[` with the
    # three arguments `command` `-v` `dnf`, so bash reads `-v` as a binary
    # operator, prints "binary operator expected" into the discarded stream, and
    # returns 2. The test was therefore ALWAYS false and this always picked yum.
    # It worked only because yum is a dnf symlink on every distro that gets here.
    if command -v dnf > /dev/null 2>&1; then
        INSTALL_CMD="dnf install -y"
    else
        INSTALL_CMD="yum install -y"
    fi
else
    echo "Unsupported operating system: $OS"
    echo "The .deb / .rpm flavors (compiler, runtime-jvm) are selected by package"
    echo "family, read from ID and ID_LIKE in /etc/os-release. This system reports"
    echo "ID=$OS ID_LIKE=${ID_LIKE:-<unset>}, which is neither debian- nor rhel-family."
    exit 1
fi

# --print-artifact: resolve the asset this invocation WOULD download, print it,
# and stop. Installs nothing.
#
# This exists so the flavor->asset mapping can be asserted in CI against a real
# release instead of being assumed. The failure mode it targets is the one that
# already bit the Homebrew tap job in log-10x/engine: a name-pattern that stops
# matching, a lookup that returns empty, and a pipeline that reports success
# while shipping nothing. Here an empty resolution exits 1.
# Fetch a release from the GitHub API.
#
# Authenticate when a token is available. The unauthenticated limit is 60
# requests per hour PER IP, and CI runners share IPs: the forwarder publish
# fans out ~10 parallel image builds, each calling this twice, so the limit is
# exhausted and GitHub answers 403. The old code passed that body straight to
# grep, found no browser_download_url, and reported "No asset found matching
# pattern", which reads as a missing artifact and sent people looking at the
# release instead of the rate limit. A different job failed on each re-run,
# which is the signature of a shared quota rather than a bad pattern.
tenx_fetch_release() {
	local url="$1" body http
	local -a auth=()
	local tok="${TENX_GITHUB_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
	[ -n "$tok" ] && auth=(-H "Authorization: Bearer $tok")

	body=$(curl -s -w '\n%{http_code}' -H "Accept: application/vnd.github.v3+json" "${auth[@]}" "$url")
	http="${body##*$'\n'}"
	body="${body%$'\n'*}"

	if [ "$http" != "200" ]; then
		echo "Error: GitHub API returned HTTP $http for $url" >&2
		case "$http" in
			403|429)
				echo "  Rate limited. The unauthenticated limit is 60 requests/hour per IP." >&2
				echo "  Set TENX_GITHUB_TOKEN (or GITHUB_TOKEN) to raise it, or retry later." >&2
				;;
			404) echo "  No such release. Check the version." >&2 ;;
		esac
		return 1
	fi
	printf '%s' "$body"
}

if [ "$PRINT_ARTIFACT" == "true" ]; then
	API_URL="https://api.github.com/repos/$GITHUB_REPO/releases/tags/$TENX_VERSION"
	ASSET_INFO=$(tenx_fetch_release "$API_URL") || exit 1
	RESOLVED=$(echo "$ASSET_INFO" | grep -o '"browser_download_url":\s*"[^"]*"' | grep -Ei "$ARTIFACT_PATTERN" | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]*)".*/\1/')

	echo "flavor:     $FLAVOR"
	echo "package id: $PACKAGE_ID"
	echo "os/arch:    $OS $ARCH"
	echo "version:    $TENX_VERSION"
	echo "pattern:    $ARTIFACT_PATTERN"

	if [ -z "$RESOLVED" ]; then
		echo "artifact:   NONE -- no asset in release $TENX_VERSION matches this pattern"
		exit 1
	fi

	echo "artifact:   $(basename "$RESOLVED")"
	echo "url:        $RESOLVED"
	exit 0
fi

# The macOS compiler and runtime-jvm resolve to a DMG (above), and stop here.
#
# Mounting it and copying the .app somewhere is not the whole job. The Homebrew
# cask also downloads config and symbols, writes the /usr/local/bin/tenx
# launcher that sets TENX_CONFIG and TENX_SYMBOLS_PATH before exec'ing into the
# bundle, and removes all of it on uninstall. This script installs its own macOS
# runtime to /usr/local/bin/tenx (see the runtime branch below), so a second
# unmanaged copy here would contend for that exact path with no uninstall on
# either side. One managed macOS install path is the whole point.
if [ "$MACOS_DMG" == "true" ]; then
	# ARTIFACT_PATTERN is a regex; the '.' is escaped for grep -E. Strip the
	# backslash so the line reads as the file name it is naming.
	DMG_NAME="${ARTIFACT_PATTERN//\\/}"
	if [ "$FLAVOR" == "compiler" ]; then
		echo "The compiler flavor is installed with Homebrew on macOS, not by this script."
		echo ""
		echo "  brew install --cask log-10x/tap/log10x-cloud"
		echo ""
		echo "The cask installs tenx-cloud.app plus config and symbols, and puts a"
		echo "'tenx' launcher on PATH. It is the same DMG this script would fetch:"
		echo "  $DMG_NAME"
	else
		# runtime-jvm on macOS. The DMG exists in every release and
		# --print-artifact resolves it, but there is no cask for it and no
		# reason to reach for it: macOS is one of the platforms where the
		# native runtime IS built, and it is the same capability set without
		# the JVM. runtime-jvm earns its place on Windows, where no native
		# binary is published at all.
		echo "The runtime-jvm flavor ships on macOS as a .dmg, which this script does not install."
		echo ""
		echo "  $DMG_NAME"
		echo ""
		echo "On macOS you almost certainly want the native runtime instead. Same"
		echo "capabilities, no JVM, and this script installs it:"
		echo "  install.sh --flavor runtime"
		echo ""
		echo "runtime-jvm exists for platforms with no native build -- that is Windows,"
		echo "via install.ps1."
	fi
	exit 1
fi

echo " .----------------. .----------------. .----------------. .----------------. .----------------. .----------------. "
echo "| .--------------. | .--------------. | .--------------. | .--------------. | .--------------. | .--------------. |"
echo "| |   _____      | | |     ____     | | |    ______    | | |     __       | | |     ____     | | |  ____  ____  | |"
echo "| |  |_   _|     | | |   .'    '.   | | |  .' ___  |   | | |    /  |      | | |   .'    '.   | | | |_  _||_  _| | |"
echo "| |    | |       | | |  /  .--.  \  | | | / .'   \_|   | | |    '| |      | | |  |  .--.  |  | | |   \ \  / /   | |"
echo "| |    | |   _   | | |  | |    | |  | | | | |    ____  | | |     | |      | | |  | |    | |  | | |    > '' <    | |"
echo "| |   _| |__/ |  | | |  \  '--'  /  | | | \ '.___]  _| | | |    _| |_     | | |  |  '--'  |  | | |  _/ /''\ \_  | |"
echo "| |  |________|  | | |   '.____.'   | | |  '._____.'   | | |   |_____|    | | |   '.____.'   | | | |____||____| | |"
echo "| |              | | |              | | |              | | |              | | |              | | |              | |"
echo "| '--------------' | '--------------' | '--------------' | '--------------' | '--------------' | '--------------' |"
echo " '----------------' '----------------' '----------------' '----------------' '----------------' '----------------' "

# Where THIS run will install. The guard below used to test $TENX_HOME, which
# this script never assigns anywhere -- `grep -n '^[[:space:]]*TENX_HOME=' `
# returned nothing. The only thing that ever exports it is /etc/profile.d/tenx.sh,
# written at the END of a previous successful install, and the documented entry
# point is `curl ... | sh`, which is not a login shell and does not source
# /etc/profile.d. So on the path every user actually takes, $TENX_HOME was empty,
# `[ -d "" ]` was false, and the guard never fired: the re-install ran to the
# `ln -s` calls below and died on symlinks that already existed, several minutes
# and one package download later.
#
# The install destination is not one path, so it is computed rather than guessed:
#   runtime + macos   ->  /usr/local             (binary moved to bin/tenx)
#   runtime + linux   ->  /opt/tenx-edge         (PACKAGE_ID is edge)
#   runtime-jvm       ->  /opt/tenx-edge         (deb/rpm; PACKAGE_ID is edge)
#   compiler          ->  /opt/$TENX_FLAVOR      (deb/rpm; PACKAGE_ID is cloud)
# runtime-jvm and runtime therefore SHARE /opt/tenx-edge, which is correct and
# is what the jpackage .deb creates. They cannot be installed side by side, and
# the guard below is what says so instead of failing later on `ln -s`.
# Every one of those paths ends by creating a `tenx` launcher in bin, so that is
# what gets tested -- a directory alone is not evidence of an install, and for
# macOS /usr/local always exists.
#
# The flavor name tested here is the POST-rename one. 48cf776 wrote `native`,
# which was correct on the vocabulary of its day; leaving it would have silently
# sent runtime+macOS down the else branch to /opt/tenx-edge, a path that install
# never creates on macOS, so the guard would have gone dead again on exactly the
# platform it is hardest to notice on.
if [ "$FLAVOR" == "runtime" ]; then
	if [ "$OS" == "macos" ]; then
		TENX_HOME="/usr/local"
	else
		TENX_HOME="/opt/tenx-edge"
	fi
else
	TENX_HOME="/opt/$TENX_FLAVOR"
fi

echo "Looking for a previous installation of the 10x engine..."
if [ -e "$TENX_HOME/bin/tenx" ] || [ -L "$TENX_HOME/bin/tenx" ]; then
    echo ""
    echo "======================================================================================================"
    echo " You already have the 10x engine installed at - $TENX_HOME/bin/tenx"
    echo ""
    # What to remove is NOT $TENX_HOME on every platform. On Linux, TENX_HOME is
    # /opt/tenx-edge or /opt/tenx-cloud and the whole prefix belongs to 10x. On
    # macOS it is /usr/local, a shared Homebrew prefix -- "Remove /usr/local"
    # would take every brew-installed program on the machine with it. There the
    # install is one file, and if it came from the tap, brew owns it.
    if [ "$OS" == "macos" ]; then
        if [ -L "$TENX_HOME/bin/tenx" ]; then
            echo " That is a symlink, so it was most likely installed by Homebrew:"
            echo "   brew uninstall log10x            (the runtime formula)"
            echo "   brew uninstall --cask log10x-cloud"
            echo ""
        fi
        echo " To reinstall with this script, remove that one file and re-run:"
        echo "   rm $TENX_HOME/bin/tenx"
        echo ""
        echo " Do NOT remove $TENX_HOME itself. It is the shared Homebrew prefix."
    else
        echo " Remove $TENX_HOME and re-run this script to reinstall."
    fi
    echo "======================================================================================================"
    echo ""
    exit 0
fi

echo "Looking for curl..."
if ! command -v curl > /dev/null; then
    echo "Not found."
    echo ""
    echo "======================================================================================================"
    echo " Please install curl on your system using your favourite package manager."
    echo ""
    echo " Restart after installing curl."
    echo "======================================================================================================"
    echo ""
    exit 1
fi

if [ "$SETUP_ENV_VARS" == "true" ] && [ "$OS" != "macos" ]; then
	echo "Looking for sudo..."
	if ! command -v sudo > /dev/null; then
	    echo "Not found."
	    echo ""
	    echo "======================================================================================================"
	    echo " sudo is required to set up environment variables in /etc/profile.d/tenx.sh"
	    echo ""
	    echo " Options:"
	    echo "   1. Install sudo and restart the installation"
	    echo "   2. Run with --no-env-setup to skip environment variable setup (no sudo needed)"
	    echo "      You will need to manually configure TENX_HOME, TENX_BIN, and PATH"
	    echo "======================================================================================================"
	    echo ""
	    exit 1
	fi
fi


# Create a temporary directory for the download
TEMP_DIR=$(mktemp -d)

# Query GitHub API for release assets
API_URL="https://api.github.com/repos/$GITHUB_REPO/releases/tags/$TENX_VERSION"
ASSET_INFO=$(tenx_fetch_release "$API_URL") || exit 1

# Resolve main artifact URL
ARTIFACT_URL=$(echo "$ASSET_INFO" | grep -o '"browser_download_url":\s*"[^"]*"' | grep -Ei "$ARTIFACT_PATTERN" | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]*)".*/\1/')
if [ -z "$ARTIFACT_URL" ]; then
    echo "Error: No asset found matching pattern '$ARTIFACT_PATTERN' for release '$TENX_VERSION'"
    exit 1
fi
ARTIFACT_FILE=$(basename "$ARTIFACT_URL")

CURL_CMD="curl -f -L -o $TEMP_DIR/$ARTIFACT_FILE $ARTIFACT_URL"
echo ""
echo "Downloading artifact: $CURL_CMD"
$CURL_CMD

if [ -n "$INSTALL_CMD" ]; then
	echo ""
    echo "Installing artifact with: $INSTALL_CMD $TEMP_DIR/$ARTIFACT_FILE"
    echo ""
    $INSTALL_CMD $TEMP_DIR/$ARTIFACT_FILE
elif [ "$FLAVOR" == "runtime" ]; then
	echo ""
	echo "Installing runtime artifact..."
	# TENX_FLAVOR is already tenx-edge here (PACKAGE_ID=edge for the runtime).
	# The prefix stays /opt/tenx-edge: docker-images bakes it into TENX_HOME and
	# TENX_BIN in five Dockerfiles, and every published container carries it.
	if [ "$OS" == "macos" ]; then
		INSTALL_DIR="/usr/local"
		mkdir -p "$INSTALL_DIR/bin"
		mkdir -p "$INSTALL_DIR/etc/tenx/config"
		mkdir -p "$INSTALL_DIR/etc/tenx/symbols"
		mv "$TEMP_DIR/$ARTIFACT_FILE" "$INSTALL_DIR/bin/tenx"
		chmod +x "$INSTALL_DIR/bin/tenx"
	else
		mkdir -p "/opt/$TENX_FLAVOR/bin"
		mv "$TEMP_DIR/$ARTIFACT_FILE" "/opt/$TENX_FLAVOR/bin/$ARTIFACT_FILE"
		chmod +x "/opt/$TENX_FLAVOR/bin/$ARTIFACT_FILE"
		ln -s "/opt/$TENX_FLAVOR/bin/$ARTIFACT_FILE" "/opt/$TENX_FLAVOR/bin/$TENX_FLAVOR"
	fi
fi

if [ "$OS" != "macos" ]; then
	ln -s "/opt/$TENX_FLAVOR/bin/$TENX_FLAVOR" "/opt/$TENX_FLAVOR/bin/tenx"
fi

if [ "$OS" == "macos" ]; then
	TENX_MODULES="/usr/local/lib/tenx/modules"
else
	TENX_MODULES="/opt/$TENX_FLAVOR/lib/app/modules"
fi

if [ "$DOWNLOAD_MODULES" == "true" ]; then
	MODULES_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$MODULES_FILE"
	MODULES_CURL="curl -f -L -o $TEMP_DIR/$MODULES_FILE $MODULES_URL"

	echo ""
	echo "Downloading 10x modules: $MODULES_CURL"
	$MODULES_CURL

	echo ""
	echo "Unpacking 10x modules into $TENX_MODULES"

	mkdir -p "$TENX_MODULES"
	# --no-same-owner: the tarballs carry uid/gid 1001 from the build machine, and as
	# root tar would restore that ownership verbatim. That leaves the installed tree
	# owned by whatever local account happens to hold 1001, and in container images it
	# makes Filebeat refuse its own config with "must be owned by the user identifier".
	tar --no-same-owner -xzf "$TEMP_DIR/$MODULES_FILE" -C "$TENX_MODULES"
fi

if [ "$OS" == "macos" ]; then
	TENX_CONFIG="/usr/local/etc/tenx/config"
else
	TENX_CONFIG="/etc/tenx/config"
fi

if [ "$DOWNLOAD_CONFIG" == "true" ]; then
	CONFIG_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$CONFIG_FILE"
	CONFIG_CURL="curl -f -L -o $TEMP_DIR/$CONFIG_FILE $CONFIG_URL"

	echo ""
	echo "Downloading 10x configuration: $CONFIG_CURL"
	$CONFIG_CURL

	echo ""
	echo "Unpacking 10x configuration into $TENX_CONFIG"

	mkdir -p "$TENX_CONFIG"
	tar --no-same-owner -xzf "$TEMP_DIR/$CONFIG_FILE" -C "$TENX_CONFIG"
fi

if [ "$OS" == "macos" ]; then
	TENX_SYMBOLS_PATH="/usr/local/etc/tenx/symbols"
else
	TENX_SYMBOLS_PATH="/etc/tenx/symbols"
fi

if [ "$DOWNLOAD_SYMBOLS" == "true" ]; then
	mkdir -p "$TENX_SYMBOLS_PATH"

	SYMBOLS_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$SYMBOLS_FILE"
	SYMBOLS_CURL="curl -f -L -o $TENX_SYMBOLS_PATH/$SYMBOLS_FILE $SYMBOLS_URL"

	echo ""
	echo "Downloading pre-compiled 10x symbols: $SYMBOLS_CURL"
	$SYMBOLS_CURL
fi

# Download and install LICENSE file
if [ "$OS" == "macos" ]; then
	LICENSE_DEST="/usr/local/etc/tenx/LICENSE"
else
	LICENSE_DEST="/opt/$TENX_FLAVOR/LICENSE"
fi
LICENSE_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$LICENSE_FILE"
LICENSE_CURL="curl -f -L -o $LICENSE_DEST $LICENSE_URL"

echo ""
echo "Downloading license: $LICENSE_CURL"
$LICENSE_CURL

if [ "$SETUP_ENV_VARS" == "true" ]; then
	if [ "$OS" == "macos" ]; then
		echo ""
		echo "The tenx binary is installed at /usr/local/bin/tenx (already on PATH)."
		echo "Set these in your shell profile if needed:"
		if [ "$DOWNLOAD_MODULES" == "true" ]; then
			echo "  export TENX_MODULES=$TENX_MODULES"
		fi
		if [ "$DOWNLOAD_CONFIG" == "true" ]; then
			echo "  export TENX_CONFIG=$TENX_CONFIG"
		fi
		if [ "$DOWNLOAD_SYMBOLS" == "true" ]; then
			echo "  export TENX_SYMBOLS_PATH=$TENX_SYMBOLS_PATH"
		fi
	else
		# Set up the environment variable
		echo ""
		echo "Setting up environment variables"
		echo "export TENX_HOME=/opt/$TENX_FLAVOR" | sudo tee "/etc/profile.d/tenx.sh"
		echo "export TENX_BIN=\$TENX_HOME/bin/$TENX_FLAVOR" | sudo tee -a "/etc/profile.d/tenx.sh"
		echo "export PATH=\$TENX_HOME/bin:\$PATH" | sudo tee -a "/etc/profile.d/tenx.sh"
		if [ "$DOWNLOAD_MODULES" == "true" ]; then
			echo "export TENX_MODULES=$TENX_MODULES" | sudo tee -a "/etc/profile.d/tenx.sh"
		fi
		if [ "$DOWNLOAD_CONFIG" == "true" ]; then
			echo "export TENX_CONFIG=$TENX_CONFIG" | sudo tee -a "/etc/profile.d/tenx.sh"
		fi
		if [ "$DOWNLOAD_SYMBOLS" == "true" ]; then
			echo "export TENX_SYMBOLS_PATH=$TENX_SYMBOLS_PATH" | sudo tee -a "/etc/profile.d/tenx.sh"
		fi
	fi
fi

# Clean up
rm -rf $TEMP_DIR

echo ""
echo "Installation complete."
echo ""
if [ "$OS" == "macos" ]; then
	echo "Installed 10x engine into - /usr/local/bin/tenx"
else
	echo "Installed 10x engine into - /opt/$TENX_FLAVOR"
fi
echo ""
echo "10x log file will be written into /var/log/tenx/"
echo ""

if [ "$SETUP_ENV_VARS" == "true" ]; then
	if [ "$OS" != "macos" ]; then
		echo "Configured the following environment variables:"
		echo "    TENX_HOME - /opt/$TENX_FLAVOR"
		echo "    TENX_BIN -  /opt/$TENX_FLAVOR/bin/$TENX_FLAVOR"
		if [ "$DOWNLOAD_MODULES" == "true" ]; then
			echo "    TENX_MODULES - $TENX_MODULES"
		fi
		if [ "$DOWNLOAD_CONFIG" == "true" ]; then
			echo "    TENX_CONFIG - $TENX_CONFIG"
		fi
		if [ "$DOWNLOAD_SYMBOLS" == "true" ]; then
			echo "    TENX_SYMBOLS_PATH - $TENX_SYMBOLS_PATH"
		fi
		echo ""
		echo "Added bin - /opt/$TENX_FLAVOR/bin - to \$PATH"
		echo ""
		echo "Please restart your terminal or run 'source /etc/profile.d/tenx.sh' to apply the environment variables."
		echo ""
	fi
else
	echo "Environment vars were not set."
	echo "It is recommended to set the following environment variables for convenient usage -"
	if [ "$OS" != "macos" ]; then
		echo "    TENX_HOME - /opt/$TENX_FLAVOR"
		echo "    TENX_BIN -  /opt/$TENX_FLAVOR/bin/$TENX_FLAVOR"
	fi
	if [ "$DOWNLOAD_MODULES" == "true" ]; then
		echo "    TENX_MODULES - $TENX_MODULES"
	fi
	if [ "$DOWNLOAD_CONFIG" == "true" ]; then
		echo "    TENX_CONFIG - $TENX_CONFIG"
	fi
	if [ "$DOWNLOAD_SYMBOLS" == "true" ]; then
		echo "    TENX_SYMBOLS_PATH - $TENX_SYMBOLS_PATH"
	fi
	echo ""
	if [ "$OS" != "macos" ]; then
		echo "Additionally, it's also recommended to add /opt/$TENX_FLAVOR/bin to the \$PATH"
	fi
	echo ""
fi

echo "Enjoy using 10x engine :)"
