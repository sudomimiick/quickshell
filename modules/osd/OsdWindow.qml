import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.services
import qs.widgets

// The pop-up: a small notch that drops out of the bar under the controls icons,
// with the same curved ears as the panels. Over a fullscreen app (where the bar
// is hidden) it drops from the top edge of the screen instead.
//
// The window is a transparent strip across the top that never changes size and
// never takes clicks; only the notch inside it moves.
PanelWindow {
    id: win

    required property ShellScreen modelData
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
    readonly property bool here: Osd.shown && Osd.screenName === modelData.name
    readonly property bool fullscreen: monitor?.activeWorkspace?.hasFullscreen ?? false
    readonly property int barH: Theme.rem(Config.bar.height)
    readonly property int dropY: fullscreen ? 0 : barH
    readonly property int ear: Config.bar.ears ? Theme.radius.lg : 1
    readonly property int notchW: Theme.rem(12 * Theme.ui.k)
    readonly property int notchH: Theme.rem(2.4 * Theme.ui.k)
    readonly property int pad: Theme.rem(0.9)
    property real t: 0 // 0 tucked away … 1 out

    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: barH + notchH + 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}

    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    onHereChanged: {
        if (here) {
            outAnim.stop();
            inAnim.restart();
        } else {
            inAnim.stop();
            outAnim.restart();
        }
    }

    NumberAnimation {
        id: inAnim
        target: win
        property: "t"
        to: 1
        duration: Theme.anim.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.anim.enter
    }

    NumberAnimation {
        id: outAnim
        target: win
        property: "t"
        to: 0
        duration: Theme.anim.fast
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.anim.exit
    }

    Item {
        id: notch

        // under the controls icons; near the right edge if the bar hasn't said where
        readonly property real centre: Osd.positions[win.modelData.name] ?? (win.width - Theme.rem(9))
        readonly property real h: win.notchH * win.t

        x: Math.round(Math.max(win.ear + win.pad, Math.min(win.width - win.notchW - win.ear - win.pad, centre - win.notchW / 2)))
        y: win.dropY
        width: win.notchW
        height: Math.max(1, h)
        visible: win.t > 0.01

        Shape {
            id: shape

            readonly property real r: win.ear
            readonly property real w: win.notchW
            readonly property real h: notch.height
            readonly property real er: Math.min(win.ear, h / 2)
            readonly property real cr: Math.min(Theme.radius.lg, h / 2, w / 2)

            x: -r
            width: w + r * 2
            height: h
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.colors.frame
                strokeColor: "transparent"
                strokeWidth: -1
                startX: 0
                startY: 0

                PathArc { x: shape.r; y: shape.er; radiusX: shape.r; radiusY: shape.er }
                PathLine { x: shape.r; y: shape.h - shape.cr }
                PathArc { x: shape.r + shape.cr; y: shape.h; radiusX: shape.cr; radiusY: shape.cr; direction: PathArc.Counterclockwise }
                PathLine { x: shape.r + shape.w - shape.cr; y: shape.h }
                PathArc { x: shape.r + shape.w; y: shape.h - shape.cr; radiusX: shape.cr; radiusY: shape.cr; direction: PathArc.Counterclockwise }
                PathLine { x: shape.r + shape.w; y: shape.er }
                PathArc { x: shape.r * 2 + shape.w; y: 0; radiusX: shape.r; radiusY: shape.er }
                PathLine { x: 0; y: 0 }
            }
        }

        // what changed: its icon, and how far along it is
        Item {
            anchors.fill: parent
            clip: true
            opacity: Math.min(1, win.t * 1.6)

            Row {
                x: win.pad
                y: (win.notchH - height) / 2 - (1 - win.t) * Theme.rem(0.4)
                width: win.notchW - win.pad * 2
                spacing: Theme.space.md

                StyledText {
                    id: glyph
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.ui.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: Osd.glyph
                    color: Osd.muted ? Theme.colors.faint : Theme.colors.text
                    font.pixelSize: Theme.ui.icon
                }

                // the microphone only has on and off
                StyledText {
                    visible: Osd.kind === "mic"
                    anchors.verticalCenter: parent.verticalCenter
                    text: Osd.muted ? "Microphone off" : "Microphone on"
                    color: Osd.muted ? Theme.colors.subtext : Theme.colors.text
                    font.pixelSize: Theme.ui.text
                }

                Rectangle {
                    id: track
                    visible: Osd.kind !== "mic"
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - glyph.width - parent.spacing - (number.visible ? number.width + parent.spacing : 0)
                    height: Theme.rem(0.36)
                    radius: height / 2
                    color: Theme.colors.raised

                    Rectangle {
                        width: Math.max(track.height, track.width * Math.max(0, Math.min(1, Osd.value)))
                        height: parent.height
                        radius: parent.radius
                        color: Osd.muted ? Theme.colors.faint : Theme.colors.accent

                        Behavior on width {
                            NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutCubic }
                        }
                    }
                }

                StyledText {
                    id: number
                    visible: Config.osd.showValue && Osd.kind !== "mic"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.rem(2.4)
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(Osd.value * 100)
                    color: Theme.colors.subtext
                    font.pixelSize: Theme.ui.small
                }
            }
        }
    }
}
