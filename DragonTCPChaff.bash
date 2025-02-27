#!/bin/bash

# DragonTCPChaff - Automated Junk Traffic Generator and Broadcaster
# Version 1.0
# Description: Captures real traffic, fuzzes it, and continuously broadcasts
#              over Yggdrasil (or other mesh network). Includes self-monitoring
#              for file size and restarts capture+fuzz cycle automatically.
# CLI docs:
#   --capture   Delete cached capture file.

DEBUG=1

if [ $DEBUG -ge 1 ]; then
    set -euxo pipefail
fi

# Configuration
INTERFACE="wlo1"               # Capture interface
CAPTURE_FILE="real_traffic.pcap" # Raw capture
FUZZED_FILE="fuzzed_traffic.bin" # Fuzzed output

KILO=1024
MEGA=$((KILO * 1024))
GIGA=$((MEGA * 1024))
MIN_FILE_SIZE=$((10 * MEGA)) # minimum file size needed for operation

YGG_PEER_IP="[YGG_PEER_IP_HERE]" # Replace with your mesh peer
YGG_PORT=9999                     # UDP port for junk traffic

# Check persistence - keep running if killed unexpectedly
function persistence_check() {
    while true; do
        if ! pgrep -f "$0" > /dev/null; then
            exec "$0" "$@"
        fi
        sleep 30
    done &
}

# Start persistence thread
persistence_check "$@"

# Capture real traffic
function capture_traffic() {
    # make sure our interface actually exists.
    if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
        echo "[!] Interface $INTERFACE does not exist. Exiting."
        exit 1
    fi

    echo "[+] Capturing real traffic on $INTERFACE..."
    tcpdump -i "$INTERFACE" -w "$CAPTURE_FILE" -G 3600 -W 1
}

# Check file size
function check_file_size() {
    FILE_SIZE=$(stat -c%s "$CAPTURE_FILE")
    if [[ "$FILE_SIZE" -lt "$MIN_FILE_SIZE" ]]; then
        echo "[!] File is too small ($FILE_SIZE bytes). Removing and re-capturing."
        rm -f "$CAPTURE_FILE"
        capture_traffic
    fi
}

# Fuzz captured traffic
function fuzz_traffic() {
    if [[ -f "$CAPTURE_FILE" ]]; then
        echo "[+] Fuzzing captured traffic..."
        radamsa "$CAPTURE_FILE" > "$FUZZED_FILE"
    fi
}

# Split fuzzed traffic into packets
function split_fuzzed_traffic() {
    echo "[+] Splitting fuzzed traffic into packets..."
    split -b $((RANDOM % 1500 + 500)) "$FUZZED_FILE" junk_packet_
}

# Broadcast junk traffic
function broadcast_junk() {
    echo "[+] Broadcasting junk traffic over Yggdrasil..."
    while true; do
        packet=$(ls junk_packet_* 2>/dev/null | shuf -n 1)
        if [[ -z "$packet" ]]; then
            echo "[!] No junk packets found, restarting process."
            break
        fi

        cat "$packet" | nc -u "$YGG_PEER_IP" "$YGG_PORT"
        rm -f "$packet"
        sleep $((RANDOM % 60 + 5))
    done
}

# Main Loop
if [[ "$1" == "--capture" ]]; then
    rm -f "$CAPTURE_FILE"
    capture_traffic
fi

if [ ! -f "$CAPTURE_FILE" ]; then
    capture_traffic
fi

while true; do
    check_file_size
    fuzz_traffic
    split_fuzzed_traffic
    broadcast_junk
    sleep 10
done
