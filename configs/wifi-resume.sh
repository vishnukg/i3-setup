#!/bin/bash
# Reload Intel Wi-Fi 7 (iwlmld) after suspend and reconnect NetworkManager.
# Runs after the system's iwlwifi.sh which removes the wrong modules.

[ "$1" = "post" ] || exit 0
sleep 1

if ! lsmod | grep -q iwlmld; then
    modprobe iwlmld 2>/dev/null || true
    sleep 2
fi

systemctl restart NetworkManager 2>/dev/null || true
