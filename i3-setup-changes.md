# i3 Setup

A self-contained bootstrap for a fresh i3 install on Ubuntu / Linux Mint.
All configs live in `configs/` and are symlinked into place by `setup.sh`.

---

## Usage

### Fresh install

```bash
git clone <your-repo> ~/.config/i3-setup
~/.config/i3-setup/setup.sh
# Open Firefox once, then re-run to apply Firefox config:
~/.config/i3-setup/setup.sh
# Log out → select i3 session → log in → reboot
```

### Re-running

`setup.sh` is idempotent — safe to re-run at any time. Each step checks before
acting and prints `SKIP` if already applied.

---

## What setup.sh does

### 1. Packages
Installs via `apt` (skips if already installed):

| Package | Purpose |
|---|---|
| `i3`, `i3status`, `i3lock`, `xss-lock`, `dex` | Window manager + screen lock |
| `xorg`, `xinit`, `x11-xserver-utils` | X11 |
| `picom` | Compositor (rounded corners, shadows) |
| `autorandr`, `arandr` | Multi-monitor profile switching |
| `nitrogen` | Wallpaper |
| `polybar`, `rofi` | Status bar + app launcher |
| `xfce4-terminal` | Terminal |
| `pulseaudio-utils` | Volume control via `pactl` |
| `dunst`, `libnotify-bin` | Notifications |
| `brightnessctl` | Brightness keys |
| `scrot`, `curl`, `unzip` | Screenshot + download utilities |
| `network-manager-gnome` | Network tray applet |
| `dmz-cursor-theme` | DMZ-White cursor |

### 2. FiraCode Nerd Font
Downloads from GitHub releases and installs to `~/.local/share/fonts/FiraCode/`.
Skipped if already installed.

### 3. System fixes (require sudo)

| Fix | File | Why |
|---|---|---|
| Screen tearing | `/usr/share/X11/xorg.conf.d/20-intel.conf` | Enables `TearFree` + `TripleBuffer` for Intel Arc modesetting driver |
| WiFi resume | `/usr/lib/systemd/system-sleep/wifi-resume.sh` | Reloads `iwlmld` (Intel Wi-Fi 7 driver) and restarts NetworkManager after suspend. The system's `iwlwifi.sh` hook targets the wrong module (`iwlmvm`) for this hardware. |
| Chrome apt warning | `/etc/apt/sources.list.d/google-chrome.sources` | Adds `Architectures: amd64` to suppress i386 fetch errors |
| CPU governor | `/etc/systemd/system/cpu-performance.service` | Sets `performance` governor via systemd on boot |
| Swappiness | `/etc/sysctl.d/99-performance.conf` | Reduces `vm.swappiness` from 60 → 10 |

Screen tearing and WiFi fixes require a reboot. The script will say so.

### 4. Config symlinks

All configs in `configs/` are symlinked to their target paths. If a real file
already exists at the target it is backed up as `.bak` before linking.

| configs/ path | Symlinked to |
|---|---|
| `.Xresources` | `~/.Xresources` |
| `picom.conf` | `~/.config/picom.conf` |
| `polybar/config.ini` | `~/.config/polybar/config.ini` |
| `polybar/launch.sh` | `~/.config/polybar/launch.sh` |
| `polybar/workspaces.sh` | `~/.config/polybar/workspaces.sh` |
| `rofi/config.rasi` | `~/.config/rofi/config.rasi` |
| `i3/config` | `~/.config/i3/config` |
| `firefox/user.js` | `~/.mozilla/firefox/<profile>/user.js` |
| `firefox/chrome/userChrome.css` | `~/.mozilla/firefox/<profile>/chrome/userChrome.css` |
| `firefox/chrome/userContent.css` | `~/.mozilla/firefox/<profile>/chrome/userContent.css` |

**Firefox note:** Firefox must have been launched at least once before running
`setup.sh` so that the profile directory exists. If the profile isn't found,
setup prints a warning and skips Firefox — re-run after opening Firefox once.

### 5. Polybar hardware detection

After linking polybar config, setup auto-detects the current machine's hardware
and patches `configs/polybar/config.ini` with the correct values:

- **WiFi interface** — detected via `ip link` (e.g. `wlp85s0f0`)
- **Battery** — detected via `/sys/class/power_supply/` (e.g. `BAT1`)
- **Backlight** — detected via `/sys/class/backlight/` (e.g. `intel_backlight`)

Each value is skipped if already correct, so re-runs don't dirty git state.

---

## Key bindings

| Binding | Action |
|---|---|
| `Mod+Return` | Open terminal (xfce4-terminal) |
| `Mod+Shift+Return` | Open Firefox (focuses existing window if running) |
| `Mod+d` | App launcher (rofi) |
| `Mod+Tab` | Window switcher (rofi) |
| `Mod+Shift+x` | Lock screen |
| `Mod+Shift+q` | Close window |
| `Mod+Shift+r` | Restart i3 |
| `Mod+Shift+e` | Exit i3 |
| `Print` | Screenshot → `~/Pictures/` |
| `XF86AudioRaiseVolume/LowerVolume/Mute` | Volume |
| `XF86MonBrightnessUp/Down` | Brightness |

---

## Hardware notes (Intel Arc / Meteor Lake)

- **picom backend:** `glx` with `use-damage = false`. If pink/magenta lines
  appear after a reboot, switch to `backend = "xrender"` in `configs/picom.conf`.
- **VA-API:** enabled in Firefox `user.js` for hardware video decoding.
- **WebRender:** forced on in Firefox for GPU compositing — first launch compiles
  shaders (slow once), subsequent launches use the cache.
- **DPI:** `.Xresources` sets `Xft.dpi: 144` for the HiDPI display. Polybar
  overrides to `dpi = 96` to prevent tray icon scaling issues.
