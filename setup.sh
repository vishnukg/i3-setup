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
XORG_CONF=/usr/share/X11/xorg.conf.d/20-intel.conf
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

step "WiFi sleep — iwlmvm power_scheme=1 (Intel Wi-Fi 7)"
MODPROBE_CONF=/etc/modprobe.d/iwlmvm.conf
if [ -f "$MODPROBE_CONF" ] && grep -q 'power_scheme=1' "$MODPROBE_CONF"; then
    skip "Already applied"
else
    echo "options iwlmvm power_scheme=1" | sudo tee "$MODPROBE_CONF" > /dev/null
    ok "Written — reboot required"; NEEDS_REBOOT=1
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
PICOM_HOOK=/usr/lib/systemd/system-sleep/picom-resume.sh
if [ -f "$PICOM_HOOK" ] && diff -q "$CONFIGS_DIR/picom-resume.sh" "$PICOM_HOOK" > /dev/null 2>&1; then
    skip "Already installed"
else
    if sudo cp "$CONFIGS_DIR/picom-resume.sh" "$PICOM_HOOK" && sudo chmod +x "$PICOM_HOOK"; then
        ok "Installed"
    else
        warn "Could not install picom resume hook — run setup.sh with sudo access"
    fi
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
write_xresources() {
    cat > "$1" << 'EOF'
Xft.dpi: 144
Xft.autohint: 0
Xft.lcdfilter: lcddefault
Xft.hintstyle: hintfull
Xft.hinting: 1
Xft.antialias: 1
Xft.rgba: rgb
Xcursor.theme: DMZ-White
Xcursor.size: 48
EOF
}
link_config ".Xresources" "$HOME/.Xresources" write_xresources
xrdb "$HOME/.Xresources" 2>/dev/null || true

# ── picom ─────────────────────────────────────────────────────────────────────
write_picom() {
    cat > "$1" << 'EOF'
# picom config — Intel Arc (Meteor Lake), xrender backend
# Switch backend = "glx" after verifying no pink-line artifacts post-reboot
# to activate rounded corners.

backend        = "glx";
vsync          = true;
use-damage     = false;
glx-no-stencil = true;

corner-radius  = 10;
rounded-corners-exclude = [
    "window_type = 'dock'",
    "window_type = 'desktop'"
];

shadow          = true;
shadow-radius   = 7;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-exclude  = [
    "name = 'Notification'",
    "class_g = 'Conky'",
    "class_g ?= 'Notify-osd'",
    "_GTK_FRAME_EXTENTS@:c",
    "name = 'cpt_frame_window'"
];

fading                = false;
frame-opacity         = 0.9;
inactive-opacity      = 1;
inactive-opacity-override = false;
detect-rounded-corners    = true;
detect-client-opacity     = true;
detect-transient          = true;
detect-client-leader      = true;
mark-wmwin-focused        = true;
mark-ovredir-focused      = true;
log-level = "warn";

wintypes: {
    dock    = { shadow = false; };
    dnd     = { shadow = false; };
    tooltip = { shadow = false; fade = false; };
};
EOF
}
_picom_linked=0
{ [ ! -L "$HOME/.config/picom.conf" ] || \
  [ "$(readlink -f "$HOME/.config/picom.conf" 2>/dev/null)" != "$(realpath "$CONFIGS_DIR/picom.conf")" ]; } \
  && _picom_linked=1
link_config "picom.conf" "$HOME/.config/picom.conf" write_picom
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

write_polybar_config() {
    cat > "$1" << EOF
# Tokyo Night — auto-generated by setup.sh
# wlan=$WLAN_IFACE  battery=$BATTERY  backlight=$BACKLIGHT
[colors]
bg       = #00000000
bg-alt   = #00000000
fg       = #c0caf5
fg-dim   = #565f89
blue     = #7aa2f7
blue-alt = #bb9af7
red      = #f7768e
green    = #9ece6a

[bar/main]
width                 = 100%
height                = 46
dpi                   = 96
background            = \${colors.bg}
foreground            = \${colors.fg}
line-size             = 2
border-size           = 0
padding-left          = 2
padding-right         = 2
module-margin-right   = 1
font-0                = FiraCode Nerd Font Mono:style=Bold:size=22;6
font-1                = FiraCode Nerd Font Mono:size=15;5
font-2                = FiraCode Nerd Font Mono:style=Bold:size=21;6
modules-left          = workspaces
modules-center        =
modules-right         = pulseaudio backlight battery wlan cpu memory tray date
wm-restack            = i3
override-redirect     = false
cursor-click          = pointer
cursor-scroll         = ns-resize
enable-ipc            = true

[module/workspaces]
type     = custom/script
exec     = ~/.config/polybar/workspaces.sh
tail     = true

[module/date]
type   = internal/date
interval = 5
date   = %a %d %b
time   = %H:%M
label  =  %date% %time%

[module/pulseaudio]
type                   = internal/pulseaudio
use-ui-max             = false
format-volume          = <ramp-volume> <label-volume>
label-volume           = %percentage%%
label-muted            = 󰝟 muted
label-muted-foreground = \${colors.fg-dim}
ramp-volume-0          = 󰕿
ramp-volume-1          = 󰖀
ramp-volume-2          = 󰕾
ramp-volume-foreground = \${colors.blue}

[module/backlight]
type                  = internal/backlight
card                  = $BACKLIGHT
use-actual-brightness = true
enable-scroll         = true
format                = <ramp> <label>
label                 = %percentage%%
ramp-0                = 󰃞
ramp-1                = 󰃟
ramp-2                = 󰃠
ramp-foreground       = \${colors.blue}

[module/wlan]
type                          = internal/network
interface                     = $WLAN_IFACE
interval                      = 5
label-connected               = 󰤨 %essid%
label-disconnected            = 󰤭 --
label-disconnected-foreground = \${colors.fg-dim}

[module/battery]
type                          = internal/battery
battery                       = $BATTERY
adapter                       = AC
full-at                       = 99
low-at                        = 10
poll-interval                 = 10
format-charging               = <animation-charging> <label-charging>
format-discharging            = <ramp-capacity> <label-discharging>
format-full                   = <label-full>
format-low                    = <ramp-capacity> <label-low>
label-charging                = %percentage%%
label-discharging             = %percentage%%
label-full                    = 󰁹 Full
label-low                     = %percentage%%
label-low-foreground          = \${colors.red}
ramp-capacity-0               = 󰂎
ramp-capacity-1               = 󰁺
ramp-capacity-2               = 󰁾
ramp-capacity-3               = 󰂀
ramp-capacity-4               = 󰁹
ramp-capacity-foreground      = \${colors.blue}
animation-charging-0          = 󰢜
animation-charging-1          = 󰂆
animation-charging-2          = 󰂈
animation-charging-3          = 󰂊
animation-charging-4          = 󰂅
animation-charging-foreground = \${colors.green}
animation-charging-framerate  = 750

[module/cpu]
type                     = internal/cpu
interval                 = 2
format-prefix            = "󰍛 "
format-prefix-foreground = \${colors.blue}
label                    = %percentage:2%%

[module/memory]
type                     = internal/memory
interval                 = 3
format-prefix            = "󰾆 "
format-prefix-foreground = \${colors.blue}
label                    = %percentage_used:2%%

[module/tray]
type         = internal/tray
tray-padding = 6px
tray-maxsize = 16
EOF
}

write_polybar_launch() {
    cat > "$1" << 'EOF'
#!/bin/bash
killall -q polybar
while pgrep -u "$UID" -x polybar > /dev/null; do sleep 0.1; done
for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR="$m" polybar --reload main 2>&1 | tee -a /tmp/polybar-"$m".log &
done
EOF
    chmod +x "$1"
}

write_workspaces_script() {
    cat > "$1" << 'EOF'
#!/bin/bash
PYTHON_SCRIPT='
import json, sys

colors = ["", "#89b4fa", "#a6e3a1", "#cba6f7", "#74c7ec", "#b4befe", "#94e2d5", "#f9e2af", "#f5c2e7", "#89b4fa", "#a6e3a1"]
text = "#000000"

def dim(hex_color, factor=0.35):
    r = int(int(hex_color[1:3], 16) * factor)
    g = int(int(hex_color[3:5], 16) * factor)
    b = int(int(hex_color[5:7], 16) * factor)
    return f"#{r:02x}{g:02x}{b:02x}"

try:
    workspaces = json.load(sys.stdin)
    workspaces.sort(key=lambda w: w["num"])
    parts = []
    for ws in workspaces:
        num = min(ws["num"], len(colors) - 1)
        color = colors[num]
        name = ws["name"]
        click = f"i3-msg workspace \"{name}\""
        if ws["focused"]:
            parts.append(f"%{{B{color}}}%{{F{text}}}%{{A1:{click}:}}%{{O12}}{name}%{{O12}}%{{A}}%{{B-}}%{{F-}}")
        elif ws["urgent"]:
            parts.append(f"%{{B#f9e2af}}%{{F{text}}}%{{A1:{click}:}}%{{O12}}{name}%{{O12}}%{{A}}%{{B-}}%{{F-}}")
        else:
            parts.append(f"%{{B{dim(color)}}}%{{F{text}}}%{{A1:{click}:}}%{{O12}}{name}%{{O12}}%{{A}}%{{B-}}%{{F-}}")
    print("%{O6}".join(parts))
except (json.JSONDecodeError, KeyError):
    pass
'

print_workspaces() {
    i3-msg -t get_workspaces 2>/dev/null | python3 -c "$PYTHON_SCRIPT" 2>/dev/null
}

print_workspaces

while true; do
    i3-msg -t subscribe '["workspace"]' 2>/dev/null | while read -r _; do
        print_workspaces
    done
    sleep 0.5
    print_workspaces
done
EOF
    chmod +x "$1"
}

link_config "polybar/config.ini"    "$HOME/.config/polybar/config.ini"    write_polybar_config
link_config "polybar/launch.sh"     "$HOME/.config/polybar/launch.sh"     write_polybar_launch
link_config "polybar/workspaces.sh" "$HOME/.config/polybar/workspaces.sh" write_workspaces_script

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
write_rofi() {
    cat > "$1" << 'EOF'
/* Floating Prompt — minimalist dark */
configuration {
    modi:               "drun,window,run";
    font:               "FiraCode Nerd Font Mono Bold 15";
    show-icons:         true;
    drun-display-format: "{icon} {name}";
    sidebar-mode:       false;
}

* {
    background:                  transparent;
    foreground:                  #ffffff;
    lightbg:                     #1e1e2e;
    lightfg:                     #6b7280;
    separatorcolor:              transparent;

    normal-background:           transparent;
    normal-foreground:           #ffffff;
    alternate-normal-background: transparent;
    alternate-normal-foreground: #ffffff;
    selected-normal-background:  #7aa2f7;
    selected-normal-foreground:  #1a1b2e;

    urgent-background:           transparent;
    urgent-foreground:           #f7768e;
    alternate-urgent-background: transparent;
    alternate-urgent-foreground: #f7768e;
    selected-urgent-background:  #f7768e;
    selected-urgent-foreground:  #1a1b2e;

    active-background:           transparent;
    active-foreground:           #9ece6a;
    alternate-active-background: transparent;
    alternate-active-foreground: #9ece6a;
    selected-active-background:  #9ece6a;
    selected-active-foreground:  #1a1b2e;

    bar:              #1a1b2ef4;
    fg:               #ffffff;
    fg-dim:           #6b7280;
    sel-bg:           #7aa2f7;
    sel-fg:           #1a1b2e;

    background-color: transparent;
    text-color:       #ffffff;
    border-color:     transparent;
}

window {
    background-color: transparent;
    border:           0px;
    width:            40%;
}

mainbox {
    background-color: transparent;
    spacing:          6px;
    padding:          0;
    children:         [ inputbar, listview ];
}

inputbar {
    background-color: @bar;
    border-radius:    10px;
    padding:          12px 16px;
    spacing:          10px;
    children:         [ prompt, entry ];
}

prompt {
    background-color: transparent;
    text-color:       @sel-bg;
}

entry {
    background-color:  transparent;
    text-color:        @fg;
    placeholder:       "search apps...";
    placeholder-color: @fg-dim;
}

listview {
    background-color: #000000aa;
    border:           0;
    spacing:          2px;
    padding:          4px 0 0;
    scrollbar:        false;
    lines:            8;
}

element {
    background-color: transparent;
    border-radius:    8px;
    padding:          8px 12px;
    spacing:          10px;
    children:         [ element-icon, element-text ];
}

element-icon { size: 20px; background-color: transparent; }
element-text { text-color: inherit; background-color: transparent; }

element.normal.normal   { background-color: transparent; text-color: #ffffff; }
element.selected.normal { background-color: @sel-bg;     text-color: @sel-fg; }
element.normal.urgent   { background-color: transparent; text-color: #f7768e; }
element.selected.urgent { background-color: #f7768e;     text-color: @sel-fg; }
element.normal.active   { background-color: transparent; text-color: #9ece6a; }
element.selected.active { background-color: #9ece6a;     text-color: @sel-fg; }
EOF
}
link_config "rofi/config.rasi" "$HOME/.config/rofi/config.rasi" write_rofi

# ── i3 config ─────────────────────────────────────────────────────────────────
write_i3() {
    cat > "$1" << 'EOF'
# i3 config — Tokyo Night
# Managed by ~/.config/i3-setup/setup.sh

set $mod Mod4

font pango:FiraCode Nerd Font Mono 11

exec --no-startup-id dex --autostart --environment i3
exec --no-startup-id xss-lock --transfer-sleep-lock -- ~/.config/lockscreen.sh
exec --no-startup-id nm-applet
exec --no-startup-id autorandr --change
exec --no-startup-id copyq
exec --no-startup-id xsettingsd
exec --no-startup-id ~/.config/lockscreen-update.sh

exec_always --no-startup-id pkill -x picom; picom --config ~/.config/picom.conf
exec_always --no-startup-id ~/.config/polybar/launch.sh
exec_always --no-startup-id /usr/bin/setxkbmap -option "ctrl:nocaps"
exec_always nitrogen --restore
exec_always --no-startup-id xset r rate 200 35

set $refresh_i3status killall -SIGUSR1 i3status
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5% && $refresh_i3status
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5% && $refresh_i3status
bindsym XF86AudioMute        exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && $refresh_i3status
bindsym XF86AudioMicMute     exec --no-startup-id pactl set-source-mute @DEFAULT_SOURCE@ toggle && $refresh_i3status
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl --min-val=2 -q set 5%-
bindsym XF86MonBrightnessUp   exec --no-startup-id brightnessctl -q set 5%+

floating_modifier $mod
tiling_drag modifier titlebar

bindsym $mod+Return       exec xfce4-terminal
bindsym $mod+Shift+Return exec --no-startup-id bash -c 'pgrep -x firefox > /dev/null && i3-msg '"'"'[class="firefox"] focus'"'"' || firefox'
bindsym $mod+Shift+q      kill
bindsym $mod+d            exec --no-startup-id rofi -show drun
bindsym $mod+Tab          exec --no-startup-id rofi -show window
bindsym $mod+Shift+x      exec --no-startup-id ~/.config/lockscreen.sh
bindsym Print             exec --no-startup-id scrot ~/Pictures/screenshot-%Y-%m-%d-%H-%M-%S.png

bindsym $mod+Left  focus left
bindsym $mod+Down  focus down
bindsym $mod+Up    focus up
bindsym $mod+Right focus right
bindsym $mod+j     focus left
bindsym $mod+k     focus down
bindsym $mod+l     focus up
bindsym $mod+semicolon focus right

bindsym $mod+Shift+Left  move left
bindsym $mod+Shift+Down  move down
bindsym $mod+Shift+Up    move up
bindsym $mod+Shift+Right move right
bindsym $mod+Shift+j     move left
bindsym $mod+Shift+k     move down
bindsym $mod+Shift+l     move up
bindsym $mod+Shift+semicolon move right

bindsym $mod+h           split h
bindsym $mod+v           split v
bindsym $mod+f           fullscreen toggle
bindsym $mod+s           layout stacking
bindsym $mod+w           layout tabbed
bindsym $mod+e           layout toggle split
bindsym $mod+Shift+space floating toggle
bindsym $mod+space       focus mode_toggle
bindsym $mod+a           focus parent

set $ws1 "1"
set $ws2 "2"
set $ws3 "3"
set $ws4 "4"
set $ws5 "5"
set $ws6 "6"
set $ws7 "7"
set $ws8 "8"
set $ws9 "9"
set $ws10 "10"

bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5
bindsym $mod+6 workspace number $ws6
bindsym $mod+7 workspace number $ws7
bindsym $mod+8 workspace number $ws8
bindsym $mod+9 workspace number $ws9
bindsym $mod+0 workspace number $ws10

bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5
bindsym $mod+Shift+6 move container to workspace number $ws6
bindsym $mod+Shift+7 move container to workspace number $ws7
bindsym $mod+Shift+8 move container to workspace number $ws8
bindsym $mod+Shift+9 move container to workspace number $ws9
bindsym $mod+Shift+0 move container to workspace number $ws10

bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes, exit' 'i3-msg exit'"

mode "resize" {
    bindsym Left       resize shrink width  10 px or 10 ppt
    bindsym Down       resize grow   height 10 px or 10 ppt
    bindsym Up         resize shrink height 10 px or 10 ppt
    bindsym Right      resize grow   width  10 px or 10 ppt
    bindsym j          resize shrink width  10 px or 10 ppt
    bindsym k          resize grow   height 10 px or 10 ppt
    bindsym l          resize shrink height 10 px or 10 ppt
    bindsym semicolon  resize grow   width  10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
    bindsym $mod+r mode "default"
}
bindsym $mod+r mode "resize"

gaps inner 10
gaps outer 4

default_border pixel 2
default_floating_border pixel 2

#                       border    bg        text      indicator child_border
client.focused          #7dcfff   #3b4252   #eceff4   #7dcfff   #7dcfff
client.focused_inactive #4c566a   #2e3440   #d8dee9   #4c566a   #4c566a
client.unfocused        #3b4252   #2e3440   #4c566a   #3b4252   #3b4252
client.urgent           #bf616a   #2e3440   #eceff4   #bf616a   #bf616a
client.background       #2e3440

workspace_auto_back_and_forth yes
EOF
}
link_config "i3/config" "$HOME/.config/i3/config" write_i3

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
link_config "gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
link_config "gtkrc-2.0"            "$HOME/.gtkrc-2.0"
link_config "xsettingsd/xsettingsd.conf" "$HOME/.config/xsettingsd/xsettingsd.conf"
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
