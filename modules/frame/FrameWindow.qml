import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.services

// The bar, one per monitor, with the screen's top corners rounded off under it.
// Panels grow down out of it; the power menu slides in from the right under it.
//
// It's one full-screen window that never changes size (so nothing ever jumps).
// Normally only the bar and an open panel take clicks; while a panel or the power
// menu is open the whole screen listens, so a click anywhere else closes it.
PanelWindow {
    id: win

    required property ShellScreen modelData
    readonly property string screenName: modelData.name
    readonly property int barH: Theme.rem(Config.bar.height)
    readonly property int corner: Config.bar.corners ? Theme.rem(Config.bar.cornerRadius) : 0
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

    readonly property bool panelHere: Drawers.current !== "" && Drawers.screenName === screenName
    readonly property bool sessionHere: Session.active && Session.screenName === screenName
    readonly property bool capturing: panelHere || sessionHere

    function closeAll() {
        Drawers.close();
        Session.close();
    }

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore // Zones reserves the bar's space; this just draws
    color: "transparent"

    WlrLayershell.namespace: "qs-frame"
    // above fullscreen apps only while the power menu is up
    WlrLayershell.layer: sessionHere ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: capturing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    mask: Region {
        item: win.capturing ? everything : bar
        Region {
            item: panels.hit
        }
    }

    onPanelHereChanged: {
        if (panelHere)
            panels.forceActiveFocus();
    }

    Item {
        id: everything
        anchors.fill: parent
    }

    // ── the bar's background ────────────────────────────────────────────────
    // One rectangle with a very thick border: its hole starts under the bar and
    // ends well below the screen, so all that shows is the bar plus the hole's
    // two rounded top corners — the screen's corners, rounded off.
    Item {
        anchors.fill: parent
        clip: true

        Rectangle {
            visible: win.corner > 0
            readonly property int m: win.barH + win.corner + 4
            x: -m
            y: win.barH - m
            width: win.width + m * 2
            height: win.height - win.barH + win.corner * 2 + m * 2
            radius: win.corner + m
            color: "transparent"
            border.width: m
            border.color: Theme.colors.frame
        }

        Rectangle {
            visible: win.corner === 0
            width: parent.width
            height: win.barH
            color: Theme.colors.frame
        }
    }

    // ── a click outside whatever is open closes it ──────────────────────────
    MouseArea {
        anchors.fill: parent
        enabled: win.capturing
        acceptedButtons: Qt.AllButtons
        onPressed: win.closeAll()
    }

    Bar {
        id: bar
        width: win.width
        height: win.barH
        win: win
        screenName: win.screenName
        monitor: win.monitor
    }

    Panels {
        id: panels
        y: win.barH
        width: win.width
        height: win.height - win.barH
        screenName: win.screenName
        bar: bar
        sideMargin: win.corner
        Keys.onEscapePressed: Drawers.close()
    }

    SessionPanel {
        anchors.fill: parent
        screenName: win.screenName
        barHeight: win.barH
        corner: win.corner
        dpr: win.modelData.devicePixelRatio || 1
    }
}
