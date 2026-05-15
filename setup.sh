#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Suppress unused color warnings for ShellCheck
# shellcheck disable=SC2034
{
    _RED=$RED
    _GREEN=$GREEN
    _YELLOW=$YELLOW
    _BLUE=$BLUE
    _NC=$NC
}

printf "%b" "${BLUE}"
echo "   _____ _               _                 _____ _     _  __ _   "
echo "  / ____| |             | |               / ____| |   (_)/ _| |  "
echo " | (___ | |__   __ _  __| | _____      __| (___ | |__  _| |_| |_ "
echo "  \___ \| '_ \ / _\` |/ _\` |/ _ \ \ /\ / /\___ \| '_ \| |  _| __|"
echo "  ____) | | | | (_| | (_| | (_) \ V  V / ____) | | | | | | | |_ "
echo " |_____/|_| |_|\__,_|\___/ \_/\_/ |_____/|_| |_|_|_|  \__|"
echo "                                                                "
printf "                 %bV 2.0 - ShadowShift - Installer%b\n" "${YELLOW}" "${NC}"
printf "%b   ============================================================%b\n" "${BLUE}" "${NC}"
printf "   %bAuthor: SyntaxSouq | https://github.com/SyntaxSouq %b\n" "${YELLOW}" "${NC}"
printf "%b   ============================================================%b\n\n" "${BLUE}" "${NC}"

set -e

# Project Name
PROJECT_NAME="ShadowShift"
# shellcheck disable=SC2034
_PROJECT_NAME=$PROJECT_NAME
SERVICE_FILE="shadowshift.service"
ROTATOR_SCRIPT="shadowshift-rotator.sh"

# OS Detection
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="$ID"
        OS_VERSION="$VERSION_ID"
    elif command -v lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(lsb_release -sr)
    else
        DISTRO="unknown"
        OS_VERSION="unknown"
    fi
    printf "%b[*] Detected OS: %s %s%b\n" "${BLUE}" "$DISTRO" "$OS_VERSION" "${NC}"
}

# Dependency Installation
install_deps() {
    printf "%b[*] Installing required packages for %s...%b\n" "${BLUE}" "$DISTRO" "${NC}"
    case "$DISTRO" in
        arch|manjaro|blackarch|endeavouros)
            sudo pacman -Syu --noconfirm curl tor jq xxd netcat
            TOR_GROUP="tor"
            ;;
        debian|ubuntu|kali|parrot|zorin|linuxmint|pop)
            sudo apt update && sudo apt install -y curl tor jq xxd netcat-openbsd
            TOR_GROUP="debian-tor"
            ;;
        fedora|centos|rhel|amzn)
            sudo dnf install -y curl tor jq xxd nc
            TOR_GROUP="tor"
            ;;
        opensuse*|suse)
            sudo zypper install -y curl tor jq xxd netcat-openbsd
            TOR_GROUP="tor"
            ;;
        *)
            printf "%b[!] Unknown distribution. Please ensure curl, tor, jq, xxd, and nc are installed manually.%b\n" "${YELLOW}" "${NC}"
            TOR_GROUP="tor"
            ;;
    esac
}

detect_os
install_deps

if ! getent group "$TOR_GROUP" >/dev/null; then
    printf "%b[*] Group '%s' not found, creating it...%b\n" "${BLUE}" "$TOR_GROUP" "${NC}"
    sudo groupadd "$TOR_GROUP"
fi

if ! groups "$USER" | grep -q "$TOR_GROUP"; then
    printf "%b[*] Adding user '%s' to group '%s'...%b\n" "${BLUE}" "$USER" "$TOR_GROUP" "${NC}"
    sudo usermod -aG "$TOR_GROUP" "$USER"
else
    printf "%b[✓] User '%s' is already a member of group '%s'.%b\n" "${GREEN}" "$USER" "$TOR_GROUP" "${NC}"
fi

printf "%b[*] Configuring Tor...%b\n" "${BLUE}" "${NC}"
TORRC_FILE="/etc/tor/torrc"
NEEDS_UPDATE=0

grep -q "^ControlPort 9051" "$TORRC_FILE" || NEEDS_UPDATE=1
grep -q "^CookieAuthentication 1" "$TORRC_FILE" || NEEDS_UPDATE=1
grep -q "^CookieAuthFileGroupReadable 1" "$TORRC_FILE" || NEEDS_UPDATE=1

if [[ "$NEEDS_UPDATE" -eq 1 ]]; then
    printf "%b[*] Updating torrc with required ControlPort settings...%b\n" "${BLUE}" "${NC}"
    {
        echo ""
        echo "# Added by ShadowShift automation script"
        echo "ControlPort 9051"
        echo "CookieAuthentication 1"
        echo "CookieAuthFileGroupReadable 1"
    } | sudo tee -a "$TORRC_FILE" > /dev/null
    sudo systemctl restart tor
else
    printf "%b[✓] torrc already configured correctly. Skipping update.%b\n" "${GREEN}" "${NC}"
fi

read -r -p "Enter Tor IP change interval (seconds, default 10): " TIME_INTERVAL
TIME_INTERVAL=${TIME_INTERVAL:-10}

printf "%b[*] Setting up systemd service with interval: %s sec...%b\n" "${BLUE}" "$TIME_INTERVAL" "${NC}"
sed -i "s/RestartSec=.*/RestartSec=$TIME_INTERVAL/" "$SERVICE_FILE"

printf "%b[*] Deploying files...%b\n" "${BLUE}" "${NC}"
INSTALL_DIR="/usr/local/bin"
sudo cp "$ROTATOR_SCRIPT" "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/$ROTATOR_SCRIPT"
sed -i "s|^ExecStart=.*|ExecStart=${INSTALL_DIR}/${ROTATOR_SCRIPT}|" "$SERVICE_FILE"
sudo cp "$SERVICE_FILE" /etc/systemd/system/

printf "%b[*] Enabling and starting service...%b\n" "${BLUE}" "${NC}"
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_FILE"
sudo systemctl enable --now tor.service

if command -v gsettings >/dev/null; then
    printf "%b[*] Setting system-wide GNOME proxy to Tor (127.0.0.1:9050)...%b\n" "${BLUE}" "${NC}"
    USER_ID=$(id -u "$USER")
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"
    gsettings set org.gnome.system.proxy mode 'manual'
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
    gsettings set org.gnome.system.proxy.socks port 9050
    gsettings set org.gnome.system.proxy.http host '127.0.0.1'
    gsettings set org.gnome.system.proxy.http port 9050
    gsettings set org.gnome.system.proxy.https host '127.0.0.1'
    gsettings set org.gnome.system.proxy.https port 9050
    printf "%b[✔] System-wide proxy configured!%b\n" "${GREEN}" "${NC}"
fi

printf "%b[✔] Deployment complete! Tor IP will change every %s seconds.%b\n" "${GREEN}" "$TIME_INTERVAL" "${NC}"
