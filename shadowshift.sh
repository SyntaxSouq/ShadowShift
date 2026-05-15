#!/bin/bash

# Project Metadata
PROJECT_NAME="ShadowShift"
VERSION="2.0"
AUTHOR="SyntaxSouq"
REPO="https://github.com/SyntaxSouq"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
LOG_FILE="/var/log/shadowshift.log"
[[ ! -f "$LOG_FILE" ]] && sudo touch "$LOG_FILE" && sudo chmod 666 "$LOG_FILE"

log() {
    local type="$1"
    local msg="$2"
    local color="$NC"
    local prefix=""
    case "$type" in
        "info")    color="$BLUE"   ; prefix="[*]" ;;
        "success") color="$GREEN"  ; prefix="[+]" ;;
        "warn")    color="$YELLOW" ; prefix="[!]" ;;
        "error")   color="$RED"    ; prefix="[x]" ;;
    esac
    printf "%b%s %s%b\n" "$color" "$prefix" "$msg" "$NC"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$type] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

show_banner() {
    clear
    printf "%b" "${BLUE}"
    echo "   _____ _               _                 _____ _     _  __ _   "
    echo "  / ____| |             | |               / ____| |   (_)/ _| |  "
    echo " | (___ | |__   __ _  __| | _____      __| (___ | |__  _| |_| |_ "
    echo "  \___ \| '_ \ / _\` |/ _\` |/ _ \ \ /\ / /\___ \| '_ \| |  _| __|"
    echo "  ____) | | | | (_| | (_| | (_) \ V  V / ____) | | | | | | | |_ "
    echo " |_____/|_| |_|\__,_|\__,_|\___/ \_/\_/ |_____/|_| |_|_|_|  \__|"
    echo "                                                                "
    printf "                 %bV %s - %s%b\n" "${YELLOW}" "$VERSION" "$PROJECT_NAME" "${NC}"
    printf "%b   ============================================================%b\n" "${BLUE}" "${NC}"
    printf "   %bAuthor: %s | %s %b\n" "${YELLOW}" "$AUTHOR" "$REPO" "${NC}"
    printf "%b   ============================================================%b\n\n" "${BLUE}" "${NC}"
}

set -e

# Ensure we're root
if [[ "$UID" -ne 0 ]]; then
    log "error" "Administrative privileges required. Please run with sudo."
    exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
USER_ID=$(id -u "$REAL_USER")

# Check for required packages
check_deps() {
    local deps=("curl" "tor" "jq" "xxd" "nc")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "warn" "Missing dependencies: ${missing[*]}. Attempting to install..."
        
        # OS Detection
        local DISTRO="unknown"
        if [[ -f /etc/os-release ]]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            DISTRO="$ID"
        fi

        case "$DISTRO" in
            debian|ubuntu|kali|parrot|zorin|linuxmint|pop)
                apt update && apt install -y "${missing[@]}"
                ;;
            arch|manjaro|blackarch|endeavouros)
                pacman -Sy --noconfirm "${missing[@]}"
                ;;
            fedora|centos|rhel)
                dnf install -y "${missing[@]}"
                ;;
            *)
                log "error" "Automatic installation not supported for $DISTRO. Please install manually: ${missing[*]}"
                exit 1
                ;;
        esac
    fi
}

enable_proxy() {
    log "info" "Configuring system-wide proxy settings..."
    
    # Identify Desktop Environment
    local DE
    DE=$(sudo -u "$REAL_USER" printenv XDG_CURRENT_DESKTOP | tr '[:upper:]' '[:lower:]')
    
    # GNOME, Cinnamon, MATE, XFCE (some versions)
    if [[ "$DE" == *"gnome"* || "$DE" == *"cinnamon"* || "$DE" == *"mate"* || "$DE" == *"xfce"* ]] && command -v gsettings >/dev/null; then
        log "info" "Detected GNOME-compatible environment ($DE). Configuring via gsettings..."
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" gsettings set org.gnome.system.proxy mode 'manual'
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" gsettings set org.gnome.system.proxy.socks port 9050
    fi

    # KDE Plasma
    if [[ "$DE" == *"kde"* ]] && command -v kwriteconfig5 >/dev/null; then
        log "info" "Detected KDE environment. Configuring via kwriteconfig5..."
        sudo -u "$REAL_USER" kwriteconfig5 --file kresourcerc --group "Proxy Settings" --key ProxyType 1
        sudo -u "$REAL_USER" kwriteconfig5 --file kresourcerc --group "Proxy Settings" --key socksProxy "socks://127.0.0.1 9050"
    fi

    # Set environment variables for CLI tools
    log "info" "Setting proxy environment variables for current session..."
    export http_proxy="socks5://127.0.0.1:9050"
    export https_proxy="socks5://127.0.0.1:9050"
    export all_proxy="socks5://127.0.0.1:9050"
    
    log "success" "Proxy configuration applied (127.0.0.1:9050)"
}

disable_proxy() {
    log "info" "Reverting proxy settings..."
    
    if command -v gsettings >/dev/null; then
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" gsettings set org.gnome.system.proxy mode 'none'
    fi

    if command -v kwriteconfig5 >/dev/null; then
        sudo -u "$REAL_USER" kwriteconfig5 --file kresourcerc --group "Proxy Settings" --key ProxyType 0
    fi

    unset http_proxy https_proxy all_proxy
    log "success" "Proxy settings restored to default"
}

cleanup() {
    log "info" "Shutting down ShadowShift..."
    disable_proxy
    exit 0
}

trap cleanup SIGINT SIGTERM

ipchanger() {
    local cookie_path=""
    for path in /run/tor/control.authcookie /var/run/tor/control.authcookie /var/lib/tor/control.authcookie; do
        if [[ -f "$path" ]]; then
            cookie_path="$path"
            break
        fi
    done

    if [[ -z "$cookie_path" ]]; then
        log "error" "Tor auth cookie not found. Is Tor running?"
        return 1
    fi

    local cookie
    cookie=$(sudo xxd -ps "$cookie_path" | tr -d '\n')
    local response
    response=$(printf 'AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n' "$cookie" | nc 127.0.0.1 9051 2>/dev/null || true)

    if echo "$response" | grep -q '250 OK'; then
        sleep 5
        local ip
        ip=$(curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip | jq -r .IP 2>/dev/null || echo "Unknown")
        log "success" "New Tor IP: $ip"
    else
        log "error" "Tor control command failed."
    fi
}

# Main Execution
show_banner
check_deps

# Argument handling
case "$1" in
    "--stop")
        disable_proxy
        log "success" "Proxy disabled. Exiting."
        exit 0
        ;;
    "--status")
        ip=$(curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip | jq -r .IP 2>/dev/null || echo "Not using Tor")
        log "info" "Current IP: $ip"
        exit 0
        ;;
esac

enable_proxy

if [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; then
    interval="$1"
else
    read -r -p "Enter IP change interval in seconds (default 10): " interval
    interval=${interval:-10}
fi

log "info" "Starting rotation every $interval seconds..."

while true; do
    ipchanger
    sleep "$interval"
done
