#!/bin/bash
# i3 fresh-install bootstrap for Ubuntu / Linux Mint
#
# Single source of truth: all configs live in configs/ next to this script.
# setup.sh installs packages, links configs/ into place, and applies system fixes.
#
# Usage on a fresh machine:
#   git clone <your-repo> ~/.config/i3-setup
#   ~/.config/i3-setup/setup.sh
#   # Log out → select i3 session → log in → reboot
#
# Idempotent: safe to re-run.

set -euo pipefail

SETUP_DIR="$(dirname "$(realpath "$0")")"
CONFIGS_DIR="$SETUP_DIR/configs"

step()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '    \033[0;32mOK\033[0m   %s\n' "$*"; }
skip()  { printf '    \033[0;33mSKIP\033[0m %s\n' "$*"; }
warn()  { printf '    \033[0;33mWARN\033[0m %s\n' "$*"; }

NEEDS_REBOOT=0

# ── Symlink helper ────────────────────────────────────────────────────────────
# link_config <configs/-relative-path> <target-absolute-path> [write-function]
#
# Priority:
#   1. If configs/ file exists                → use it (write-function is skipped)
#   2. If target real-file exists             → adopt it into configs/
#   3. If write-function given               → call it to create configs/ file
# Then symlink target → configs/ file.
link_config() {
    local rel="$1"
    local target="$2"
    local write_fn="${3:-}"
    local src="$CONFIGS_DIR/$rel"

    mkdir -p "$(dirname "$src")" "$(dirname "$target")"

    if [ ! -f "$src" ]; then
        if [ -f "$target" ] && [ ! -L "$target" ]; then
            mv "$target" "$src"
            ok "  Adopted into configs/$rel"
        elif [ -n "$write_fn" ]; then
            "$write_fn" "$src"
            ok "  Created  configs/$rel"
        else
            warn "  No source for configs/$rel — skipping"
            return
        fi
    elif [ -f "$target" ] && [ ! -L "$target" ]; then
        mv "$target" "$target.bak"
        warn "  Backed up $target → $target.bak"
    fi

    local src_real target_real
    src_real="$(realpath "$src")"
    target_real="$(readlink -f "$target" 2>/dev/null || true)"

    if [ -L "$target" ] && [ "$target_real" = "$src_real" ]; then
        skip "  Already linked: $rel"
    else
        ln -sf "$src" "$target"
        ok "  Linked $target"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# 1. PACKAGES
# ════════════════════════════════════════════════════════════════════════════
step "Packages"

PACKAGES=(
    i3 i3status i3lock xss-lock dex
    xorg xinit x11-xserver-utils
    picom
    autorandr arandr
    nitrogen
    polybar rofi
    xfce4-terminal
    pulseaudio-utils
    dunst libnotify-bin
    brightnessctl
    scrot imagemagick curl unzip
    network-manager-gnome
    dmz-cursor-theme
    copyq
    arc-theme papirus-icon-theme
    xsettingsd
    power-profiles-daemon
)

MISSING=()
for pkg in "${PACKAGES[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
done

if [ "${#MISSING[@]}" -eq 0 ]; then
    skip "All packages already installed"
else
    echo "    Installing: ${MISSING[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${MISSING[@]}"
    ok "Installed"
fi

# ════════════════════════════════════════════════════════════════════════════
# 2. FIRACODE NERD FONT
# ════════════════════════════════════════════════════════════════════════════
step "FiraCode Nerd Font"

FONT_DIR="$HOME/.local/share/fonts/FiraCode"

if ls "$FONT_DIR"/*.ttf &>/dev/null; then
    skip "Already installed"
else
    mkdir -p "$FONT_DIR"
    curl -L --progress-bar \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" \
        -o /tmp/FiraCode-nerd.zip
    unzip -q -o /tmp/FiraCode-nerd.zip "*.ttf" -d "$FONT_DIR"
    rm /tmp/FiraCode-nerd.zip
    fc-cache -f "$FONT_DIR"
    ok "Installed to $FONT_DIR"
fi

# ════════════════════════════════════════════════════════════════════════════
# 3. SYSTEM FIXES  (require sudo)
# ════════════════════════════════════════════════════════════════════════════

step "Screen tearing — 20-intel.conf (Intel Arc / modesetting)"
# /etc/X11/xorg.conf.d/ is the admin-managed location; survives package updates.
# /usr/share/X11/xorg.conf.d/ is package-managed and can be overwritten on upgrade.
XORG_CONF=/etc/X11/xorg.conf.d/20-intel.conf
sudo mkdir -p /etc/X11/xorg.conf.d
if [ -f "$XORG_CONF" ] && grep -q 'TearFree' "$XORG_CONF"; then
    skip "Already applied"
else
    sudo tee "$XORG_CONF" > /dev/null << 'EOF'
Section "Device"
  Identifier "Intel Graphics"
  Driver "modesetting"
  Option "TearFree" "true"
  Option "TripleBuffer" "true"
  Option "DRI" "iris"
EndSection
EOF
    ok "Written — reboot required"; NEEDS_REBOOT=1
fi
# Clean up old location if it exists (was previously written there)
if [ -f /usr/share/X11/xorg.conf.d/20-intel.conf ]; then
    sudo rm -f /usr/share/X11/xorg.conf.d/20-intel.conf
    ok "Removed old /usr/share/X11/xorg.conf.d/20-intel.conf"
fi

step "WiFi D3cold fix — Intel BE200 (iwlmld)"
# BE200 enters PCIe D3cold during suspend; firmware can't reinitialise on resume.
# Udev rule keeps d3cold_allowed=0 from boot so device stays in D3hot across sleep.
# Device ID 8086:272b = Intel BE200. Noop on other hardware.
WIFI_UDEV=/etc/udev/rules.d/10-intel-wifi-d3cold.rules
WIFI_UDEV_RULE='ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x272b", ATTR{d3cold_allowed}="0"'
if [ -f "$WIFI_UDEV" ] && grep -qF "$WIFI_UDEV_RULE" "$WIFI_UDEV"; then
    skip "Already installed"
else
    echo "$WIFI_UDEV_RULE" | sudo tee "$WIFI_UDEV" > /dev/null
    sudo udevadm control --reload
    ok "Installed"
fi
# Apply immediately without reboot
WIFI_PCI=$(lspci -D 2>/dev/null | awk '/Network controller.*Intel/{print $1; exit}')
if [ -n "$WIFI_PCI" ] && [ -e "/sys/bus/pci/devices/$WIFI_PCI" ]; then
    sudo udevadm trigger --action=add "/sys/bus/pci/devices/$WIFI_PCI"
    ok "d3cold_allowed=0 applied to $WIFI_PCI"
fi
# Clean up old sleep hooks (no longer needed)
for _old in /etc/systemd/system-sleep/wifi-resume.sh /usr/lib/systemd/system-sleep/wifi-resume.sh; do
    [ -f "$_old" ] && sudo rm -f "$_old" && ok "Removed $_old"
done
# Remove stale iwlmvm modprobe config (wrong driver for this hardware)
if [ -f /etc/modprobe.d/iwlmvm.conf ]; then
    sudo rm -f /etc/modprobe.d/iwlmvm.conf
    ok "Removed stale iwlmvm.conf"
fi

step "Chrome apt — suppress i386 warning"
CHROME_SOURCES=/etc/apt/sources.list.d/google-chrome.sources
if [ ! -f "$CHROME_SOURCES" ]; then
    skip "google-chrome.sources not found"
elif grep -q 'Architectures:' "$CHROME_SOURCES"; then
    skip "Already applied"
else
    sudo sed -i 's/^Types: deb$/Types: deb\nArchitectures: amd64/' "$CHROME_SOURCES"
    ok "Added Architectures: amd64"
fi

step "CPU governor — power-profiles-daemon (auto-switches on AC/battery)"
CPU_SVC=/etc/systemd/system/cpu-performance.service
if [ -f "$CPU_SVC" ]; then
    sudo systemctl disable --now cpu-performance.service 2>/dev/null || true
    sudo rm -f "$CPU_SVC"
    ok "Removed static performance governor service"
fi
if systemctl is-active --quiet power-profiles-daemon; then
    skip "power-profiles-daemon already running"
else
    sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
    sudo systemctl enable --now power-profiles-daemon \
        && ok "power-profiles-daemon enabled" \
        || warn "Could not enable power-profiles-daemon — may conflict with another power manager"
fi

step "picom resume hook — restart compositor after suspend"
PICOM_HOOK=/etc/systemd/system-sleep/picom-resume.sh
sudo mkdir -p /etc/systemd/system-sleep
if [ -f "$PICOM_HOOK" ] && diff -q "$CONFIGS_DIR/picom-resume.sh" "$PICOM_HOOK" > /dev/null 2>&1; then
    skip "Already installed"
else
    if sudo cp "$CONFIGS_DIR/picom-resume.sh" "$PICOM_HOOK" && sudo chmod +x "$PICOM_HOOK"; then
        ok "Installed"
    else
        warn "Could not install picom resume hook — run setup.sh with sudo access"
    fi
fi
# Clean up old location if it exists
if [ -f /usr/lib/systemd/system-sleep/picom-resume.sh ]; then
    sudo rm -f /usr/lib/systemd/system-sleep/picom-resume.sh
    ok "Removed old /usr/lib/systemd/system-sleep/picom-resume.sh"
fi

step "Swappiness — reduce to 10 (was 60)"
SYSCTL_CONF=/etc/sysctl.d/99-performance.conf
if [ -f "$SYSCTL_CONF" ] && grep -q 'swappiness=10' "$SYSCTL_CONF"; then
    skip "Already applied"
else
    echo 'vm.swappiness=10' | sudo tee "$SYSCTL_CONF" > /dev/null
    sudo sysctl -p "$SYSCTL_CONF" > /dev/null
    ok "Swappiness set to 10"
fi

# ════════════════════════════════════════════════════════════════════════════
# 4. CONFIG FILES  (symlinked from configs/)
# ════════════════════════════════════════════════════════════════════════════
step "Config symlinks — configs/ → ~/.config/"

# ── .Xresources ──────────────────────────────────────────────────────────────
link_config ".Xresources" "$HOME/.Xresources"
xrdb "$HOME/.Xresources" 2>/dev/null || true

# ── picom ─────────────────────────────────────────────────────────────────────
_picom_linked=0
{ [ ! -L "$HOME/.config/picom.conf" ] || \
  [ "$(readlink -f "$HOME/.config/picom.conf" 2>/dev/null)" != "$(realpath "$CONFIGS_DIR/picom.conf")" ]; } \
  && _picom_linked=1
link_config "picom.conf" "$HOME/.config/picom.conf"
if [ "$_picom_linked" -eq 1 ] && pgrep -x picom > /dev/null 2>&1; then
    pkill -x picom; sleep 0.3
    picom --config "$HOME/.config/picom.conf" &
    ok "  picom restarted"
fi

# ── autorandr external monitor ───────────────────────────────────────────────
AUTORANDR_EXT="$HOME/.config/autorandr/external/config"
if [ -f "$AUTORANDR_EXT" ] && ! grep -q 'broadcast_rgb Full' "$AUTORANDR_EXT"; then
    sed -i 's/x-prop-broadcast_rgb Automatic/x-prop-broadcast_rgb Full/' "$AUTORANDR_EXT"
    ok "  autorandr external: broadcast_rgb → Full"
fi

# ── polybar ───────────────────────────────────────────────────────────────────
WLAN_IFACE=$(ip -o link show 2>/dev/null | awk '$2 ~ /^w/ {gsub(/:/, "", $2); print $2; exit}')
WLAN_IFACE=${WLAN_IFACE:-wlan0}
BATTERY=$(ls /sys/class/power_supply/ 2>/dev/null | grep -i bat | head -1)
BATTERY=${BATTERY:-BAT0}
BACKLIGHT=$(ls /sys/class/backlight/ 2>/dev/null | head -1)
BACKLIGHT=${BACKLIGHT:-intel_backlight}

link_config "polybar/config.ini"    "$HOME/.config/polybar/config.ini"
link_config "polybar/launch.sh"     "$HOME/.config/polybar/launch.sh"
link_config "polybar/workspaces.sh" "$HOME/.config/polybar/workspaces.sh"
chmod +x "$HOME/.config/polybar/launch.sh" "$HOME/.config/polybar/workspaces.sh"

# Patch hardware-specific values — auto-detected each run, skipped if already correct
_patch_polybar() {
    local key="$1" val="$2" file="$CONFIGS_DIR/polybar/config.ini"
    if grep -q "^${key}[[:space:]]*=[[:space:]]*${val}[[:space:]]*$" "$file"; then
        skip "  polybar: $key = $val"
    else
        sed -i "s|^${key}[[:space:]]*=.*|${key} = ${val}|" "$file"
        ok "  polybar: $key → $val"
    fi
}
_patch_polybar "interface" "$WLAN_IFACE"
_patch_polybar "battery"   "$BATTERY"
_patch_polybar "card"      "$BACKLIGHT"

# ── rofi ──────────────────────────────────────────────────────────────────────
link_config "rofi/config.rasi" "$HOME/.config/rofi/config.rasi"

# ── i3 config ─────────────────────────────────────────────────────────────────
link_config "i3/config" "$HOME/.config/i3/config"

# ── lockscreen ────────────────────────────────────────────────────────────────
link_config "lockscreen.sh"        "$HOME/.config/lockscreen.sh"
link_config "lockscreen-update.sh" "$HOME/.config/lockscreen-update.sh"
chmod +x "$HOME/.config/lockscreen.sh" "$HOME/.config/lockscreen-update.sh"

# ── dunst ─────────────────────────────────────────────────────────────────────
link_config "dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
if pgrep -x dunst > /dev/null 2>&1; then
    pkill -x dunst; sleep 0.1
    dunst &
    ok "  dunst restarted"
fi

# ── GTK theme ─────────────────────────────────────────────────────────────────
link_config "gtk-3.0/settings.ini"       "$HOME/.config/gtk-3.0/settings.ini"
link_config "gtkrc-2.0"                  "$HOME/.gtkrc-2.0"
link_config "xsettingsd/xsettingsd.conf" "$HOME/.config/xsettingsd/xsettingsd.conf"
link_config "icons-default/index.theme"  "$HOME/.icons/default/index.theme"
if pgrep -x xsettingsd > /dev/null 2>&1; then
    pkill -x xsettingsd; sleep 0.1
    xsettingsd &
    ok "  xsettingsd restarted"
fi

# ── firefox ───────────────────────────────────────────────────────────────────

FF_PROFILE=$(python3 - <<'PYEOF'
import configparser, os, sys
p = configparser.ConfigParser()
p.read(os.path.expanduser("~/.mozilla/firefox/profiles.ini"))
for s in p.sections():
    if p.get(s, "Default", fallback="0") == "1" and p.get(s, "Path", fallback=""):
        print(p.get(s, "Path"))
        sys.exit(0)
PYEOF
)

if [ -z "$FF_PROFILE" ]; then
    warn "Could not detect Firefox default profile — skipping"
else
    FF_DIR="$HOME/.mozilla/firefox/$FF_PROFILE"
    mkdir -p "$FF_DIR/chrome"

    link_config "firefox/user.js"              "$FF_DIR/user.js"
    link_config "firefox/chrome/userChrome.css"  "$FF_DIR/chrome/userChrome.css"
    link_config "firefox/chrome/userContent.css" "$FF_DIR/chrome/userContent.css"
fi

# ════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════════════════
echo
printf '\033[1;32m==> Done.\033[0m\n'
echo
echo "  configs/ layout:"
find "$CONFIGS_DIR" -type f | sort | sed "s|$CONFIGS_DIR/||" | sed 's/^/    /'
echo
[ "$NEEDS_REBOOT" -eq 1 ] && echo "  Reboot for: screen tearing fix, WiFi sleep fix."
echo "  Keybinds: Mod+d (apps)  Mod+Tab (windows)  Mod+Return (terminal)  Print (screenshot)"
