pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.common

// The volume / brightness pop-up: a small notch that drops out of the bar under
// the controls icons whenever either changes — from the keys, an app, or a
// scroll on the bar — then tucks itself away again.
// Not while the controls panel is open (its sliders already show it).
Singleton {
    id: root

    property bool shown: false
    property string kind: ""          // "volume" | "mic" | "brightness"
    property real value: 0            // 0…1 (volume can go past 1 if Config.audio.max allows)
    property bool muted: false
    property string glyph: ""
    property string screenName: ""
    // the x each bar's controls icons sit at, by monitor
    property var positions: ({})

    // values settle in during the first moments after login; don't announce them
    property bool armed: false
    // a different default output is a new number, not a change worth a pop-up
    property double quietUntil: 0

    function setAnchor(screen, x) {
        const a = Object.assign({}, root.positions);
        a[screen] = x;
        root.positions = a;
    }

    function show(kind, value, glyph, muted) {
        if (!Config.osd.enabled || !root.armed || Date.now() < root.quietUntil)
            return;
        if (Drawers.current === "controls")
            return;
        root.screenName = Hyprland.focusedMonitor?.name ?? (Quickshell.screens.length ? Quickshell.screens[0].name : "");
        root.kind = kind;
        root.value = value;
        root.glyph = glyph;
        root.muted = muted;
        root.shown = true;
        hide.restart();
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hide
        interval: Config.osd.timeout
        onTriggered: root.shown = false
    }

    Connections {
        target: Audio
        function onSinkChanged() {
            root.quietUntil = Date.now() + 600;
        }
        function onVolumeChanged() {
            root.show("volume", Audio.volume, Audio.glyph(), Audio.muted);
        }
        function onMutedChanged() {
            root.show("volume", Audio.volume, Audio.glyph(), Audio.muted);
        }
        function onMicMutedChanged() {
            root.show("mic", Audio.micVolume, Audio.micMuted ? "󰍭" : "󰍬", Audio.micMuted);
        }
    }

    Connections {
        target: Brightness
        function onValueChanged() {
            if (Brightness.available)
                root.show("brightness", Brightness.value, Brightness.glyph, false);
        }
    }

    // a panel opening takes over
    Connections {
        target: Drawers
        function onCurrentChanged() {
            if (Drawers.current !== "")
                root.shown = false;
        }
    }
}
