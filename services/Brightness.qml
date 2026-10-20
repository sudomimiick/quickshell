pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common

// Screen backlight. Reads sysfs directly and sets it with brightnessctl.
// `udevadm monitor` tells us the moment it changes — from the brightness keys,
// another app or this shell — so the pop-up and the bar keep up; a slow re-read
// covers drivers that stay quiet.
//
//   qs ipc call brightness up | down | set 40
//   hl.bind("XF86MonBrightnessUp", hl.dsp.global("quickshell:brightnessUp"), { locked = true, repeating = true })
Singleton {
    id: root

    property string dir: ""           // e.g. /sys/class/backlight/intel_backlight
    property int max: 0
    property int raw: 0
    readonly property string device: dir.split("/").pop()
    readonly property bool available: dir !== "" && max > 0
    readonly property real value: available ? Math.max(0, Math.min(1, raw / max)) : 0
    readonly property string glyph: root.glyphFor(value)

    // a sun that fills in as it gets brighter
    function glyphFor(v) {
        return v < 0.34 ? "󰃞" : v < 0.67 ? "󰃟" : "󰃠";
    }

    function set(v) {
        if (!root.available)
            return;
        const p = Math.max(0.01, Math.min(1, v)); // never all the way to black
        root.raw = Math.round(p * root.max);       // show it now, sysfs catches up
        Quickshell.execDetached(["brightnessctl", "-q", "-d", root.device, "set", Math.round(p * 100) + "%"]);
    }

    function step(notches) {
        root.set(root.value + notches * Config.brightness.step);
    }

    Component.onCompleted: {
        if (Config.brightness.device)
            root.dir = "/sys/class/backlight/" + Config.brightness.device;
        else
            finder.running = true;
    }

    Process {
        id: finder
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] && { printf %s \"$d\"; exit 0; }; done"]
        stdout: StdioCollector {
            id: found
            onStreamFinished: root.dir = found.text.trim()
        }
    }

    FileView {
        id: maxFile
        path: root.dir ? root.dir + "/max_brightness" : ""
        printErrors: false
        onLoaded: root.max = parseInt(maxFile.text()) || 0
    }

    FileView {
        id: nowFile
        path: root.dir ? root.dir + "/actual_brightness" : ""
        printErrors: false
        watchChanges: true
        onFileChanged: nowFile.reload()
        onLoaded: root.raw = parseInt(nowFile.text()) || 0
    }

    Process {
        id: udev
        running: root.available
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("change"))
                    nowFile.reload();
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.available
        onTriggered: nowFile.reload()
    }

    GlobalShortcut {
        name: "brightnessUp"
        description: "Brighter (shows the pop-up)"
        onPressed: root.step(Config.brightness.keyStep / Config.brightness.step)
    }

    GlobalShortcut {
        name: "brightnessDown"
        description: "Dimmer (shows the pop-up)"
        onPressed: root.step(-Config.brightness.keyStep / Config.brightness.step)
    }

    IpcHandler {
        target: "brightness"

        function up(): void {
            root.step(Config.brightness.keyStep / Config.brightness.step);
        }
        function down(): void {
            root.step(-Config.brightness.keyStep / Config.brightness.step);
        }
        function set(percent: int): void {
            root.set(percent / 100);
        }
    }
}
