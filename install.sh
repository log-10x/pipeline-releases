#!/bin/bash

set -e

GITHUB_REPO="log-10x/pipeline-releases"
VERSION="0.11.10"
FLAVOR="cloud"
DOWNLOAD_CONFIG="true"
SETUP_ENV_VARS="true"

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
    	--no-config)
			DOWNLOAD_CONFIG="false"
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
            echo "Usage: install.sh [--version <version>] [--flavor <edge|cloud|native>] [--no-config] [--no-env-setup]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: install.sh [--version <version>] [--flavor <edge|cloud|native>] [--no-config] [--no-env-setup]"
            exit 1
            ;;
    esac
    shift
done

L1X_VERSION=$VERSION
L1X_FLAVOR="log10x-$FLAVOR"

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

#Validate native on supported os only
if [ "$FLAVOR" == "native" ]; then
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        echo "Unsupported operating system $OS for $FLAVOR"
        exit 1
    fi
fi

ARTIFACT_FILE=""
MODULES_FILE="log10x-modules-$L1X_VERSION.tar.gz"
CONFIG_FILE="log10x-config-$L1X_VERSION.tar.gz"
INSTALL_CMD=""

# Set commands based on OS and flavor
if [ "$FLAVOR" == "native" ]; then
	if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_FILE="log10x-edge-$L1X_VERSION-amd64-native"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_FILE="log10x-edge-$L1X_VERSION-aarch64-native"
    fi

elif [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_FILE="${L1X_FLAVOR}_$L1X_VERSION-1_amd64.deb"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_FILE="${L1X_FLAVOR}_$L1X_VERSION-1_arm64.deb"
    fi

    INSTALL_CMD="apt-get install -y"

elif [[ "$OS" == "centos" || "$OS" == "fedora" || "$OS" == "rhel" ]]; then
    if [[ "$ARCH" == "x86_64" ]]; then
    	ARTIFACT_FILE="$L1X_FLAVOR-$L1X_VERSION-1.x86_64.rpm"
    elif [[ "$ARCH" == "aarch64" ]]; then
    	ARTIFACT_FILE="$L1X_FLAVOR-$L1X_VERSION-1.aarch64.rpm"
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

echo "Looking for a previous installation of Log10x..."
if [ -d "$L1X_HOME" ]; then
    echo ""
    echo "======================================================================================================"
    echo " You already have Log10x installed at - $L1X_HOME"
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
	    echo " Please install sudo on your system using your favourite package manager."
	    echo ""
	    echo " Restart after installing sudo."
	    echo "======================================================================================================"
	    echo ""
	    exit 1
	fi
fi

ARTIFACT_URL="https://github.com/$GITHUB_REPO/releases/download/$L1X_VERSION/$ARTIFACT_FILE"

# Create a temporary directory for the download
TEMP_DIR=$(mktemp -d)

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

	L1X_FLAVOR="log10x-edge"

    mkdir -p "/opt/$L1X_FLAVOR/bin"
    mv "$TEMP_DIR/$ARTIFACT_FILE" "/opt/$L1X_FLAVOR/bin/$ARTIFACT_FILE"
    chmod +x "/opt/$L1X_FLAVOR/bin/$ARTIFACT_FILE"
    ln -s "/opt/$L1X_FLAVOR/bin/$ARTIFACT_FILE" "/opt/$L1X_FLAVOR/bin/$L1X_FLAVOR"
fi

ln -s "/opt/$L1X_FLAVOR/bin/$L1X_FLAVOR" "/opt/$L1X_FLAVOR/bin/log10x"

L1X_MODULES="/opt/$L1X_FLAVOR/lib/app/modules"

if [ "$DOWNLOAD_MODULES" == "true" ]; then
	MODULES_URL="https://github.com/$GITHUB_REPO/releases/download/$L1X_VERSION/$MODULES_FILE"
	MODULES_CURL="curl -f -L -o $TEMP_DIR/$MODULES_FILE $MODULES_URL"

	echo ""
	echo "Downloading Log10x modules: $MODULES_CURL"
	$MODULES_CURL

	echo ""
	echo "Unpacking Log10x modules into $L1X_MODULES"

	mkdir -p "$L1X_MODULES"
	tar -xzf "$TEMP_DIR/$MODULES_FILE" -C "$L1X_MODULES"
fi

L1X_CONFIG="/etc/log10x/config"

if [ "$DOWNLOAD_CONFIG" == "true" ]; then
	CONFIG_URL="https://github.com/$GITHUB_REPO/releases/download/$L1X_VERSION/$CONFIG_FILE"
	CONFIG_CURL="curl -f -L -o $TEMP_DIR/$CONFIG_FILE $CONFIG_URL"

	echo ""
	echo "Downloading Log10x configuration: $CONFIG_CURL"
	$CONFIG_CURL

	echo ""
	echo "Unpacking Log10x configuration into $L1X_CONFIG"

	mkdir -p "$L1X_CONFIG"
	tar -xzf "$TEMP_DIR/$CONFIG_FILE" -C "$L1X_CONFIG"
fi

if [ "$SETUP_ENV_VARS" == "true" ]; then
	# Set up the environment variable
	echo ""
	echo "Setting up environment variables"
	echo "export L1X_HOME=/opt/$L1X_FLAVOR" | sudo tee "/etc/profile.d/log10x.sh"
	echo "export L1X_BIN=\$L1X_HOME/bin/$L1X_FLAVOR" | sudo tee -a "/etc/profile.d/log10x.sh"
	echo "export PATH=\$L1X_HOME/bin:\$PATH" | sudo tee -a "/etc/profile.d/log10x.sh"

	if [ "$DOWNLOAD_MODULES" == "true" ]; then
		echo "export L1X_MODULES=$L1X_MODULES" | sudo tee -a "/etc/profile.d/log10x.sh"
	fi

	if [ "$DOWNLOAD_CONFIG" == "true" ]; then
		echo "export L1X_CONFIG=$L1X_CONFIG" | sudo tee -a "/etc/profile.d/log10x.sh"
	fi
fi

# Clean up
rm -rf $TEMP_DIR

echo ""
echo "Installation complete."
echo ""
echo "Installed into - /opt/$L1X_FLAVOR"
echo ""
echo "Log10x log file is written into /var/log/l1x/"
echo ""

if [ "$SETUP_ENV_VARS" == "true" ]; then
	echo "Configured the following environment variables:"
	echo "    L1X_HOME - /opt/$L1X_FLAVOR"
	echo "    L1X_BIN -  /opt/$L1X_FLAVOR/bin/$L1X_FLAVOR"

	if [ "$DOWNLOAD_CONFIG" == "true" ]; then
	echo "    L1X_CONFIG - $L1X_CONFIG"
	fi

	if [ "$DOWNLOAD_MODULES" == "true" ]; then
	echo "    L1X_MODULES - $L1X_MODULES"
	fi

	echo ""
	echo "Added bin - /opt/$L1X_FLAVOR/bin - to \$PATH"
	echo ""

	echo "Please restart your terminal or run 'source /etc/profile.d/log10x.sh' to apply the environment variables."
	echo ""
else
	echo "Environment vars where not set."
	echo "It is recommended to set the following environment variables for convenient usage -"
	echo "    L1X_HOME - /opt/$L1X_FLAVOR"
	echo "    L1X_BIN -  /opt/$L1X_FLAVOR/bin/$L1X_FLAVOR"
	if [ "$DOWNLOAD_MODULES" == "true" ]; then
	echo "    L1X_MODULES - $L1X_MODULES"
	fi
	if [ "$DOWNLOAD_CONFIG" == "true" ]; then
	echo "    L1X_CONFIG - $L1X_CONFIG"
	fi
	echo ""
	echo "Additionally, it's also recommended to add /opt/$L1X_FLAVOR/bin to the \$PATH"
	echo ""
fi

echo "Enjoy using Log10x :)"
