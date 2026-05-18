# i3 Post-Install Setup — Changes & Fixes

## Script

Run once after a fresh i3 install:

```
~/.config/i3-setup/setup.sh
```

Self-contained — installs all packages, writes polybar/rofi/picom configs,
patches i3 config, and applies system-level fixes.
Requires sudo (prompts automatically) for apt install and Xorg/modprobe changes.
Idempotent — safe to re-run; already-applied steps are skipped.
After running: reload i3 with Mod+Shift+R, then reboot.

---

## Changes applied (2026-05-18)

### 1. Screen tearing fix — `20-intel.conf`
**Script:** `fix-screen-tearing.sh`
**File:** `/usr/share/X11/xorg.conf.d/20-intel.conf`
**What:** Enables `TearFree` and `TripleBuffer` on the Intel Arc modesetting driver.
**Why:** Without it, screen tearing is visible in i3. picom vsync alone isn't enough at the driver level.
**Status:** Applied. Reboot required.

### 2. External monitor color fix — autorandr broadcast_rgb
**Script:** `fix-external-monitor-colors.sh`
**File:** `~/.config/autorandr/external/config`
**What:** Changed `x-prop-broadcast_rgb` from `Automatic` to `Full`.
**Why:** "Automatic" causes Intel Arc to output limited color range (16–235) on HDMI/DP,
making colors look washed out. "Full" forces the correct 0–255 range for a monitor (not a TV).
**Status:** Applied. Takes effect next time autorandr switches to the external profile.

### 3. WiFi sleep fix — `iwlmvm.conf`
**Script:** `fix-wifi-sleep.sh`
**File:** `/etc/modprobe.d/iwlmvm.conf`
**Content:** `options iwlmvm power_scheme=1`
**What:** Disables aggressive power management on the Intel Wi-Fi 7 (iwlmvm) module.
**Why:** The sleep hook at `/usr/lib/systemd/system-sleep/iwlwifi.sh` unloads/reloads the
wifi modules around suspend, but on some kernels the module reloads with power_scheme=3
(aggressive), which causes the adapter to drop. power_scheme=1 keeps it stable.
**Status:** Applied. Reboot required.

### 4. HiDPI cursor size fix — `.Xresources`
**Script:** `fix-hidpi-cursor.sh`
**File:** `~/.Xresources`
**What:** Changed `Xcursor.size` from `40` to `80`.
**Why:** At 144 DPI (2880x1800 display), a size-40 cursor is too small. 80 matches the
intended size documented in the dotfiles README.
**Status:** Applied. Run `xrdb ~/.Xresources` to apply without relog, or just relog.

---

### 5. Chrome apt i386 warning fix
**Script:** `fix-chrome-apt-warning.sh`
**File:** `/etc/apt/sources.list.d/google-chrome.sources`
**What:** Adds `Architectures: amd64` to the Chrome apt sources file.
**Why:** Without it, apt tries to fetch i386 packages from the Chrome repo which doesn't
provide them, producing a warning on every `apt update`.
**Status:** Script created — run it, then verify with `sudo apt update`.

---

## i3 config improvements (2026-05-18)

All changes are in `~/.config/i3/config`. Reload with `Mod+Shift+R` to apply
(autorandr change only takes effect on next login).

### 6. Fix picom duplicate instances on i3 reload
**What:** Changed `exec_always picom -b` to `exec_always pkill -x picom; picom`.
**Why:** `exec_always` with `-b` (daemonize) spawns a new picom on every i3 reload without
killing the old one, causing visual glitches from multiple compositors running simultaneously.

### 7. autorandr triggered on login
**What:** Added `exec --no-startup-id autorandr --change`.
**Why:** Without this, autorandr profiles exist but are never activated automatically at login —
display detection only happened manually.

### 8. Volume keys switched from amixer to pactl
**What:** Replaced `amixer sset 'Master'` with `pactl set-sink-volume @DEFAULT_SINK@` for
volume up/down/mute keys. Mic mute was already using pactl.
**Why:** Consistency — amixer and pactl can conflict on PipeWire/PulseAudio systems. pactl
is the correct tool for all audio control.

### 9. Screenshot keybinding
**What:** Added `bindsym Print exec scrot ~/Pictures/screenshot-%Y-%m-%d-%H-%M-%S.png`.
**Why:** `Print` key was unbound. Screenshots save to `~/Pictures/` with a timestamp filename.

### 10. workspace_auto_back_and_forth
**What:** Added `workspace_auto_back_and_forth yes`.
**Why:** Pressing the same workspace key twice now jumps back to the previous workspace,
useful for quickly toggling between two workspaces.

---

## Changes applied (2026-05-18, session 3 — visual refresh)

### Summary
Nord theme, polybar, rofi, FiraCode font, transparent bar, 2px blue borders.
Rounded corners added to picom.conf — activate by switching `backend = "glx"` after reboot fixes pink lines.

| File | Change |
|------|--------|
| `~/.config/i3/config` | Nord colors, FiraCode font, 2px borders, polybar, rofi, gaps 10/4 |
| `~/.config/polybar/config.ini` | New — Nord themed, transparent bg, all system modules |
| `~/.config/polybar/launch.sh` | New — multi-monitor polybar launcher |
| `~/.config/rofi/config.rasi` | New — Nord themed with rounded corners |
| `~/.config/picom.conf` | corner-radius = 10 (activates when backend switches to glx) |

---

## Changes applied (2026-05-18, session 2)

### 11. picom pink-lines fix — `~/.config/picom.conf`
**What:** Switched `backend` from `glx` to `xrender`. Also set `use-damage = false` and
`glx-no-stencil = true` (retained for if GLX is ever re-enabled).
**Why:** picom GLX backend on Intel Arc (MTL / i915 + Mesa iris) causes pink/magenta lines
when a browser opens. The GLX damage-based partial redraws race with browser's own GL
rendering, leaving uninitialized RGBA buffer regions. Switching to xrender backend avoids
the conflict entirely. Performance impact is negligible for desktop use on modern hardware.
**Status:** Applied and picom restarted. No reboot required.

### 12. Cursor size reduced — `~/.Xresources`
**What:** Changed `Xcursor.size` from `80` to `48`.
**Why:** 80 was too large. 48 is visible at 144 DPI without being oversized.
**Status:** Applied (`xrdb ~/.Xresources`). New apps pick it up immediately; full effect on reboot.

---

## Already correctly set up (verified)

- `/usr/lib/systemd/system-sleep/iwlwifi.sh` — installed and executable (chmod 755)
- `~/.Xresources` — loaded at login (confirmed via `xrdb -query`)
- `picom` — running via i3 `exec_always` with glx backend + vsync, `use-damage = false`
- `nm-applet` — running for NetworkManager tray icon
- `autorandr` — profiles for `laptop` and `external` both present
- `brightnessctl` — brightness keys bound in i3 config
- `xss-lock` + `i3lock` — screen lock on suspend configured
- CapsLock remapped to Ctrl via `setxkbmap`
- Keyboard repeat rate set (`xset r rate 200 35`)
