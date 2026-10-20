pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common

// The power menu: lock, sleep, log out, reboot, shut down.
//
//   qs ipc call session toggle
//   hl.bind("SUPER + Escape", hl.dsp.global("quickshell:session"))
Singleton {
    id: root

    property bool active: false
    property string screenName: ""
    property string pending: ""         // the action to run once the menu has slid away

    readonly property string user: String(Quickshell.env("USER") ?? "")
    property string host: ""

    // what the menu shows, top to bottom
    readonly property var actions: {
        const c = Config.session;
        const out = [
            { id: "lock", label: "Lock", glyph: "󰌾", key: "L" },
            { id: "suspend", label: "Sleep", glyph: "󰤄", key: "S" },
            { id: "logout", label: "Log out", glyph: "󰗼", key: "O" }
        ];
        if (c.hibernate.length)
            out.push({ id: "hibernate", label: "Hibernate", glyph: "󰒲", key: "H" });
        out.push({ id: "reboot", label: "Reboot", glyph: "󰜉", key: "R" });
        out.push({ id: "poweroff", label: "Shut down", glyph: "󰐥", key: "P" });
        return out;
    }

    function open() {
        Drawers.close();
        root.screenName = Hyprland.focusedMonitor?.name ?? (Quickshell.screens.length ? Quickshell.screens[0].name : "");
        root.pending = "";
        root.active = true;
    }

    function close() {
        root.active = false;
    }

    function toggle() {
        if (root.active)
            root.close();
        else
            root.open();
    }

    // The menu closes first and runs the action when it's gone, so a lock screen
    // never photographs the menu and nothing is left half-drawn on reboot.
    function choose(id) {
        root.pending = id;
        root.active = false;
    }

    function runPending() {
        const id = root.pending;
        root.pending = "";
        if (id)
            root.run(id);
    }

    function run(id) {
        const c = Config.session;
        if (id === "logout") {
            Hypr.exit();
            return;
        }
        const cmd = { lock: c.lock, suspend: c.suspend, hibernate: c.hibernate, reboot: c.reboot, poweroff: c.poweroff }[id];
        if (cmd && cmd.length)
            Quickshell.execDetached(cmd);
    }

    // "up 3h 12m"
    function uptime(seconds) {
        const m = Math.floor(seconds / 60);
        const d = Math.floor(m / 1440);
        const h = Math.floor((m % 1440) / 60);
        if (d > 0)
            return `up ${d}d ${h}h`;
        if (h > 0)
            return `up ${h}h ${String(m % 60).padStart(2, "0")}m`;
        return `up ${m % 60}m`;
    }

    FileView {
        id: hostname
        path: "/etc/hostname"
        printErrors: false
        onLoaded: root.host = hostname.text().trim()
    }

    GlobalShortcut {
        name: "session"
        description: "Open or close the power menu"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
    }
}
