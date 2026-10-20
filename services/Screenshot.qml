pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common

// Screenshots, Spectacle-style. Replaces grim + slurp.
//
// Every capture freezes the screen first, then you work on the frozen frame,
// so menus and tooltips stay exactly as they were when you pressed the key.
//
//   qs ipc call screenshot region       drag a region / click a window
//   qs ipc call screenshot screen       the focused monitor
//   qs ipc call screenshot window       the active window
//   qs ipc call screenshot screenIn 5   same, after a 5 s countdown (also windowIn)
//   qs ipc call screenshot cancel
//
// Flow: idle → (countdown) → capturing → selecting | instant → saving → idle.
// The per-screen overlays (modules/screenshot/ShotWindow.qml) do the drawing
// and the cropping; this file decides what happens and what comes after.
Singleton {
    id: root

    property string phase: "idle"
    property string mode: "region"        // region | screen | window
    property int countdown: 0
    property int shot: 0                  // bumps once per capture; overlays react to it
    property var ready: ({})              // screen name → frozen frame is in
    property var targetScreen: null       // the screen being saved
    property var targetRect: null         // { x, y, w, h } in that screen's logical px (screen/window modes)

    property string picturesDir: ""
    property string lastStamp: ""
    property int seq: 0

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string directory: expand(Config.screenshot.directory)
        || `${picturesDir || home + "/Pictures"}/Screenshots`
    readonly property string scratchDir: Quickshell.cachePath("screenshots")
    readonly property string defaultAction: Config.screenshot.copy && Config.screenshot.save
        ? "both" : Config.screenshot.save ? "save" : "copy"

    // ── starting ─────────────────────────────────────────────────────────────

    function start(newMode, delaySec) {
        if (phase !== "idle")
            return;
        mode = newMode;
        targetScreen = null;
        targetRect = null;
        Hyprland.refreshToplevels(); // fresh window geometry for snapping
        Hyprland.refreshMonitors();
        Quickshell.execDetached(["mkdir", "-p", directory, scratchDir]);
        // copy-only shots live in scratchDir; clear out the old ones
        Quickshell.execDetached(["find", scratchDir, "-maxdepth", "1", "-name", "*.png",
                                 "-mmin", `+${Config.screenshot.keepCopiesDays * 1440}`, "-delete"]);
        if (delaySec > 0) {
            countdown = delaySec;
            phase = "countdown";
            ticker.restart();
        } else {
            capture();
        }
    }

    function capture() {
        ready = ({});
        phase = "capturing";
        shot++;
        watchdog.restart();
    }

    // Each overlay reports in once its frozen frame has arrived.
    function markReady(name) {
        if (phase !== "capturing")
            return;
        const r = Object.assign({}, ready);
        r[name] = true;
        ready = r;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (!r[screens[i].name])
                return;
        watchdog.stop();
        proceed();
    }

    function proceed() {
        if (mode === "region") {
            phase = "selecting";
            return;
        }
        const t = mode === "window" ? activeWindowTarget() : focusedScreenTarget();
        if (!t) {
            fail(mode === "window" ? "There's no active window to capture." : "No screen to capture.");
            return;
        }
        targetScreen = t.screen;
        targetRect = t.rect;
        phase = "instant";
    }

    // ── finishing ────────────────────────────────────────────────────────────

    // A fresh file path. action "copy" goes to a scratch folder (Save is offered later).
    function newPath(action) {
        const stamp = Qt.formatDateTime(new Date(), Config.screenshot.timeFormat);
        seq = stamp === lastStamp ? seq + 1 : 0;
        lastStamp = stamp;
        const name = `${Config.screenshot.prefix}${stamp}${seq > 0 ? "_" + (seq + 1) : ""}.png`;
        return `${action === "copy" ? scratchDir : directory}/${name}`;
    }

    function finished(ok, path, action) {
        phase = "idle";
        targetScreen = null;
        if (!ok) {
            notifyError(`Couldn't write ${path}`);
            return;
        }
        if (action !== "save")
            Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", path]);
        if (Config.screenshot.notify) {
            const what = action === "both" ? "both" : action === "copy" ? "copied" : "saved";
            Quickshell.execDetached(["sh", Quickshell.shellPath("scripts/screenshot-notify.sh"), path, what, directory]);
        }
    }

    function cancel() {
        ticker.stop();
        gap.stop();
        watchdog.stop();
        phase = "idle";
        targetScreen = null;
    }

    function fail(message) {
        cancel();
        notifyError(message);
    }

    function notifyError(message) {
        Quickshell.execDetached(["notify-send", "-a", "Screenshot", "-i", "dialog-error", "Screenshot failed", message]);
    }

    // ── targets ──────────────────────────────────────────────────────────────

    function screenByName(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === name)
                return screens[i];
        return null;
    }

    function focusedScreen() {
        return screenByName(Hyprland.focusedMonitor?.name ?? "") ?? Scaling.primary;
    }

    function focusedScreenTarget() {
        const s = focusedScreen();
        return s ? { screen: s, rect: { x: 0, y: 0, w: s.width, h: s.height } } : null;
    }

    function activeWindowTarget() {
        const t = Hyprland.activeToplevel;
        const o = t?.lastIpcObject;
        if (!o || !o.at || !o.size)
            return null;
        const s = screenByName(t.monitor?.name ?? "") ?? focusedScreen();
        if (!s)
            return null;
        const r = clip({ x: o.at[0] - s.x, y: o.at[1] - s.y, w: o.size[0], h: o.size[1] }, s);
        return r ? { screen: s, rect: r } : null;
    }

    function clip(r, s) {
        const x1 = Math.max(0, r.x), y1 = Math.max(0, r.y);
        const x2 = Math.min(s.width, r.x + r.w), y2 = Math.min(s.height, r.y + r.h);
        return x2 > x1 && y2 > y1 ? { x: x1, y: y1, w: x2 - x1, h: y2 - y1 } : null;
    }

    // Windows visible on a screen, best "click target" first:
    // floating before tiled, then most recently focused.
    function windowsOn(s) {
        const mon = Hyprland.monitorFor(s);
        if (!mon)
            return [];
        const visible = [mon.activeWorkspace?.id, mon.lastIpcObject?.specialWorkspace?.id]
            .filter(id => id !== undefined && id !== null && id !== 0);
        const out = [];
        const all = Hyprland.toplevels.values;
        for (let i = 0; i < all.length; i++) {
            const o = all[i].lastIpcObject;
            if (!o || !o.at || !o.size || o.hidden === true || o.mapped === false)
                continue;
            if (!visible.includes(o.workspace?.id))
                continue;
            const r = clip({ x: o.at[0] - s.x, y: o.at[1] - s.y, w: o.size[0], h: o.size[1] }, s);
            if (!r)
                continue;
            r.title = o.title || all[i].title || "";
            r.appClass = o.class || "";
            r.floating = o.floating === true;
            r.order = o.focusHistoryID ?? 99;
            out.push(r);
        }
        out.sort((a, b) => (b.floating - a.floating) || (a.order - b.order));
        return out;
    }

    function expand(path) {
        return path ? path.replace(/^~(?=\/|$)/, home) : "";
    }

    // ── plumbing ─────────────────────────────────────────────────────────────

    // Your real Pictures folder (from user-dirs.dirs), no extra package needed.
    Process {
        running: true
        command: ["sh", "-c", '. "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" 2>/dev/null; printf %s "${XDG_PICTURES_DIR:-$HOME/Pictures}"']
        stdout: StdioCollector {
            onStreamFinished: root.picturesDir = this.text.trim()
        }
    }

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) {
                stop();
                gap.restart();
            }
        }
    }

    // Let the countdown pill disappear before the frame is taken.
    Timer {
        id: gap
        interval: 250
        onTriggered: if (root.phase === "countdown") root.capture()
    }

    Timer {
        id: watchdog
        interval: 3000
        onTriggered: if (root.phase === "capturing") root.fail("The screen capture never arrived.")
    }

    Timer {
        id: saveGuard
        interval: 6000
        onTriggered: if (root.phase === "saving") root.fail("Saving the screenshot timed out.")
    }

    onPhaseChanged: {
        if (phase === "saving")
            saveGuard.restart();
        else
            saveGuard.stop();
    }

    IpcHandler {
        target: "screenshot"

        function region(): void {
            root.start("region", 0);
        }
        function screen(): void {
            root.start("screen", 0);
        }
        function window(): void {
            root.start("window", 0);
        }
        function screenIn(seconds: int): void {
            root.start("screen", seconds);
        }
        function windowIn(seconds: int): void {
            root.start("window", seconds);
        }
        function cancel(): void {
            root.cancel();
        }
    }
}
