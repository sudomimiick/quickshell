pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.services
import qs.widgets

// One per screen. Keeps a frozen frame of its screen and runs the selection UI.
//
//   drag             new region            click a window   capture it (Shift: just select)
//   drag inside      move it               drag an edge     resize it
//   Enter / dbl-click  default (copy)      Ctrl+C / Ctrl+S  copy / save
//   Space            whole screen          arrows           nudge 1 px (Shift: resize)
//   Esc / right click  cancel
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    readonly property real dpr: modelData.devicePixelRatio
    readonly property bool useGrim: Config.screenshot.capture === "grim"
    readonly property Item frozen: useGrim ? grimFrame : nativeFrame
    readonly property string grimPath: Quickshell.cachePath(`freeze-${modelData.name}.png`)
    readonly property bool selecting: Screenshot.phase === "selecting"
    readonly property bool isTarget: Screenshot.targetScreen === modelData
    readonly property bool isFocusedScreen: Hyprland.focusedMonitor?.name === modelData.name

    // selection, in logical px snapped to the physical pixel grid
    property rect sel: Qt.rect(0, 0, 0, 0)
    property rect lastSel: Qt.rect(0, 0, 0, 0)
    readonly property bool hasSel: sel.width >= 1 && sel.height >= 1
    property string dragMode: ""          // "" | new | move | n s e w ne nw se sw
    property point pressPos: Qt.point(0, 0)
    property rect startSel: Qt.rect(0, 0, 0, 0)
    property bool moved: false
    property point cursor: Qt.point(-1, -1)
    property var windows: []
    property var hoverWindow: null
    readonly property rect hoverRect: hoverWindow ? snapRect(hoverWindow) : Qt.rect(0, 0, 0, 0)
    property var afterFlash: null
    property int tries: 0

    visible: selecting || ((Screenshot.phase === "instant" || Screenshot.phase === "saving") && isTarget)
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-screenshot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: selecting && isFocusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── geometry helpers ─────────────────────────────────────────────────────

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    // Logical px land between physical pixels at fractional scales; snap so the
    // saved image is cut on exact pixel boundaries.
    function snap(v) {
        return Math.round(v * dpr) / dpr;
    }

    function makeRect(x1, y1, x2, y2) {
        const l = snap(clamp(Math.min(x1, x2), 0, width));
        const t = snap(clamp(Math.min(y1, y2), 0, height));
        const r = snap(clamp(Math.max(x1, x2), 0, width));
        const b = snap(clamp(Math.max(y1, y2), 0, height));
        return Qt.rect(l, t, r - l, b - t);
    }

    function snapRect(r) {
        return makeRect(r.x, r.y, r.x + r.w, r.y + r.h);
    }

    function hitTest(x, y) {
        if (!hasSel)
            return "";
        const t = Theme.rem(0.6);
        const l = sel.x, r = sel.x + sel.width, tp = sel.y, b = sel.y + sel.height;
        const nearL = Math.abs(x - l) <= t, nearR = Math.abs(x - r) <= t;
        const nearT = Math.abs(y - tp) <= t, nearB = Math.abs(y - b) <= t;
        const inX = x >= l - t && x <= r + t, inY = y >= tp - t && y <= b + t;
        if (nearT && nearL) return "nw";
        if (nearT && nearR) return "ne";
        if (nearB && nearL) return "sw";
        if (nearB && nearR) return "se";
        if (nearT && inX) return "n";
        if (nearB && inX) return "s";
        if (nearL && inY) return "w";
        if (nearR && inY) return "e";
        if (x > l && x < r && y > tp && y < b) return "move";
        return "";
    }

    function applyDrag(x, y) {
        x = clamp(x, 0, width);
        y = clamp(y, 0, height);
        const s = startSel;
        let x1 = s.x, y1 = s.y, x2 = s.x + s.width, y2 = s.y + s.height;
        if (dragMode === "new") {
            x1 = pressPos.x; y1 = pressPos.y; x2 = x; y2 = y;
        } else if (dragMode === "move") {
            const dx = clamp(x - pressPos.x, -s.x, width - x2);
            const dy = clamp(y - pressPos.y, -s.y, height - y2);
            x1 += dx; x2 += dx; y1 += dy; y2 += dy;
        } else {
            if (dragMode.includes("w")) x1 = x;
            if (dragMode.includes("e")) x2 = x;
            if (dragMode.includes("n")) y1 = y;
            if (dragMode.includes("s")) y2 = y;
        }
        sel = makeRect(x1, y1, x2, y2);
    }

    function windowAt(x, y) {
        for (const w of windows)
            if (x >= w.x && x < w.x + w.w && y >= w.y && y < w.y + w.h)
                return w;
        return null;
    }

    // one physical pixel per press; Shift resizes from the bottom-right corner
    function nudge(dx, dy, resize) {
        if (!hasSel)
            return;
        const step = 1 / dpr;
        const s = sel;
        if (resize)
            sel = makeRect(s.x, s.y, s.x + s.width + dx * step, s.y + s.height + dy * step);
        else {
            const mx = clamp(dx * step, -s.x, width - s.x - s.width);
            const my = clamp(dy * step, -s.y, height - s.y - s.height);
            sel = makeRect(s.x + mx, s.y + my, s.x + s.width + mx, s.y + s.height + my);
        }
    }

    function cursorFor(hit) {
        switch (hit) {
        case "nw": case "se": return Qt.SizeFDiagCursor;
        case "ne": case "sw": return Qt.SizeBDiagCursor;
        case "n": case "s": return Qt.SizeVerCursor;
        case "e": case "w": return Qt.SizeHorCursor;
        case "move": return Qt.SizeAllCursor;
        default: return hoverWindow ? Qt.PointingHandCursor : Qt.CrossCursor;
        }
    }

    // ── capture ──────────────────────────────────────────────────────────────

    function captureNow() {
        tries = 0;
        if (useGrim) {
            const args = Config.screenshot.includeCursor ? "-c" : "";
            grimProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && exec grim $3 -o "$1" "$2"', "sh", modelData.name, grimPath, args];
            grimProc.running = true;
        } else {
            nativeFrame.captureFrame();
            settle.restart();
        }
    }

    function beginSelecting() {
        windows = Screenshot.windowsOn(modelData);
        hoverWindow = null;
        dragMode = "";
        sel = Config.screenshot.rememberRegion ? lastSel : Qt.rect(0, 0, 0, 0);
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }

    function accept(action) {
        if (hasSel)
            grab(sel, action);
    }

    // Cut r out of the frozen frame at full resolution and hand it to the service.
    function grab(r, action) {
        if (r.width < 1 || r.height < 1)
            return;
        lastSel = r;
        Screenshot.targetScreen = modelData;
        Screenshot.phase = "saving";
        crop.width = r.width;
        crop.height = r.height;
        cropView.x = -r.x;
        cropView.y = -r.y;
        const path = Screenshot.newPath(action);
        const size = Qt.size(Math.round(r.width * dpr), Math.round(r.height * dpr));
        const started = crop.grabToImage(result => {
            const ok = result.saveToFile(path);
            win.flash(() => Screenshot.finished(ok, path, action));
        }, size);
        if (!started)
            Screenshot.fail("Couldn't read the frozen frame.");
    }

    function flash(then) {
        if (!Config.screenshot.flash) {
            then();
            return;
        }
        afterFlash = then;
        flashAnim.restart();
    }

    function runAfterFlash() {
        const f = afterFlash;
        afterFlash = null;
        if (f)
            f();
    }

    function handleKey(e) {
        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
        const shift = (e.modifiers & Qt.ShiftModifier) !== 0;
        switch (e.key) {
        case Qt.Key_Escape: Screenshot.cancel(); break;
        case Qt.Key_Return:
        case Qt.Key_Enter: accept(Screenshot.defaultAction); break;
        case Qt.Key_Space: grab(Qt.rect(0, 0, width, height), Screenshot.defaultAction); break;
        case Qt.Key_C: if (ctrl) accept("copy"); break;
        case Qt.Key_S: if (ctrl) accept("save"); break;
        case Qt.Key_Left: nudge(-1, 0, shift); break;
        case Qt.Key_Right: nudge(1, 0, shift); break;
        case Qt.Key_Up: nudge(0, -1, shift); break;
        case Qt.Key_Down: nudge(0, 1, shift); break;
        default: return;
        }
        e.accepted = true;
    }

    Connections {
        target: Screenshot
        function onShotChanged() {
            win.captureNow();
        }
        function onPhaseChanged() {
            if (Screenshot.phase === "selecting")
                win.beginSelecting();
            else if (Screenshot.phase === "instant" && win.isTarget)
                Qt.callLater(() => win.grab(win.snapRect(Screenshot.targetRect), Screenshot.defaultAction));
        }
    }

    // Native: one capture view per screen for the shell's whole life. It is never
    // destroyed, only asked for fresh frames (sidesteps a Quickshell 0.3 bug where
    // destroying screencopy captures can crash the shell later).
    ScreencopyView {
        id: nativeFrame
        anchors.fill: parent
        visible: !win.useGrim
        captureSource: win.useGrim ? null : win.modelData
        live: false
        paintCursor: Config.screenshot.includeCursor
    }

    Timer {
        id: settle
        interval: 120
        onTriggered: {
            if (nativeFrame.hasContent)
                Screenshot.markReady(win.modelData.name);
            else if (++win.tries < 15)
                restart();
            else
                Screenshot.fail("The compositor didn't send a frame.");
        }
    }

    // Fallback: grim writes the frame to a file, shown as an image.
    Image {
        id: grimFrame
        anchors.fill: parent
        visible: win.useGrim
        cache: false
        asynchronous: false
    }

    Process {
        id: grimProc
        onExited: (code, status) => {
            if (code !== 0) {
                Screenshot.fail("grim failed — is it installed?");
                return;
            }
            grimFrame.source = "";
            grimFrame.source = "file://" + win.grimPath;
            Screenshot.markReady(win.modelData.name);
        }
    }

    // A 1:1 copy of the frozen frame, shifted so the selection sits at 0,0 and
    // clipped to it. Parked off-screen; grabs render it anyway.
    Item {
        id: crop
        x: win.width + 10
        width: 1
        height: 1
        clip: true

        ShaderEffectSource {
            id: cropView
            width: win.width
            height: win.height
            sourceItem: win.frozen
            textureSize: Qt.size(Math.round(win.width * win.dpr), Math.round(win.height * win.dpr))
            hideSource: false
            smooth: false
        }
    }

    // ── selection UI ─────────────────────────────────────────────────────────

    Item {
        id: chrome
        anchors.fill: parent
        visible: win.selecting

        readonly property rect hole: win.hasSel ? win.sel : win.hoverRect
        readonly property color dim: Qt.rgba(0, 0, 0, 0.45)
        readonly property int line: Math.max(1, Theme.rem(0.12))

        // dim everything except the selection (or the window under the cursor)
        Rectangle { x: 0; y: 0; width: parent.width; height: chrome.hole.y; color: chrome.dim }
        Rectangle { x: 0; y: chrome.hole.y + chrome.hole.height; width: parent.width; height: parent.height - y; color: chrome.dim }
        Rectangle { x: 0; y: chrome.hole.y; width: chrome.hole.x; height: chrome.hole.height; color: chrome.dim }
        Rectangle { x: chrome.hole.x + chrome.hole.width; y: chrome.hole.y; width: parent.width - x; height: chrome.hole.height; color: chrome.dim }

        // crosshair until something is selected
        Rectangle {
            visible: !win.hasSel && win.cursor.x >= 0
            x: 0; y: win.cursor.y; width: parent.width; height: 1
            color: Theme.alpha(Theme.colors.text, 0.25)
        }
        Rectangle {
            visible: !win.hasSel && win.cursor.x >= 0
            x: win.cursor.x; y: 0; width: 1; height: parent.height
            color: Theme.alpha(Theme.colors.text, 0.25)
        }

        // window under the cursor
        Rectangle {
            visible: !win.hasSel && win.hoverWindow !== null
            x: win.hoverRect.x; y: win.hoverRect.y
            width: win.hoverRect.width; height: win.hoverRect.height
            color: Theme.alpha(Theme.colors.accent, 0.06)
            border.width: chrome.line
            border.color: Theme.colors.accent
        }

        Chip {
            visible: !win.hasSel && win.hoverWindow !== null
            x: win.clamp(win.hoverRect.x + Theme.space.sm, 0, win.width - width)
            y: win.clamp(win.hoverRect.y + Theme.space.sm, 0, win.height - height)
            text: win.hoverWindow ? `${win.hoverWindow.title || win.hoverWindow.appClass}  ·  ${Math.round(win.hoverRect.width * win.dpr)} × ${Math.round(win.hoverRect.height * win.dpr)}` : ""
        }

        // the selection
        Rectangle {
            visible: win.hasSel
            x: win.sel.x; y: win.sel.y
            width: win.sel.width; height: win.sel.height
            color: "transparent"
            border.width: chrome.line
            border.color: Theme.colors.accent
        }

        Repeater {
            model: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]]
            delegate: Rectangle {
                required property var modelData
                visible: win.hasSel && win.dragMode !== "new"
                width: Theme.rem(0.7)
                height: width
                radius: width / 2
                x: win.sel.x + modelData[0] * win.sel.width - width / 2
                y: win.sel.y + modelData[1] * win.sel.height - height / 2
                color: Theme.colors.text
                border.width: chrome.line
                border.color: Theme.colors.accent
            }
        }

        // size, above the selection (inside it if there's no room)
        Chip {
            id: sizeChip
            visible: win.hasSel
            x: win.clamp(win.sel.x, 0, win.width - width)
            y: win.sel.y - height - Theme.space.sm >= 0 ? win.sel.y - height - Theme.space.sm : win.sel.y + Theme.space.sm
            text: `${Math.round(win.sel.width * win.dpr)} × ${Math.round(win.sel.height * win.dpr)}`
        }

        // actions, below the selection (above it, or inside, if there's no room)
        Rectangle {
            id: toolbar
            visible: win.hasSel && win.dragMode === "" && Config.screenshot.confirmRegion
            readonly property real gap: Theme.space.md
            readonly property bool fitsBelow: win.sel.y + win.sel.height + gap + height <= win.height
            readonly property bool fitsAbove: win.sel.y - gap - height - sizeChip.height - Theme.space.sm >= 0
            x: win.clamp(win.sel.x + (win.sel.width - width) / 2, Theme.space.md, win.width - width - Theme.space.md)
            y: fitsBelow ? win.sel.y + win.sel.height + gap
                : fitsAbove ? win.sel.y - gap - height
                : win.sel.y + win.sel.height - height - gap
            width: toolRow.implicitWidth + Theme.space.sm * 2
            height: toolRow.implicitHeight + Theme.space.sm * 2
            radius: height / 2
            color: Theme.colors.overlay
            border.width: 1
            border.color: Theme.colors.border

            RowLayout {
                id: toolRow
                anchors.centerIn: parent
                spacing: Theme.space.xs

                // the default action (Config: copy / save) is highlighted and takes Enter
                PillButton {
                    readonly property bool isDefault: Screenshot.defaultAction === "copy"
                    icon: "󰆏"; label: "Copy"; hint: isDefault ? "⏎" : "^C"; primary: isDefault
                    onClicked: win.accept("copy")
                }
                PillButton {
                    readonly property bool isDefault: Screenshot.defaultAction === "save"
                    icon: "󰆓"; label: "Save"; hint: isDefault ? "⏎" : "^S"; primary: isDefault
                    onClicked: win.accept("save")
                }
                PillButton {
                    readonly property bool isDefault: Screenshot.defaultAction === "both"
                    icon: "󰄬"; label: "Copy & Save"; hint: isDefault ? "⏎" : ""; primary: isDefault
                    onClicked: win.accept("both")
                }
                PillButton { icon: "󰅖"; hint: "Esc"; onClicked: Screenshot.cancel() }
            }
        }

        // how-to, until something is selected
        Chip {
            visible: !win.hasSel && win.isFocusedScreen
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.rem(2)
            padding: Theme.space.md
            text: "Drag to select  ·  Click a window  ·  Space: whole screen  ·  Esc: cancel"
        }
    }

    // ── input ────────────────────────────────────────────────────────────────

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: win.selecting
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: win.dragMode === "new" ? Qt.CrossCursor
            : win.dragMode !== "" ? win.cursorFor(win.dragMode)
            : win.cursorFor(win.hitTest(win.cursor.x, win.cursor.y))

        onPressed: e => {
            if (e.button === Qt.RightButton) {
                Screenshot.cancel();
                return;
            }
            const hit = win.hitTest(e.x, e.y);
            win.pressPos = Qt.point(e.x, e.y);
            win.moved = false;
            win.startSel = win.sel;
            win.dragMode = hit === "" ? "new" : hit;
        }

        onPositionChanged: e => {
            win.cursor = Qt.point(e.x, e.y);
            if (!mouse.pressed) {
                win.hoverWindow = win.hasSel ? null : win.windowAt(e.x, e.y);
                return;
            }
            if (!win.moved && Math.hypot(e.x - win.pressPos.x, e.y - win.pressPos.y) < 4)
                return;
            win.moved = true;
            win.hoverWindow = null;
            win.applyDrag(e.x, e.y);
        }

        onReleased: e => {
            if (e.button !== Qt.LeftButton)
                return;
            const mode = win.dragMode;
            win.dragMode = "";
            if (!win.moved) {
                // a plain click: outside the selection clears it; on a window picks it
                if (mode === "new" && win.hasSel) {
                    win.sel = Qt.rect(0, 0, 0, 0);
                    win.hoverWindow = win.windowAt(e.x, e.y);
                } else if (mode === "new" && win.hoverWindow) {
                    win.sel = win.hoverRect;
                    win.hoverWindow = null;
                    if (Config.screenshot.clickWindowCaptures && !(e.modifiers & Qt.ShiftModifier))
                        win.accept(Screenshot.defaultAction);
                }
                return;
            }
            if (mode === "new" && !Config.screenshot.confirmRegion)
                win.accept(Screenshot.defaultAction);
        }

        onDoubleClicked: e => {
            if (win.hitTest(e.x, e.y) === "move")
                win.accept(Screenshot.defaultAction);
        }

        onExited: win.cursor = Qt.point(-1, -1)
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => win.handleKey(e)
    }

    // camera flash
    Rectangle {
        id: flashRect
        anchors.fill: parent
        color: "white"
        opacity: 0

        SequentialAnimation {
            id: flashAnim
            NumberAnimation { target: flashRect; property: "opacity"; to: 0.45; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 170; easing.type: Easing.InQuad }
            ScriptAction { script: win.runAfterFlash() }
        }
    }

    // small dark label
    component Chip: Rectangle {
        property alias text: label.text
        property real padding: Theme.space.sm

        width: label.implicitWidth + padding * 2
        height: label.implicitHeight + padding
        radius: Theme.radius.sm
        color: Theme.colors.overlay
        border.width: 1
        border.color: Theme.colors.border

        StyledText {
            id: label
            anchors.centerIn: parent
            font.pixelSize: Theme.font.xs
        }
    }
}
