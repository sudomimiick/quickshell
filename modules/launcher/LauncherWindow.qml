import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.services
import qs.widgets

// The launcher box, one per monitor (the focused monitor's one opens).
//
// With Config.launcher.persistent the layer surface never unmaps: closed, it is an
// invisible 1×1 pixel that takes no clicks and no keyboard. Opening only resizes it
// and draws one frame — no new window, GL context or glyph cache — and the rows are
// a fixed set that re-bind, so typing never creates or destroys anything.
PanelWindow {
    id: win

    required property ShellScreen modelData
    screen: modelData

    readonly property bool shown: Launcher.active && Launcher.screenName === modelData.name
    readonly property bool sized: shown || !Config.launcher.persistent
    readonly property real dpr: modelData.devicePixelRatio || 1
    readonly property int pad: Theme.space.sm
    readonly property int rowH: Theme.rem(2.9)
    readonly property int iconSize: Theme.rem(2)
    readonly property int iconPx: Math.ceil(iconSize * dpr)   // crisp at fractional scale

    visible: Config.launcher.persistent || shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: sized ? box.width : 1
    implicitHeight: sized ? box.height : 1
    mask: Region {
        item: win.shown ? box : null
    }

    WlrLayershell.namespace: "qs-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onShownChanged: {
        if (shown) {
            input.text = Launcher.query;
            input.cursorPosition = input.text.length;
            input.forceActiveFocus();
            hover.armed = false;
        } else {
            grabDelay.stop();
            grab.active = false;
        }
    }

    // Click anywhere outside the box → close. Armed only once we hold the keyboard:
    // Hyprland drops any grab when a layer turns exclusive, so arming earlier would
    // close the launcher the moment it opens.
    HyprlandFocusGrab {
        id: grab
        windows: [win]
        onCleared: {
            if (win.shown)
                Launcher.close();
        }
    }

    Timer {
        id: grabDelay
        interval: 50
        onTriggered: {
            if (win.shown)
                grab.active = true;
        }
    }

    // Carry out one of fuzzel's key actions (Launcher.keyAction maps the keys).
    function handle(action) {
        const t = input.text;
        const c = input.cursorPosition;
        switch (action) {
        case "cancel":
            Launcher.close();
            break;
        case "execute":
            Launcher.activate(Launcher.selected, false);
            break;
        case "execute-terminal":
            if (!Launcher.activate(Launcher.selected, true))
                Launcher.executeInput(true);
            break;
        case "execute-input":
            Launcher.executeInput(false);
            break;
        case "execute-or-next":
            if (Launcher.results.length === 1)
                Launcher.activate(0, false);
            else
                Launcher.move(1, true);
            break;
        case "prev":
            Launcher.move(-1, false);
            break;
        case "next":
            Launcher.move(1, false);
            break;
        case "prev-wrap":
            Launcher.move(-1, true);
            break;
        case "prev-page":
            Launcher.move(-Launcher.lines, false);
            break;
        case "next-page":
            Launcher.move(Launcher.lines, false);
            break;
        case "first":
            Launcher.select(0);
            break;
        case "last":
            Launcher.select(Launcher.results.length - 1);
            break;
        case "insert-selected":
            {
                const r = Launcher.results[Launcher.selected];
                if (r) {
                    input.text = r.kind === "run" ? ">" + r.cmd : r.kind === "calc" ? (r.value ?? t) : r.title;
                    input.cursorPosition = input.text.length;
                }
            }
            break;
        case "expunge":
            Launcher.expunge(Launcher.selected);
            break;
        case "delete-line-backward":
            input.remove(0, c);
            break;
        case "delete-line-forward":
            input.remove(c, t.length);
            break;
        case "delete-line":
            input.text = "";
            break;
        case "delete-prev-word":
            input.remove(Launcher.wordLeft(t, c), c);
            break;
        case "delete-next-word":
            input.remove(c, Launcher.wordRight(t, c));
            break;
        case "backspace":
            if (input.selectedText.length)
                input.remove(input.selectionStart, input.selectionEnd);
            else if (c > 0)
                input.remove(c - 1, c);
            break;
        case "home":
            input.cursorPosition = 0;
            break;
        case "end":
            input.cursorPosition = t.length;
            break;
        case "left":
            input.cursorPosition = Math.max(0, c - 1);
            break;
        case "right":
            input.cursorPosition = Math.min(t.length, c + 1);
            break;
        case "word-left":
            input.cursorPosition = Launcher.wordLeft(t, c);
            break;
        case "word-right":
            input.cursorPosition = Launcher.wordRight(t, c);
            break;
        default:
            return false;
        }
        return true;
    }

    Rectangle {
        id: box

        visible: win.shown
        width: Theme.rem(Config.launcher.width)
        height: list.y + list.height + win.pad
        radius: Theme.radius.lg
        color: Theme.colors.base
        border.width: 1
        border.color: Theme.colors.border

        // ── search field ────────────────────────────────────────────────────
        Item {
            id: search
            x: win.pad
            y: win.pad
            width: box.width - win.pad * 2
            height: Theme.rem(2.9)

            StyledText {
                id: glyph
                x: Theme.space.sm
                width: Theme.rem(1.6)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: Launcher.mode === "calc" ? "󰃬" : Launcher.mode === "run" ? "" : ""
                color: Theme.colors.subtext
                font.pixelSize: Theme.font.lg
            }

            TextInput {
                id: input
                anchors.left: glyph.right
                anchors.leftMargin: Theme.space.sm
                anchors.right: counter.left
                anchors.rightMargin: Theme.space.md
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                selectByMouse: true
                color: Theme.colors.text
                selectionColor: Theme.alpha(Theme.colors.text, 0.3)
                selectedTextColor: Theme.colors.text
                font.family: Theme.font.family
                font.pixelSize: Theme.font.lg

                onTextChanged: {
                    if (win.shown)
                        Launcher.setQuery(text);
                }
                onActiveFocusChanged: {
                    if (activeFocus && win.shown)
                        grabDelay.restart();
                }
                Keys.onPressed: event => {
                    if (win.handle(Launcher.keyAction(event.key, event.modifiers)))
                        event.accepted = true;
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: "Search apps…"
                    color: Theme.colors.subtext
                    font.pixelSize: Theme.font.lg
                }
            }

            StyledText {
                id: counter
                anchors.right: parent.right
                anchors.rightMargin: Theme.space.sm
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (Launcher.mode === "calc")
                        return "calculator";
                    if (Launcher.mode === "run")
                        return "run";
                    if (!input.text.length)
                        return (Config.launcher.calculator ? "=  calc    " : "") + (Config.launcher.runCommands ? ">  run" : "");
                    return `${Launcher.results.length}/${Launcher.total}`;
                }
                color: Theme.colors.subtext
                font.pixelSize: Theme.font.xs
            }
        }

        Rectangle {
            id: divider
            x: win.pad
            y: search.y + search.height
            width: search.width
            height: 1
            color: Theme.colors.border
        }

        // ── results ─────────────────────────────────────────────────────────
        Item {
            id: list
            x: win.pad
            y: divider.y + divider.height + win.pad
            width: box.width - win.pad * 2
            height: win.rowH * Launcher.lines

            Repeater {
                model: Launcher.lines

                // one row; a fixed set of these re-binds on every keystroke
                delegate: Item {
                    id: row

                    required property int index
                    readonly property int at: Launcher.scroll + index
                    readonly property var r: Launcher.results[at] ?? null
                    readonly property bool sel: at === Launcher.selected
                    readonly property color accent: Theme.colors.accent

                    y: index * win.rowH
                    width: list.width
                    height: win.rowH
                    visible: r !== null

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 1
                        anchors.bottomMargin: 1
                        visible: row.sel
                        radius: Theme.radius.md
                        color: Theme.colors.raised

                        Rectangle {
                            width: Theme.rem(0.2)
                            height: parent.height * 0.5
                            anchors.verticalCenter: parent.verticalCenter
                            radius: width / 2
                            color: row.accent
                        }
                    }

                    Item {
                        id: iconBox
                        x: Theme.space.md
                        width: win.iconSize
                        height: win.iconSize
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            id: img
                            anchors.fill: parent
                            source: row.r?.icon ?? ""
                            sourceSize: Qt.size(win.iconPx, win.iconPx)
                            visible: status === Image.Ready
                        }

                        // no icon: a grey tile with its first letter (or a glyph)
                        Rectangle {
                            anchors.fill: parent
                            visible: !img.visible
                            radius: Theme.radius.sm
                            color: Theme.colors.raised

                            StyledText {
                                anchors.centerIn: parent
                                text: row.r?.glyph || (row.r?.title ?? "?").charAt(0).toUpperCase()
                                font.pixelSize: Theme.font.lg
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Column {
                        anchors.left: iconBox.right
                        anchors.leftMargin: Theme.space.md
                        anchors.right: tail.left
                        anchors.rightMargin: Theme.space.sm
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            width: parent.width
                            textFormat: Text.StyledText
                            text: row.r ? Launcher.markup(row.r.title, row.r.pos) : ""
                            elide: Text.ElideRight
                            color: row.sel ? Theme.colors.text : Theme.alpha(Theme.colors.text, 0.78)
                            font.weight: row.sel ? Font.Medium : Font.Normal
                        }
                        StyledText {
                            width: parent.width
                            visible: text.length > 0
                            textFormat: Text.PlainText
                            text: row.r?.sub ?? ""
                            elide: Text.ElideRight
                            color: Theme.colors.subtext
                            font.pixelSize: Theme.font.xs
                        }
                    }

                    StyledText {
                        id: tail
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.space.md
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const term = row.r?.ref?.term ? "" : "";
                            if (!row.sel)
                                return term;
                            if (row.r?.kind === "calc")
                                return row.r.value === null ? "" : "copy ⏎";
                            return term ? term + "  ⏎" : "⏎";
                        }
                        color: Theme.colors.subtext
                        font.pixelSize: Theme.font.xs
                    }
                }
            }

            // scrollbar
            Rectangle {
                readonly property int n: Launcher.results.length
                visible: n > Launcher.lines
                x: list.width - width
                width: Theme.rem(0.18)
                height: Math.max(Theme.rem(1.5), list.height * Launcher.lines / Math.max(1, n))
                y: n > Launcher.lines ? (list.height - height) * Launcher.scroll / (n - Launcher.lines) : 0
                radius: width / 2
                color: Theme.alpha(Theme.colors.text, 0.22)
            }

            Column {
                anchors.centerIn: parent
                visible: Launcher.results.length === 0
                spacing: Theme.space.xs

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Launcher.mode === "run" ? "Type a command" : Launcher.total === 0 ? "Loading apps…" : "No matches"
                    color: Theme.colors.subtext
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text.length > 0
                    text: Launcher.mode === "apps" && Config.launcher.runCommands && Launcher.query.trim().length ? "Shift+Enter runs it as a command" : ""
                    color: Theme.alpha(Theme.colors.subtext, 0.7)
                    font.pixelSize: Theme.font.xs
                }
            }

            // one mouse area for every row: hover selects (only on a real move, so a
            // pointer resting where the box opens doesn't steal the selection),
            // click launches, Ctrl+click launches in a terminal, wheel moves
            MouseArea {
                id: hover

                property bool armed: false
                property real lx: 0
                property real ly: 0
                property real wheelAcc: 0

                function rowAt(y) {
                    return Launcher.scroll + Math.floor(y / win.rowH);
                }

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton

                onPositionChanged: mouse => {
                    const moved = armed && Math.abs(mouse.x - lx) + Math.abs(mouse.y - ly) >= 3;
                    if (!armed || moved) {
                        lx = mouse.x;
                        ly = mouse.y;
                    }
                    armed = true;
                    if (moved && rowAt(mouse.y) < Launcher.results.length)
                        Launcher.select(rowAt(mouse.y));
                }
                onClicked: mouse => Launcher.activate(rowAt(mouse.y), (mouse.modifiers & Qt.ControlModifier) !== 0)
                onWheel: wheel => {
                    wheelAcc += wheel.angleDelta.y;
                    while (wheelAcc >= 120) {
                        Launcher.move(-1, false);
                        wheelAcc -= 120;
                    }
                    while (wheelAcc <= -120) {
                        Launcher.move(1, false);
                        wheelAcc += 120;
                    }
                }
            }
        }
    }

    // ── icon warm-up ────────────────────────────────────────────────────────
    // Renders each app icon once, a few per tick, right after login. Qt keeps the
    // result, so later no row ever waits for an SVG to be drawn.
    property int warmAt: 0

    Timer {
        interval: 40
        repeat: true
        running: Config.launcher.preloadIcons && win.warmAt < Launcher.icons.length
        onTriggered: win.warmAt += 6
    }

    Connections {
        target: Launcher
        function onIconsChanged() {
            win.warmAt = 0;
        }
    }

    Item {
        visible: false

        Repeater {
            model: Config.launcher.preloadIcons ? 6 : 0

            Image {
                required property int index
                source: Launcher.icons[win.warmAt + index] ?? ""
                sourceSize: Qt.size(win.iconPx, win.iconPx)
            }
        }
    }
}
