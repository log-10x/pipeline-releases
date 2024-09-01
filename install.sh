#!/bin/bash

set -e

GITHUB_REPO="log-10x/pipeline-releases"
VERSION="0.4.1"
FLAVOR="cloud"

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift
            ;;
        --flavor)
            FLAVOR=$(echo "$2" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

            if [[ "$FLAVOR" != "edge" && "$FLAVOR" != "cloud" ]]; then
                echo "Invalid flavor: $FLAVOR. Allowed values are 'edge' / 'cloud'"
                exit 1
            fi
            shift
            ;;
        --help)
            echo "Usage: install.sh [--version <version>] [--flavor <edge|cloud>]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: install.sh [--version <version>] [--flavor <edge|cloud>]"
            exit 1
            ;;
    esac
    shift
done

L1X_VERSION=$VERSION
L1X_FLAVOR="log10x-$FLAVOR"

# Determine the OS type
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "Unable to detect operating system."
    exit 1
fi

INSTALL_CMD=""

# Create a temporary directory for the download
TEMP_DIR=$(mktemp -d)

# Set commands based on OS and flavor
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    PACKAGE_FILE="${L1X_FLAVOR}_$L1X_VERSION-1_amd64.deb"
    PACKAGE_URL="https://github.com/$GITHUB_REPO/releases/download/$L1X_VERSION/$PACKAGE_FILE"

    CURL_CMD="curl -f -L -o $TEMP_DIR/$PACKAGE_FILE $PACKAGE_URL"
    
    INSTALL_CMD="apt-get install -y $TEMP_DIR/$PACKAGE_FILE"

elif [[ "$OS" == "centos" || "$OS" == "fedora" || "$OS" == "rhel" ]]; then
    PACKAGE_FILE="$L1X_FLAVOR-$L1X_VERSION-1.x86_64.rpm"
    PACKAGE_URL="https://github.com/$GITHUB_REPO/releases/download/$L1X_VERSION/$PACKAGE_FILE"

    CURL_CMD="curl -f -L -o $TEMP_DIR/$PACKAGE_FILE $PACKAGE_URL"
    
    if [ command -v dnf &> /dev/null ]; then
        INSTALL_CMD="dnf install -y $TEMP_DIR/$PACKAGE_FILE"
    else
        INSTALL_CMD="yum install -y $TEMP_DIR/$PACKAGE_FILE"
    fi
else
    echo "Unsupported operating system: $OS"
    rm -rf $TEMP_DIR

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

echo "Going to download with: $CURL_CMD"
$CURL_CMD

if [ -n "$INSTALL_CMD" ]; then
    echo "Going to install with: $INSTALL_CMD"
    $INSTALL_CMD
fi

# Set up the environment variable
echo "export L1X_HOME=/opt/$L1X_FLAVOR" | sudo tee "/etc/profile.d/$L1X_FLAVOR.sh"
echo "export L1X_BIN=\$L1X_HOME/bin/$L1X_FLAVOR" | sudo tee -a "/etc/profile.d/$L1X_FLAVOR.sh"
echo "export PATH=\$L1X_HOME/bin:\$PATH" | sudo tee -a "/etc/profile.d/$L1X_FLAVOR.sh"

# Clean up
rm -rf $TEMP_DIR

echo "Installation complete."
echo ""
echo "Installed into L1X_HOME - /opt/$L1X_FLAVOR"
echo ""
echo "Set L1X_BIN as - /opt/$L1X_FLAVOR/bin/$L1X_FLAVOR"
echo ""
echo "Added bin - /opt/$L1X_FLAVOR/bin - to \$PATH"
echo ""
echo "Please restart your terminal or run 'source /etc/profile.d/$L1X_FLAVOR.sh' to apply the environment variables."
echo ""
echo "Enjoy using Log10x :)"
