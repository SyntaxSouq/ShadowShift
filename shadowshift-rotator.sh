#!/bin/bash
# ShadowShift Rotator Script
# Author: SyntaxSouq
# Repository: https://github.com/SyntaxSouq

set -e

LOG_FILE="/var/log/shadowshift.log"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" | sudo tee -a "$LOG_FILE" > /dev/null
    printf "%s - %s\n" "$timestamp" "$1"
}

# Ensure log file exists and is writable
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

COOKIE_PATH=""
for path in /run/tor/control.authcookie /var/run/tor/control.authcookie /var/lib/tor/control.authcookie; do
    if [[ -f "$path" ]]; then
        COOKIE_PATH="$path"
        break
    fi
done

if [[ -z "$COOKIE_PATH" ]]; then
    log "Error: Tor auth cookie not found. Is Tor running?"
    exit 1
fi

COOKIE=$(sudo xxd -ps "$COOKIE_PATH" | tr -d '\n')
RESPONSE=$(printf 'AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n' "$COOKIE" | nc 127.0.0.1 9051 2>/dev/null || true)

if ! echo "$RESPONSE" | grep -q '250 OK'; then
    log "Error: Tor control authentication failed or SIGNAL NEWNYM did not execute."
    log "Response: $RESPONSE"
    exit 1
fi

sleep 5

IP=$(curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip | jq -r .IP 2>/dev/null || echo "Unknown")
log "Success: New Tor IP: $IP"
