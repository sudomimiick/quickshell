pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Which panel hangs from the bar, on which monitor, under which icon. One at a time.
//   "centre"   calendar + notifications (time, bell or date)
//   "network"  battery and power profile, Wi-Fi, Ethernet, VPNs
//   "controls" brightness, display scale, sound, Bluetooth
//   "wallpaper" the wallpaper picker (no icon: SUPER+SHIFT+W)
//
//   qs ipc call drawers toggle network
//   hl.bind("SUPER + N", hl.dsp.global("quickshell:notifications"))
//   hl.bind("SUPER + W", hl.dsp.global("quickshell:network"))
Singleton {
    id: root

    property string current: ""       // "" = closed
    property string screenName: ""
    property real anchorX: -1         // centre of the icon it hangs from; -1 = the bar decides

    // the panels there are
    readonly property var available: ["centre", "network", "controls", "wallpaper"]

    function has(name) {
        return root.available.includes(name);
    }

    function open(name, screen, x) {
        if (!root.has(name))
            return;
        root.screenName = screen || root.focusedScreen();
        root.anchorX = x ?? -1;
        root.current = name;
    }

    function close() {
        root.current = "";
    }

    function toggle(name, screen, x) {
        const s = screen || root.focusedScreen();
        if (root.current === name && root.screenName === s)
            root.close();
        else
            root.open(name, s, x);
    }

    // With a drawer open, moving to another icon on the same bar swaps drawers.
    function hover(name, screen, x) {
        // the wallpaper picker is keyboard-driven: the mouse passing over the bar mustn't swap it away
        if (root.current === "wallpaper")
            return;
        if (root.current && root.current !== name && root.screenName === screen && root.has(name))
            root.open(name, screen, x);
    }

    function isOpen(name) {
        return root.current === name;
    }

    function focusedScreen() {
        return Hyprland.focusedMonitor?.name ?? (Quickshell.screens.length ? Quickshell.screens[0].name : "");
    }

    GlobalShortcut {
        name: "notifications"
        description: "Open or close the notification centre"
        onPressed: root.toggle("centre", "", -1)
    }

    GlobalShortcut {
        name: "calendar"
        description: "Open or close the calendar (same panel as notifications)"
        onPressed: root.toggle("centre", "", -1)
    }

    GlobalShortcut {
        name: "network"
        description: "Open or close the battery, Wi-Fi and VPN panel"
        onPressed: root.toggle("network", "", -1)
    }

    GlobalShortcut {
        name: "controls"
        description: "Open or close the display, sound and Bluetooth panel"
        onPressed: root.toggle("controls", "", -1)
    }

    // the old name of the controls panel, so existing keybinds keep working
    GlobalShortcut {
        name: "sound"
        description: "Same as quickshell:controls"
        onPressed: root.toggle("controls", "", -1)
    }

    IpcHandler {
        target: "drawers"

        function toggle(name: string): void {
            root.toggle(name, "", -1);
        }
        function open(name: string): void {
            root.open(name, "", -1);
        }
        function close(): void {
            root.close();
        }
    }
}
