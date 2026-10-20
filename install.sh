#!/usr/bin/env bash
# install.sh — set up this Quickshell desktop on Arch Linux + Hyprland.
#
#   From a clone of the repository:   ./install.sh
#   Straight from GitHub:             curl -fsSL https://raw.githubusercontent.com/YOUR-USER/YOUR-REPO/main/install.sh | bash
#                                     (set REPO below to your repository first)
#
# What it does, asking before anything big:
#   1. installs the packages it needs with pacman (only the missing ones)
#   2. turns on Bluetooth, power profiles and (if nothing else manages your network) NetworkManager
#   3. puts the shell in ~/.config/quickshell (your old one is moved to quickshell.bak-<date>),
#      and any pictures in the repo's wallpapers/ folder in ~/Pictures/Wallpapers
#   4. adds a small file to your Hyprland config that starts the shell and binds its keys
#   5. starts it, if you're in Hyprland right now
#
# Options:
#   -y, --yes        don't ask; take the defaults
#   --no-packages    leave pacman alone (install the dependencies yourself)
#   --no-hypr        don't touch your Hyprland config
#   --link           make ~/.config/quickshell a link to the clone (update with git pull)
#   --repo URL       clone this repository instead of the one below
#   --uninstall      remove the shell and put your old config back
#   -h, --help

set -euo pipefail

REPO="${QS_REPO:-https://github.com/YOUR-USER/YOUR-REPO.git}"
BRANCH="${QS_BRANCH:-}" # empty = the repository's default branch

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST="$CONFIG_HOME/quickshell"
HYPR="$CONFIG_HOME/hypr"
CLONE="$DATA_HOME/quickshell-desktop"
STAMP="$(date +%Y%m%d-%H%M%S)"
MARK="Quickshell desktop (install.sh)"

# what makes up the shell (everything else in the repo is for installing it)
ITEMS=(shell.qml common services modules widgets scripts assets GUIDE.md)

PACKAGES=(
    quickshell qt6-svg qt6-imageformats   # the shell (SVG/GIF/WebP avatars)
    ttf-jetbrains-mono-nerd               # its font and icons
    pipewire wireplumber                  # sound
    networkmanager network-manager-applet # Wi-Fi/VPN panel, "Network settings"
    bluez bluez-utils                     # Bluetooth
    upower brightnessctl                  # battery, brightness
    wl-clipboard libnotify grim           # screenshots, copying, notifications from scripts
    libvips                               # fast wallpaper thumbnails
    hyprlock hyprpolkitagent              # lock screen, password prompts
    git curl
)
OPTIONAL=(satty) # draw on screenshots ("Annotate")

YES=false
PKGS=true
HYPRCFG=true
LINK=false
UNINSTALL=false

# ── output ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'
else
    B="" D="" G="" Y="" R="" N=""
fi
say() { printf '%s\n' "${G}::${N} $*"; }
note() { printf '%s\n' "   ${D}$*${N}"; }
warn() { printf '%s\n' "${Y}!!${N} $*" >&2; }
die() {
    printf '%s\n' "${R}error:${N} $*" >&2
    exit 1
}

# ask "question" yes|no — the answer comes from the terminal even under `curl | bash`
ask() {
    local q=$1 def=${2:-yes} hint reply
    [[ $def == yes ]] && hint="Y/n" || hint="y/N"
    if $YES || ! { : </dev/tty; } 2>/dev/null; then
        [[ $def == yes ]]
        return
    fi
    printf '%s' "${B}?${N} $q [$hint] " >/dev/tty
    read -r reply </dev/tty || reply=""
    reply=${reply:-$def}
    [[ $reply =~ ^[Yy] ]]
}

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//' || true
    exit 0
}

while (($#)); do
    case $1 in
    -y | --yes) YES=true ;;
    --no-packages) PKGS=false ;;
    --no-hypr) HYPRCFG=false ;;
    --link) LINK=true ;;
    --repo)
        [[ $# -ge 2 ]] || die "--repo needs a URL"
        REPO=$2
        shift
        ;;
    --uninstall) UNINSTALL=true ;;
    -h | --help) usage ;;
    *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

# ── checks ──────────────────────────────────────────────────────────────────
preflight() {
    [[ $EUID -ne 0 ]] || die "run this as yourself, not root (it uses sudo when it needs to)"
    command -v pacman >/dev/null || die "this installer is for Arch Linux (no pacman here)"
    if ! command -v Hyprland >/dev/null && ! command -v hyprland >/dev/null; then
        warn "Hyprland isn't installed."
        if $PKGS && ask "Install Hyprland too?" yes; then
            PACKAGES+=(hyprland xdg-desktop-portal-hyprland)
        fi
    fi
}

installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# ── 1. packages ─────────────────────────────────────────────────────────────
install_packages() {
    local want=("${PACKAGES[@]}") missing=() p

    # PipeWire's PulseAudio stand-in, unless you run real PulseAudio
    if installed pulseaudio; then
        note "PulseAudio is installed; leaving it (the shell talks to PipeWire, so consider pipewire-pulse)."
    else
        want+=(pipewire-pulse)
    fi

    # power profiles, unless another power manager already does that job
    if installed tuned-ppd; then
        note "tuned-ppd provides power profiles; using it."
    elif installed tlp || installed auto-cpufreq; then
        note "TLP / auto-cpufreq manage power here, so the power profile circles will stay hidden."
    else
        want+=(power-profiles-daemon)
    fi

    for p in "${OPTIONAL[@]}"; do
        if ! installed "$p" && ask "Also install $p (draw on screenshots)?" no; then
            want+=("$p")
        fi
    done

    for p in "${want[@]}"; do
        installed "$p" || missing+=("$p")
    done
    if ((${#missing[@]} == 0)); then
        say "All packages are already installed."
        return
    fi
    say "Installing: ${missing[*]}"
    if $YES; then
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    elif { : </dev/tty; } 2>/dev/null; then
        # pacman's questions come from the keyboard, not from `curl | bash`'s pipe
        sudo pacman -S --needed "${missing[@]}" </dev/tty
    else
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    fi
}

# ── 2. services ─────────────────────────────────────────────────────────────
unit_exists() { systemctl cat "$1" >/dev/null 2>&1; }

enable_services() {
    local svc other=""
    for svc in bluetooth.service power-profiles-daemon.service; do
        unit_exists "$svc" || continue
        # never alongside another power manager
        if [[ $svc == power-profiles-daemon.service ]] && { installed tlp || installed auto-cpufreq; }; then
            continue
        fi
        if ! systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            say "Turning on $svc"
            sudo systemctl enable --now "$svc" || warn "couldn't start $svc"
        fi
    done

    systemctl is-active --quiet NetworkManager.service && return 0
    unit_exists NetworkManager.service || return 0
    for svc in systemd-networkd.service iwd.service connman.service netctl.service; do
        systemctl is-active --quiet "$svc" 2>/dev/null && other+="${svc%.service} "
    done
    if [[ -n $other ]]; then
        warn "The Wi-Fi panel needs NetworkManager, but ${other}manages your network right now."
        note "Switching now could cut you off mid-install, so that's left to you:"
        note "  sudo systemctl disable --now ${other% } && sudo systemctl enable --now NetworkManager"
    elif ask "Turn on NetworkManager (the Wi-Fi panel needs it)?" yes; then
        sudo systemctl enable --now NetworkManager.service || warn "couldn't start NetworkManager"
    fi
}

# ── 3. the shell itself ─────────────────────────────────────────────────────
SRC=""
find_source() {
    local here=""
    if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
        here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    fi
    if [[ -n $here && -f $here/shell.qml ]]; then
        SRC=$here
        return
    fi
    [[ $REPO != *YOUR-USER* ]] || die "set REPO at the top of install.sh to your repository (or run it from a clone, or pass --repo URL)"
    command -v git >/dev/null || sudo pacman -S --needed --noconfirm git
    if [[ -d $CLONE/.git ]]; then
        say "Updating $CLONE"
        git -C "$CLONE" pull --ff-only
    else
        say "Downloading $REPO"
        mkdir -p "$(dirname "$CLONE")"
        git clone --depth 1 ${BRANCH:+--branch "$BRANCH"} "$REPO" "$CLONE"
    fi
    SRC=$CLONE
    [[ -f $SRC/shell.qml ]] || die "$REPO doesn't look like this shell (no shell.qml at its top)"
}

same_dir() { [[ -e $1 && -e $2 && $(readlink -f "$1") == "$(readlink -f "$2")" ]]; }

install_files() {
    if same_dir "$DEST" "$SRC"; then
        say "The shell is already at $DEST."
        return
    fi
    if [[ -e $DEST || -L $DEST ]]; then
        mv "$DEST" "$DEST.bak-$STAMP"
        say "Moved your old config to ${DEST/#$HOME/\~}.bak-$STAMP"
    fi
    mkdir -p "$(dirname "$DEST")"
    if $LINK; then
        ln -s "$SRC" "$DEST"
        say "Linked ${DEST/#$HOME/\~} → $SRC (update with: git -C $SRC pull)"
    else
        mkdir -p "$DEST"
        local item
        for item in "${ITEMS[@]}"; do
            [[ -e $SRC/$item ]] && cp -a "$SRC/$item" "$DEST/"
        done
        say "Installed the shell in ${DEST/#$HOME/\~}"
    fi
    chmod +x "$DEST"/scripts/*.sh 2>/dev/null || true
}

# the repo's wallpapers/ folder → ~/Pictures/Wallpapers (never overwriting yours)
install_wallpapers() {
    local walls="$HOME/Pictures/Wallpapers" f n=0
    mkdir -p "$walls"
    [[ -d $SRC/wallpapers ]] || return 0
    while IFS= read -r -d '' f; do
        if [[ ! -e $walls/$(basename "$f") ]]; then
            cp "$f" "$walls/"
            n=$((n + 1))
        fi
    done < <(find "$SRC/wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
        -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.jxl' -o -iname '*.avif' \) -print0)
    ((n == 0)) || say "Copied $n wallpaper(s) to ~/Pictures/Wallpapers"
}

# ── 4. Hyprland ─────────────────────────────────────────────────────────────
setup_hyprland() {
    local main snippet line clash
    if [[ -f $HYPR/hyprland.lua ]]; then
        main=$HYPR/hyprland.lua
        snippet=quickshell.lua
        line="pcall(require, \"quickshell\") -- $MARK"
    elif [[ -f $HYPR/hyprland.conf ]]; then
        main=$HYPR/hyprland.conf
        snippet=quickshell.conf
        line="source = $HYPR/quickshell.conf # $MARK"
    else
        warn "No Hyprland config in $HYPR yet. Start Hyprland once (it writes one), then run this again,"
        note "or copy $SRC/hypr/quickshell.lua next to your hyprland.lua and add: pcall(require, \"quickshell\")"
        return 0
    fi

    if [[ -f $HYPR/$snippet ]] && ! cmp -s "$SRC/hypr/$snippet" "$HYPR/$snippet"; then
        cp "$HYPR/$snippet" "$HYPR/$snippet.bak-$STAMP"
    fi
    cp "$SRC/hypr/$snippet" "$HYPR/$snippet"

    if grep -qF "$MARK" "$main"; then
        say "Hyprland already loads $snippet."
    elif grep -qiE 'quickshell|(^|[^[:alnum:]_-])qs( |"|$)' "$main"; then
        warn "Your ${main/#$HOME/\~} already starts Quickshell or binds its keys, so it's left as it is"
        note "(loading mine too would make every key fire twice). Mine is in $HYPR/$snippet —"
        note "copy across anything you're missing, like the wallpaper key and the no_anim layer rule."
    else
        cp "$main" "$main.bak-$STAMP"
        printf '\n%s\n' "$line" >>"$main"
        say "Added the shell's autostart and keys to ${main/#$HOME/\~} (via $snippet)"
    fi

    # other bars and notification daemons would fight with this one (comments don't count)
    local others='waybar|mako|dunst|swaync|hyprpanel|ags|eww|fnott|hyprpaper|swww|swww-daemon|swaybg|wpaperd|mpvpaper'
    clash=$(grep -rhE "($others)" "$HYPR" --include='*.lua' --include='*.conf' 2>/dev/null |
        grep -vE '^[[:space:]]*(--|#)' | grep -oE "\b($others)\b" | sort -u | tr '\n' ' ' || true)
    if [[ -n $clash ]]; then
        warn "Your Hyprland config also starts: ${clash}— take those out."
        note "A second bar sits on top of this one, another notification daemon takes notifications away from it,"
        note "and another wallpaper tool fights the shell's own wallpaper (pick yours with SUPER+SHIFT+W)."
    fi
}

# ── 5. start ────────────────────────────────────────────────────────────────
start_shell() {
    if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        say "Log into Hyprland and the shell starts by itself."
        return 0
    fi
    $HYPRCFG && { hyprctl reload >/dev/null 2>&1 || true; }
    local p
    for p in waybar mako dunst swaync hyprpaper swww-daemon swaybg; do
        if pgrep -x "$p" >/dev/null && ask "Stop $p now (it clashes with the shell)?" yes; then
            pkill -x "$p" || true
        fi
    done
    qs kill >/dev/null 2>&1 || true
    qs -d -n >/dev/null 2>&1 || setsid -f qs -n >/dev/null 2>&1
    say "The shell is running. Logs: qs log"
}

# ── uninstall ───────────────────────────────────────────────────────────────
uninstall() {
    local backup main
    qs kill >/dev/null 2>&1 || true
    if [[ -e $DEST || -L $DEST ]]; then
        rm -rf "$DEST"
        say "Removed ${DEST/#$HOME/\~}"
    fi
    backup=$(find "$(dirname "$DEST")" -maxdepth 1 -name "$(basename "$DEST").bak-*" 2>/dev/null | sort | tail -n 1)
    if [[ -n $backup ]] && ask "Put back your previous config (${backup/#$HOME/\~})?" yes; then
        mv "$backup" "$DEST"
        say "Restored it."
    fi
    for main in "$HYPR/hyprland.lua" "$HYPR/hyprland.conf"; do
        if [[ -f $main ]] && grep -qF "$MARK" "$main"; then
            cp "$main" "$main.bak-$STAMP"
            grep -vF "$MARK" "$main.bak-$STAMP" >"$main"
            say "Took the shell out of ${main/#$HOME/\~}"
        fi
    done
    rm -f "$HYPR/quickshell.lua" "$HYPR/quickshell.conf"
    note "Packages were left installed. Remove them with pacman if you don't need them."
}

main() {
    if $UNINSTALL; then
        uninstall
        return
    fi
    preflight
    say "${B}Quickshell desktop${N} — installing for $(id -un)"
    $PKGS && install_packages
    $PKGS && enable_services
    find_source
    install_files
    install_wallpapers
    $HYPRCFG && setup_hyprland
    start_shell
    printf '\n'
    say "Done. Keys: SUPER+D apps · SUPER+N notifications · SUPER+W battery & Wi-Fi · SUPER+A display & sound"
    note "SUPER+SHIFT+W wallpapers · SUPER+Esc power menu · Print screenshot"
    note "Settings live in ${DEST/#$HOME/\~}/common/Config.qml (behaviour) and Theme.qml (looks); GUIDE.md explains them."
}

main
