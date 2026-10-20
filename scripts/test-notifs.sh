#!/usr/bin/env bash
# Fire a spread of test notifications at the Quickshell daemon.
# Run it while `qs` is running:  bash ~/.config/quickshell/scripts/test-notifs.sh
set -u
gap() { sleep "${1:-0.6}"; }

notify-send -a discord "alex" "yo, did you push the quickshell config?"
gap
notify-send -a Spotify -i spotify "Now playing" "Daft Punk — Digital Love"
gap
notify-send -a firefox "Download complete" "quickshell-0.3.2.pkg.tar.zst  ·  <b>1.6 MB</b>"
gap
notify-send -u low -a NetworkManager "Wi-Fi" "Connected to <b>$(hostname)</b> — this one is low urgency (short timeout)"
gap 1.5

# Actions: right click runs "default", the pills run the others.
# notify-send waits and prints which one you picked.
( notify-send -a Telegram -A default=Open -A reply=Reply -A mute=Mute \
    "Mom" "call me when you're free" | sed 's/^/[telegram] you picked: /' ) &
gap 1.5

# A picture (avatar/thumbnail) with the app icon as a badge.
for img in /usr/share/pixmaps/archlinux-logo.png /usr/share/pixmaps/archlinux-logo.svg \
           /usr/share/icons/hicolor/256x256/apps/*.png; do
    if [ -f "$img" ]; then
        notify-send -a discord -h "string:image-path:$img" "with a picture" "the image goes left, the app icon becomes a badge"
        break
    fi
done
gap 1.5

# Critical: red, pulses, stays until you click it (even in do-not-disturb).
notify-send -u critical -a Battery "Battery low" "5% remaining — plug in soon"

wait
