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
VERSION="0.9.0"
FLAVOR="cloud"
DOWNLOAD_CONFIG="true"
DOWNLOAD_SYMBOLS="true"
SETUP_ENV_VARS="true"

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
        --version)
            VERSION="$2"
            shift
            ;;
        --flavor)
            FLAVOR=$(echo "$2" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
            if [[ "$FLAVOR" != "edge" && "$FLAVOR" != "cloud" && "$FLAVOR" != "native" ]]; then
                echo "Invalid flavor: $FLAVOR. Allowed values are 'edge' / 'cloud' / 'native'."
                exit 1
            fi
            shift
            ;;
        --help)
            echo "Usage: install.sh [--version <version>] [--flavor <edge|cloud|native>] [--no-config] [--no-symbols] [--no-env-setup]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: install.sh [--version <version>] [--flavor <edge|cloud|native>] [--no-config] [--no-symbols] [--no-env-setup]"
            exit 1
            ;;
    esac
    shift
done

TENX_VERSION=$VERSION
TENX_FLAVOR="tenx-$FLAVOR"

DOWNLOAD_MODULES="true"

if [ "$FLAVOR" != "native" ]; then
	DOWNLOAD_MODULES="false"
fi

# Determine the OS type
if [ -f /etc/os-release ]; then
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
	aarch64)
		;;
	*)
		echo "Unsupported arch $ARCH"
		exit 1
		;;
esac

echo "Detected machine as $OS $VERSION_ID $ARCH"

# Validate native on supported os only
if [ "$FLAVOR" == "native" ]; then
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        echo "Unsupported operating system $OS for $FLAVOR"
        exit 1
    fi
fi

ARTIFACT_PATTERN=""
MODULES_FILE="tenx-modules-${TENX_VERSION}.tar.gz"
CONFIG_FILE="tenx-config-${TENX_VERSION}.tar.gz"
SYMBOLS_FILE="tenx-symbols-${TENX_VERSION}.10x.tar"
LICENSE_FILE="LICENSE.txt"
INSTALL_CMD=""

# Set artifact pattern based on OS, flavor, and architecture
if [ "$FLAVOR" == "native" ]; then
	if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_PATTERN="tenx-edge-${TENX_VERSION}-amd64-native"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_PATTERN="tenx-edge-${TENX_VERSION}-aarch64-native"
    fi
elif [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?amd64\.deb"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?arm64\.deb"
    fi
    INSTALL_CMD="apt-get install -y"
elif [[ "$OS" == "centos" || "$OS" == "fedora" || "$OS" == "rhel" ]]; then
    if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?x86_64\.rpm"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_PATTERN="${TENX_FLAVOR}[a-zA-Z0-9._-]*?${TENX_VERSION}[a-zA-Z0-9._-]*?aarch64\.rpm"
    fi

    if [ command -v dnf &> /dev/null ]; then
        INSTALL_CMD="dnf install -y"
    else
        INSTALL_CMD="yum install -y"
    fi
else
    echo "Unsupported operating system: $OS"
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

echo "Looking for a previous installation of the 10x engine..."
if [ -d "$TENX_HOME" ]; then
    echo ""
    echo "======================================================================================================"
    echo " You already have the 10x engine installed at - $TENX_HOME"
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

if [ "$SETUP_ENV_VARS" == "true" ]; then
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
ASSET_INFO=$(curl -s -H "Accept: application/vnd.github.v3+json" "$API_URL")

# Resolve main artifact URL
ARTIFACT_URL=$(echo "$ASSET_INFO" | grep -o '"browser_download_url":\s*"[^"]*"' | grep -Ei "$ARTIFACT_PATTERN" | sed 's/.*"browser_download_url":\s*"\([^"]*\)".*/\1/')
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
elif [ "$FLAVOR" == "native" ]; then
	echo ""
	echo "Installing native artifact..."
	TENX_FLAVOR="tenx-edge"
    mkdir -p "/opt/$TENX_FLAVOR/bin"
    mv "$TEMP_DIR/$ARTIFACT_FILE" "/opt/$TENX_FLAVOR/bin/$ARTIFACT_FILE"
    chmod +x "/opt/$TENX_FLAVOR/bin/$ARTIFACT_FILE"
    ln -s "/opt/$TENX_FLAVOR/bin/$ARTIFACT_FILE" "/opt/$TENX_FLAVOR/bin/$TENX_FLAVOR"
fi

ln -s "/opt/$TENX_FLAVOR/bin/$TENX_FLAVOR" "/opt/$TENX_FLAVOR/bin/tenx"

TENX_MODULES="/opt/$TENX_FLAVOR/lib/app/modules"

if [ "$DOWNLOAD_MODULES" == "true" ]; then
	MODULES_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$MODULES_FILE"
	MODULES_CURL="curl -f -L -o $TEMP_DIR/$MODULES_FILE $MODULES_URL"

	echo ""
	echo "Downloading 10x modules: $MODULES_CURL"
	$MODULES_CURL

	echo ""
	echo "Unpacking 10x modules into $TENX_MODULES"

	mkdir -p "$TENX_MODULES"
	tar -xzf "$TEMP_DIR/$MODULES_FILE" -C "$TENX_MODULES"
fi

TENX_CONFIG="/etc/tenx/config"

if [ "$DOWNLOAD_CONFIG" == "true" ]; then
	CONFIG_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$CONFIG_FILE"
	CONFIG_CURL="curl -f -L -o $TEMP_DIR/$CONFIG_FILE $CONFIG_URL"

	echo ""
	echo "Downloading 10x configuration: $CONFIG_CURL"
	$CONFIG_CURL

	echo ""
	echo "Unpacking 10x configuration into $TENX_CONFIG"

	mkdir -p "$TENX_CONFIG"
	tar -xzf "$TEMP_DIR/$CONFIG_FILE" -C "$TENX_CONFIG"
fi

TENX_SYMBOLS_PATH="/etc/tenx/symbols"

if [ "$DOWNLOAD_SYMBOLS" == "true" ]; then
	mkdir -p "$TENX_SYMBOLS_PATH"

	SYMBOLS_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$SYMBOLS_FILE"
	SYMBOLS_CURL="curl -f -L -o $TENX_SYMBOLS_PATH/$SYMBOLS_FILE $SYMBOLS_URL"

	echo ""
	echo "Downloading pre-compiled 10x symbols: $SYMBOLS_CURL"
	$SYMBOLS_CURL
fi

# Download and install LICENSE file
LICENSE_URL="https://github.com/$GITHUB_REPO/releases/download/$TENX_VERSION/$LICENSE_FILE"
LICENSE_CURL="curl -f -L -o /opt/$TENX_FLAVOR/LICENSE $LICENSE_URL"

echo ""
echo "Downloading license: $LICENSE_CURL"
$LICENSE_CURL

if [ "$SETUP_ENV_VARS" == "true" ]; then
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

# Clean up
rm -rf $TEMP_DIR

echo ""
echo "Installation complete."
echo ""
echo "Installed 10x engine into - /opt/$TENX_FLAVOR"
echo ""
echo "10x log file will be written into /var/log/tenx/"
echo ""

if [ "$SETUP_ENV_VARS" == "true" ]; then
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
else
	echo "Environment vars were not set."
	echo "It is recommended to set the following environment variables for convenient usage -"
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
	echo "Additionally, it's also recommended to add /opt/$TENX_FLAVOR/bin to the \$PATH"
	echo ""
fi

echo "Enjoy using 10x engine :)"
