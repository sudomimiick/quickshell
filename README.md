# Quickshell desktop

A minimal, quiet desktop shell for [Hyprland](https://hypr.land), built with
[Quickshell](https://quickshell.org). One thin bar across the top; everything
else grows out of it as a panel and tucks back in.

- **Bar** — launcher, 5 workspaces, the focused app · clock, notifications, date · tray, brightness, volume, Bluetooth, Wi-Fi (with the VPN's country), battery, power
- **Calendar + notifications** under the clock: do-not-disturb, history, clear all
- **Battery + Wi-Fi + VPN** panel: battery and power profile (three circles), Wi-Fi networks (join, forget, passwords typed in place), Ethernet, one switch per VPN — NetworkManager profiles and VPN apps like Proton VPN. The bar shows `󰤨 │ India` while a VPN is on
- **Display + sound + Bluetooth** panel: brightness and Hyprland's display scale, volume, microphone and outputs, Bluetooth devices
- **Wallpaper picker** (SUPER+SHIFT+W): your wallpapers in a row; Enter opens the screen down the middle onto the new one
- **Volume / brightness pop-up** that drops out of the bar whenever either changes
- **App launcher** with fuzzy search, a calculator (`=`), run-a-command (`>`) and launch history
- **Notifications** with actions, images and history
- **Screenshots**: region / window / screen, copy, save, annotate
- **Power menu** with a small spinning companion (bring your own picture or GIF)

Monochrome with a few soft colours: lavender for "active", blue for connected,
amber and rose when something needs you.



To change how it looks or behaves — colours, sizes, the chibi, the bar's
height, keys, wallpapers — see **[GUIDE.md](GUIDE.md)**.

## Requirements

- Arch Linux (or an Arch-based distro) with Hyprland — a `hyprland.lua` (0.55+) or a `hyprland.conf` setup
- Quickshell 0.3.2 or newer (`pacman -S quickshell`)

Everything else is installed for you: NetworkManager, BlueZ, PipeWire, UPower,
power-profiles-daemon, brightnessctl, libvips, the JetBrains Mono Nerd Font,
hyprlock and a polkit agent.

## Install

```sh
git clone https://github.com/sudomimiick/quickshell.git
cd YOUR-REPO
./install.sh
```

or in one go (set `REPO` at the top of `install.sh` to this repository first):

```sh
curl -fsSL https://raw.githubusercontent.com/sudomimiick/quickshell/main/install.sh | bash
```

The installer asks before anything big. It:

1. installs the missing packages with `pacman`;
2. turns on Bluetooth and power profiles, and NetworkManager if nothing else manages your network (if `iwd`/`systemd-networkd` does, it tells you how to switch instead of cutting you off);
3. copies the shell to `~/.config/quickshell` — an existing one is moved to `~/.config/quickshell.bak-<date>` — and any pictures in this repo's `wallpapers/` folder to `~/Pictures/Wallpapers`;
4. puts `quickshell.lua` (or `quickshell.conf`) next to your Hyprland config and loads it from there — it starts the shell and binds the keys below. If your config already mentions Quickshell it's left alone;
5. starts the shell if you're in Hyprland right now.

Options: `--yes` (no questions), `--no-packages`, `--no-hypr`, `--link` (symlink to the clone, so `git pull` updates it), `--repo URL`, `--uninstall`.

Take other bars, notification daemons and wallpaper tools (waybar, mako, dunst,
swaync, hyprpaper, swww…) out of your autostart — the installer points them out.

## Keys

| Key | |
| --- | --- |
| `SUPER + D` | app launcher |
| `SUPER + N` | calendar and notifications |
| `SUPER + W` | battery, Wi-Fi and VPN |
| `SUPER + A` | display, sound and Bluetooth |
| `SUPER + SHIFT + W` | wallpaper picker |
| `SUPER + Escape` | power menu |
| `Print` / `SHIFT + Print` / `SUPER + Print` | screenshot: region (or click a window) / screen / active window |

Change them in `~/.config/hypr/quickshell.lua`; `hyprctl globalshortcuts` lists
everything the shell offers. The volume and brightness keys keep working however
you bind them — the pop-up appears either way.

**On the bar:** scroll on the brightness or volume icon to change it,
middle-click the volume icon to mute and the Wi-Fi icon to turn Wi-Fi off, scroll
anywhere else to switch workspace, right-click the clock for do-not-disturb. With
a panel open, hovering another icon swaps to its panel; clicking anywhere else
closes it.

**In the wallpaper picker:** ← → (or scroll) to choose, Enter or a click to set
it, Esc to close.

## Settings

Two files hold everything you're likely to change:

- `~/.config/quickshell/common/Config.qml` — behaviour: clock format, workspaces,
  notification timeouts, launcher, screenshots, VPN apps, wallpapers, the pop-up…
- `~/.config/quickshell/common/Theme.qml` — looks: colours, sizes, fonts, motion.

Quickshell reloads as you save. **[GUIDE.md](GUIDE.md)** walks through the common changes.

### Proton VPN

The switch runs the official Proton VPN command-line app: `protonvpn connect` /
`protonvpn disconnect`. Sign in once in a terminal with `protonvpn signin`. The
button next to the switch opens the Proton app if you have it (`protonvpn-app`).

### Wallpapers

Put pictures in `~/Pictures/Wallpapers` (or point `wallpaper.directory` elsewhere).
The shell draws the wallpaper itself — that's what makes the transition possible —
so take hyprpaper / swww out of your autostart. To keep one of those instead, set
`wallpaper.draw: false` and have `wallpaper.onChange` run it.

### Display scale

The slider in the display panel sets Hyprland's scale for the screen you're on,
offering only scales Hyprland takes as they are. It applies when you let go and is
remembered per monitor; "Reset scale" goes back to your Hyprland config.

## Scripting it

```sh
qs ipc call drawers toggle network      # centre | network | controls | wallpaper
qs ipc call wallpaper next              # also: previous, random, set <file>, rescan
qs ipc call launcher search "="         # straight into the calculator
qs ipc call screenshot screenIn 5       # after a 5 s countdown
qs ipc call notifs toggleDnd
qs ipc call audio set 40                # also: up, down, mute, micMute
qs ipc call brightness set 60           # also: up, down
qs ipc call display set 1.25            # also: options, reset
qs ipc call session toggle
qs ipc show                             # everything else
```

## Updating and removing

Run `./install.sh` again after `git pull` (or install with `--link` and just pull).
Your previous copy is kept as `~/.config/quickshell.bak-<date>`, so carry any
changes you made to `Config.qml` / `Theme.qml` across — or better, make them in the
repo and commit them.

`./install.sh --uninstall` removes the shell, puts your previous config back and
takes it out of your Hyprland config. Packages stay installed.

## Troubleshooting

- **Nothing shows up** — `qs log` shows what went wrong; `qs -n` starts it by hand.
- **No notifications** — another notification daemon is running (`pgrep -a 'mako|dunst|swaync'`).
- **The wallpaper doesn't change** — another wallpaper tool is drawing over it (`pgrep -a 'hyprpaper|swww|swaybg'`).
- **The Wi-Fi panel is empty** — NetworkManager isn't running: `systemctl status NetworkManager`.
- **No power profile circles** — power-profiles-daemon isn't running (or TLP / auto-cpufreq is in charge).
- **No brightness icon** — no backlight under `/sys/class/backlight` (most desktops).
