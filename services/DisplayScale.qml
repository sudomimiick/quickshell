pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common

// Hyprland's monitor scale, for the slider in the controls panel: everything on
// that screen — apps, bar, cursor — gets bigger or smaller.
//
// Only scales Hyprland takes as they are get offered: the screen's size divided
// by the scale has to come out in whole pixels (it would otherwise round it
// itself and complain). Your choice is remembered per monitor and put back when
// the shell starts or Hyprland reloads its config; Reset forgets it and reloads
// Hyprland so your own config's scale applies again.
Singleton {
    id: root

    readonly property HyprlandMonitor monitor: Hyprland.focusedMonitor
    readonly property string name: monitor?.name ?? ""
    readonly property real current: monitor?.scale ?? 1
    readonly property var options: root.scalesFor(monitor?.width ?? 0, monitor?.height ?? 0, current)
    readonly property bool available: options.length > 1
    readonly property bool remembered: name !== "" && saved[name] !== undefined

    // monitor name → scale you picked
    property var saved: ({})

    // Scales for a w×h (physical pixels) screen: multiples of 1/120 (what Wayland
    // can express) that divide both sides evenly, kept to "nice" ones — steps of
    // 0.05 and thirds — within Config.display, plus whatever it's set to now.
    function scalesFor(w, h, now) {
        const out = [];
        if (!(w > 0 && h > 0))
            return out;
        const lo = Math.ceil(Config.display.minScale * 120);
        const hi = Math.floor(Config.display.maxScale * 120);
        for (let n = lo; n <= hi; n++) {
            const s = n / 120;
            const lw = w / s;
            const lh = h / s;
            if (lw !== Math.round(lw) || lh !== Math.round(lh))
                continue;
            if (n % 6 !== 0 && n % 40 !== 0)
                continue;
            // never so big that the screen gets cramped (unless it's 1×)
            if (Math.max(lw, lh) < Config.display.minWidth && n !== 120)
                continue;
            out.push(s);
        }
        if (now > 0 && !out.some(s => Math.abs(s - now) < 0.001)) {
            out.push(now);
            out.sort((a, b) => a - b);
        }
        return out;
    }

    function indexOf(list, s) {
        let best = 0;
        for (let i = 1; i < list.length; i++)
            if (Math.abs(list[i] - s) < Math.abs(list[best] - s))
                best = i;
        return best;
    }

    // "1.25×", "1.33×", "2×"
    function label(s) {
        return (Math.round(s * 100) / 100).toString() + "×";
    }

    // what Hyprland gets told: this output, as it runs now, at a new scale
    function command(m, s, lua) {
        const ipc = m.lastIpcObject ?? {};
        const rate = ipc.refreshRate ? `@${Number(ipc.refreshRate).toFixed(2)}` : "";
        const mode = m.width > 0 ? `${m.width}x${m.height}${rate}` : "preferred";
        const pos = Hyprland.monitors.values.length > 1 ? `${m.x}x${m.y}` : "auto";
        const scale = Number(s.toFixed(6));
        if (lua)
            return ["hyprctl", "eval", `hl.monitor({ output = "${m.name}", mode = "${mode}", position = "${pos}", scale = ${scale} })`];
        return ["hyprctl", "keyword", "monitor", `${m.name},${mode},${pos},${scale}`];
    }

    function apply(s) {
        const m = root.monitor;
        if (!m)
            return;
        Quickshell.execDetached(root.command(m, s, Hyprland.usingLua));
        // Hyprland doesn't announce a scale change, so ask it what it is now
        refreshSoon.restart();
        refreshLater.restart();
        if (Config.display.rememberScale) {
            const next = Object.assign({}, root.saved);
            next[m.name] = s;
            root.save(next);
        }
    }

    // forget it, and let Hyprland's config decide again
    function reset() {
        if (!root.remembered)
            return;
        const next = Object.assign({}, root.saved);
        delete next[root.name];
        root.save(next);
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    function save(next) {
        root.saved = next;
        store.setText(JSON.stringify(next, null, 2) + "\n");
    }

    // put remembered scales back on every monitor that has one
    function restore() {
        if (!Config.display.rememberScale)
            return;
        const ms = Hyprland.monitors.values;
        for (let i = 0; i < ms.length; i++) {
            const want = root.saved[ms[i].name];
            if (want !== undefined && Math.abs(want - ms[i].scale) >= 0.001)
                Quickshell.execDetached(root.command(ms[i], want, Hyprland.usingLua));
        }
    }

    FileView {
        id: store
        path: Quickshell.statePath("display-scale.json")
        printErrors: false
        onLoaded: {
            try {
                root.saved = JSON.parse(store.text()) ?? {};
            } catch (e) {
                root.saved = {};
            }
            restoreSoon.restart();
        }
    }

    // after login / a Hyprland reload / a monitor being plugged in: read the
    // monitors fresh first (their scale is only re-read on some events), then restore
    Timer {
        id: restoreSoon
        interval: 800
        onTriggered: {
            Hyprland.refreshMonitors();
            restoreNow.restart();
        }
    }

    Timer {
        id: restoreNow
        interval: 400
        onTriggered: root.restore()
    }

    Timer {
        id: refreshSoon
        interval: 350
        onTriggered: Hyprland.refreshMonitors()
    }

    Timer {
        id: refreshLater
        interval: 1500
        onTriggered: Hyprland.refreshMonitors()
    }

    // the slider shows what the screen is really at whenever the panel opens
    Connections {
        target: Drawers
        function onCurrentChanged() {
            if (Drawers.current === "controls")
                Hyprland.refreshMonitors();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" || event.name === "monitoradded" || event.name === "monitoraddedv2")
                restoreSoon.restart();
        }
    }

    IpcHandler {
        target: "display"

        function options(): string {
            return root.options.map(s => root.label(s)).join("  ");
        }
        function set(scale: real): void {
            if (root.options.length)
                root.apply(root.options[root.indexOf(root.options, scale)]);
        }
        function reset(): void {
            root.reset();
        }
    }
}
