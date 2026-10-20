pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common

// Your wallpapers: the folder, the picture in use, and small thumbnails for the
// picker. The shell draws the wallpaper itself (modules/wallpaper), which is what
// lets it open the screen down the middle onto the new one.
//
//   hl.bind("SUPER + SHIFT + W", hl.dsp.global("quickshell:wallpaper"))
//   qs ipc call wallpaper next | previous | random | set ~/Pictures/Wallpapers/x.jpg | rescan
Singleton {
    id: root

    readonly property string home: String(Quickshell.env("HOME") ?? "")
    readonly property string directory: root.expand(Config.wallpaper.directory)
    readonly property string thumbDir: Quickshell.cachePath("wallpapers")

    property var files: []            // every picture, sorted
    property var thumbs: ({})         // picture → its thumbnail
    property string current: ""       // the one on screen
    property string preview: ""       // the one the picker rests on: decoded ahead so Enter is instant
    property bool scanning: false
    property bool loaded: false       // the remembered wallpaper has been read

    property var pendingFiles: []
    property var pendingThumbs: ({})

    function expand(p) {
        return String(p ?? "").replace(/^~(?=\/|$)/, root.home);
    }

    // a file:// URL that survives spaces, # and % in names
    function url(path) {
        if (!path)
            return "";
        return "file://" + path.split("/").map(s => encodeURIComponent(s)).join("/");
    }

    // "~/Pictures/Wallpapers/mountains-at-dawn.jpg" → "mountains at dawn"
    function title(path) {
        const file = String(path ?? "").split("/").pop() ?? "";
        return file.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ").trim();
    }

    function thumbUrl(path) {
        return root.url(root.thumbs[path] ?? "");
    }

    function indexOf(path) {
        return root.files.indexOf(path);
    }

    function set(path) {
        const p = root.expand(path);
        if (!p || p === root.current)
            return;
        root.current = p;
        store.setText(JSON.stringify({ path: p }) + "\n");
        const cmd = Config.wallpaper.onChange;
        if (cmd && cmd.length)
            Quickshell.execDetached(cmd.map(a => String(a).replace(/%f/g, p)));
    }

    function step(d) {
        const n = root.files.length;
        if (!n)
            return;
        const i = root.indexOf(root.current);
        root.set(root.files[((i < 0 ? 0 : i + d) % n + n) % n]);
    }

    function random() {
        const n = root.files.length;
        if (n < 2)
            return root.step(1);
        let i = root.indexOf(root.current);
        let j = i;
        while (j === i)
            j = Math.floor(Math.random() * n);
        root.set(root.files[j]);
    }

    function scan() {
        if (lister.running)
            return;
        root.scanning = true;
        root.pendingFiles = [];
        lister.running = true;
    }

    // one line from scripts/wallpapers.sh
    function take(line) {
        const f = line.split("\t");
        if (f[0] === "F" && f[1]) {
            root.pendingFiles.push(f[1]);
        } else if (f[0] === "E") {
            root.files = root.pendingFiles;
            root.pendingFiles = [];
            // nothing chosen yet (a fresh install): start with the first one
            if (!root.current && root.loaded && root.files.length && Config.wallpaper.draw)
                root.set(root.files[0]);
        } else if (f[0] === "T" && f[1] && f[2]) {
            root.pendingThumbs[f[1]] = f[2];
            thumbBatch.restart();
        }
    }

    Process {
        id: lister
        command: ["sh", Quickshell.shellPath("scripts/wallpapers.sh"), root.directory, root.thumbDir, String(Config.wallpaper.thumbnailSize)]
        stdout: SplitParser {
            onRead: line => root.take(line)
        }
        onExited: {
            root.scanning = false;
            thumbBatch.stop();
            root.flushThumbs();
        }
    }

    // thumbnails arrive in bursts; hand them over a few times a second, not per line
    function flushThumbs() {
        if (Object.keys(root.pendingThumbs).length === 0)
            return;
        root.thumbs = Object.assign({}, root.thumbs, root.pendingThumbs);
        root.pendingThumbs = {};
    }

    Timer {
        id: thumbBatch
        interval: 60
        onTriggered: root.flushThumbs()
    }

    // the wallpaper you had last time — read straight away (it's tiny), so the
    // wallpaper starts decoding the moment the shell starts
    FileView {
        id: store
        path: Quickshell.statePath("wallpaper.json")
        blockLoading: true
        printErrors: false
        onLoaded: root.readSaved()
        onLoadFailed: root.loaded = true
    }

    function readSaved() {
        try {
            const saved = JSON.parse(store.text());
            if (saved?.path && !root.current)
                root.current = saved.path;
        } catch (e) {}
        root.loaded = true;
    }

    Component.onCompleted: root.readSaved()

    // look through the folder (and make missing thumbnails) a moment after login,
    // and again whenever the picker opens
    Timer {
        running: true
        interval: 1500
        onTriggered: root.scan()
    }

    Connections {
        target: Drawers
        function onCurrentChanged() {
            if (Drawers.current === "wallpaper")
                root.scan();
            else
                root.preview = "";
        }
    }

    GlobalShortcut {
        name: "wallpaper"
        description: "Open or close the wallpaper picker"
        onPressed: Drawers.toggle("wallpaper", "", -1)
    }

    IpcHandler {
        target: "wallpaper"

        function set(path: string): void {
            root.set(path);
        }
        function next(): void {
            root.step(1);
        }
        function previous(): void {
            root.step(-1);
        }
        function random(): void {
            root.random();
        }
        function rescan(): void {
            root.scan();
        }
        function get(): string {
            return root.current;
        }
    }
}
