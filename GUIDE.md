# Changing things — a guide for future you

Everything here is a small edit to a text file. Quickshell watches its files and
reloads the moment you save, so you see each change straight away.

---

## Before you start

**Where to edit.** The running copy lives in `~/.config/quickshell`. The copy you
keep on GitHub is your clone of the repo. Pick one way of working:

- **Edit the repo, keep it linked** (recommended). Run `./install.sh --link` once.
  `~/.config/quickshell` then *is* your clone, so every edit is live and ready to
  commit:
  ```sh
  cd ~/path/to/your/clone
  git add -A && git commit -m "lavender → teal" && git push
  ```
- **Edit `~/.config/quickshell` directly**, then copy the files you changed back
  into the repo before you commit.

**If something breaks.** A typo usually means the shell vanishes or stops
updating. Then:

- `qs log` shows the error. The first `ERROR` line names the file and line number.
- Undo your last edit, or `git checkout -- <file>` in the repo.
- `qs kill; qs -d -n` restarts the shell by hand.

**Sizes are in rem.** Most sizes are written like `Theme.rem(2.75)`. 1 rem is a
13 px font (adjusted per screen). So `2.75` means "2.75 × the text size". Nudge
these numbers by small steps, like 0.1–0.3 at a time.

**Colours** are hex: `"#b4a7e0"`. With transparency it's `"#AARRGGBB"`, so
`"#12ffffff"` is white at 7 %.

---

## The two files you'll use most

| File | What's in it |
| --- | --- |
| `common/Config.qml` | behaviour: clock format, workspaces, timeouts, wallpapers, VPN apps, power menu commands, … |
| `common/Theme.qml` | looks: colours, fonts, sizes, corner radii, animation speeds |

Every setting has a comment next to it. The rest of this guide is recipes.

---

## Colours — `common/Theme.qml`, `colors`

| Name | Used for |
| --- | --- |
| `frame` | the bar and everything that grows out of it (panels, power menu, pop-up) |
| `surface`, `raised` | cards in panels; hover, chips and slider tracks |
| `base`, `overlay` | floating glass: notification popups, launcher, screenshot chips |
| `border` | hairlines |
| `text`, `subtext`, `faint` | main text, secondary text, quiet text |
| `ink` | text on a coloured fill (the active workspace, a switch that's on) |
| `accent` | **the one colour**: active workspace, today, switches, sliders, selection rings, the launcher logo |
| `blue` | connected Wi-Fi and Bluetooth |
| `green` | a VPN that's on |
| `warn`, `critical` | amber (battery low) and rose (battery very low, critical notifications, the power button) |

**A different accent**, e.g. soft teal:
```qml
readonly property color accent: "#8fc7c1"
```
Keep accents light and slightly greyed, as `ink` (near-black) sits on top of them.

**A whole new scheme**: change `frame`, `surface`, `raised` and the three text
colours together, then `accent`. Lighter `frame` colours need darker text.

**Notification cards in each app's own colour**: `Config.notifications.appColors: true`.

---

## Fonts — `common/Theme.qml`, `font.family`

It must be a **Nerd Font**, because every icon is a character from it. For example:
```qml
readonly property string family: "JetBrainsMono Nerd Font Propo"
```
Install another with pacman (e.g. `ttf-firacode-nerd`), then use its name exactly
as `fc-list | grep -i nerd` shows it. The "Propo" variants keep icons from
looking cramped.

---

## Sizes

| To change… | Edit |
| --- | --- |
| the bar's height | `Config.bar.height` (rem, now 2.75) |
| icons and text on the bar *and* in its panels, all at once | `Config.bar.scale` (1.1 = 10 % bigger) |
| just the bar's icons / text | `Theme.ui.icon`, `Theme.ui.text` (and `small`, `tiny`, `title`) |
| space between bar icons | `Theme.ui.cell`: every icon sits centred in a square this big |
| Wi-Fi/battery and display/sound panel width | `implicitWidth: Theme.rem(22 …)` at the top of `modules/frame/panels/NetworkPanel.qml` / `ControlsPanel.qml` |
| calendar + notifications panel | `Calendar.qml` → `cell` (day size); `CentrePanel.qml` → `listWidth`, `maxListHeight` |
| wallpaper picker | `WallpaperPanel.qml` → `implicitWidth` (share of the screen: `0.64`, cap `78` rem) and `thumbH` (card height) |
| Wi-Fi rows before the list scrolls | `Config.network.maxNetworks` |
| power menu width | `Config.session.width` (share of the screen, never more than ⅕) |
| everything in the whole shell | `Config.scaling.userScale` (or try it live: `qs ipc call scaling setUserScale 1.1`) |
| Hyprland's own scale (apps too) | the Scale slider in the display panel |

---

## Shapes

- **Rounded corners**: `Theme.radius` (`sm`, `md`, `lg`).
- **The curves where a panel meets the bar**: `Config.bar.ears` (false = square joins).
- **Rounded screen corners under the bar**: `Config.bar.corners: true` (and `cornerRadius`).

---

## Speed of animations — `common/Theme.qml`, `anim`

- `fast` 150 / `normal` 260 / `slow` 420 ms are used everywhere. Make them smaller to speed everything up.
- **Wallpaper change**: `Config.wallpaper.duration`, and `transition`: `"split"` · `"fade"` · `"none"`.
- **Power menu slide**: in `modules/frame/SessionPanel.qml`, `inAnim` (220) and `outAnim` (150).
- **Volume/brightness pop-up**: how long it stays is `Config.osd.timeout`. Turn it off with `Config.osd.enabled: false`.

---

## The chibi (power menu)

- **Use your own picture or GIF**: `Config.session.avatar: "~/Pictures/me.gif"`.
  With an animated GIF, set `Config.session.spin: "none"` so it isn't also spun.
- **How it moves**: `Config.session.spin`: `"twirl"` (spins on the spot) · `"turn"` · `"bob"` · `"none"`.
- **Its size**: in `modules/frame/SessionPanel.qml`, find the `Avatar` block:
  `width: Math.min(content.width * 0.85, Theme.rem(13))`. Raise `13` for bigger.
- **Recolour the built-in one**: open `assets/chibi.svg` in a text editor and swap the hex codes:

  | Part | Colours |
  | --- | --- |
  | hair (top → bottom) | `#b5a7e1` → `#8172bb` |
  | hoodie | `#9cb2d8` → `#647ead`, pocket `#5b75a5`, strings `#e4e9f3` |
  | skin, paws | `#f7ede5` → `#e9d5c8`, `#efdfd4` |
  | eyes (top → bottom) | `#29233f`, `#4f4783`, `#9fd0c9` |
  | inner ears, cheeks, mouth | `#e2b6c6`, `#e49cb0`, `#7d4b58` |
  | star clip | `#ecd8a2` with outline `#c7a361` |

  `assets/chibi-mono.svg` is a grey version: point `avatar` at it to use it.
- **Replace it entirely**: drop any SVG/PNG over `assets/chibi.svg`. A roughly
  square, see-through-background picture looks best.

---

## The power menu

- **Commands**: `Config.session` → `lock`, `suspend`, `reboot`, `poweroff`.
- **Add Hibernate**: `hibernate: ["systemctl", "hibernate"]`.
- **Labels, icons, keys, order**: the `actions` list in `services/Session.qml`.
  Each line is `{ id, label, glyph, key }`. Reorder the lines to reorder the menu.

---

## The bar

- **Clock / date**: `Config.bar.timeFormat` / `dateFormat` (Qt format).
  `"HH:mm"` = 24-hour, `"hh:mm AP"` = 12-hour, `"ddd dd MMM"` = Mon 19 Oct,
  `"dddd, d MMMM"` = Monday, 19 October.
- **Number of workspaces always shown**: `Config.bar.workspaces`.
- **Text when nothing's focused**: `Config.bar.windowFallback`.
- **Battery number**: `Config.bar.batteryPercent`. **Tray**: `Config.bar.tray`.
- **Hovering an icon swaps open panels**: `Config.bar.hoverSwitch`.
- **Reorder the right-hand icons**: in `modules/frame/Bar.qml`, the `── right ──`
  section lists them left to right. Each icon is a `BarIcon { … }` block inside a
  `BarButton` (one button = one panel). Move a block up or down to move the icon.

---

## Keys — `~/.config/hypr/quickshell.lua`

Change the key in any `hl.bind(...)` line. The names the shell offers:

| Name | Does |
| --- | --- |
| `quickshell:launcher` | app launcher |
| `quickshell:notifications` | calendar and notifications |
| `quickshell:network` | battery, Wi-Fi and VPN panel |
| `quickshell:controls` | display, sound and Bluetooth panel |
| `quickshell:wallpaper` | wallpaper picker |
| `quickshell:session` | power menu |
| `quickshell:volumeUp` / `volumeDown` / `volumeMute` / `micMute` | volume keys, through the shell |
| `quickshell:brightnessUp` / `brightnessDown` | brightness keys, through the shell |

Screenshots are commands rather than names: `qs ipc call screenshot region`
(or `screen`, `window`, `screenIn 5`).

> If `hyprland.lua` already had Quickshell lines when you installed, the installer
> left it alone. Then these binds live in your own `hyprland.lua` instead. Also add
> this line there, so the bar and wallpaper appear without Hyprland's open animation:
> `hl.layer_rule({ match = { namespace = "^qs-" }, no_anim = true })`

---

## Wallpapers — `Config.wallpaper`

- **Folder**: `directory` (searched 3 levels deep). `qs ipc call wallpaper rescan` picks up new files at once; opening the picker also rescans.
- **Transition**: `transition` and `duration` (see *Speed* above).
- **Run something on every change**: `onChange`, where `%f` is the picture, e.g.
  `["matugen", "image", "%f"]` for a matching colour scheme.
- **Keep hyprpaper / swww instead**: `draw: false`, and put
  `["swww", "img", "%f"]` in `onChange`.
- **Thumbnails** are cached in `~/.cache/quickshell/…/wallpapers`. Delete that
  folder to rebuild them. `thumbnailSize` sets their size.
- **On a new machine**: put pictures in the repo's `wallpapers/` folder and the
  installer copies them into `~/Pictures/Wallpapers`.

---

## Network and VPN — `Config.network`

- **VPN apps** are the `vpnProviders` list. Each entry has a `name`, a `match`
  (part of the connection or interface name the app creates), `connect` /
  `disconnect` commands and an optional `app`. Mullvad and Tailscale examples are
  in there, commented out.
- **Proton in a fixed country**: `connect: ["protonvpn", "connect", "--country", "CH"]`.
- **Country on the bar** for VPNs that don't put it in their connection name:
  `vpnCountryLookup: ["curl", "-sf", "--max-time", "5", "https://ipinfo.io/country"]`.
  That asks a web service where your traffic appears to come from.
- **Full names vs codes**: `countryNameMax` (names up to this many letters are written out).
- **"Network settings" button app**: `settingsApp`.

---

## Notifications, launcher, screenshots

- **Notifications** (`Config.notifications`): `timeout`, `timeoutLow`, `maxPopups`,
  `criticalSticky`, `width`.
- **Launcher** (`Config.launcher`): `width`, `lines`, `terminal` (e.g. `["kitty"]`),
  `hidden` (desktop ids to never show), `calculator`, `runCommands`.
- **Screenshots** (`Config.screenshot`): `copy`, `save`, `directory`, `confirmRegion`,
  `includeCursor`, `flash`.

---

## Volume, brightness, display scale

- **Scroll step on the icons**: `Config.audio.step`, `Config.brightness.step`.
- **Allow volume past 100 %**: `Config.audio.max: 1.5`.
- **Which backlight**: `Config.brightness.device` (a name from `/sys/class/backlight`).
- **Scale slider range**: `Config.display.minScale` / `maxScale`. Turn off
  remembering it with `rememberScale: false`.

---

## Where the rest lives

```
shell.qml                 what starts, in what order
common/                   Config, Theme, Scaling (per-screen size correction), Countries
services/                 the logic: Audio, Battery, Brightness, Bt, Network, Notifs,
                          Wallpaper, DisplayScale, Session, Launcher, Screenshot, Osd, …
modules/frame/            the bar (Bar.qml), its icons, the panel engine (Panels.qml),
                          the power menu (SessionPanel.qml)
modules/frame/panels/     each panel: CentrePanel, NetworkPanel, ControlsPanel,
                          WallpaperPanel, and the pieces they share
modules/wallpaper/        drawing the wallpaper and the split transition
modules/osd/              the volume / brightness pop-up
modules/launcher/, notifications/, screenshot/
widgets/                  Slider, Toggle, BatteryIcon, StyledText, PillButton
scripts/                  helper shell scripts (wallpaper thumbnails, screenshot notifications)
assets/                   the chibi
hypr/                     the Hyprland files the installer sets up (keys, autostart)
```
