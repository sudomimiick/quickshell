import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.common
import qs.services
import qs.modules.frame.panels

// The panels that grow out of the bar. One shape, joined to the bar by two
// concave ears, that grows down under the icon you used and morphs — position,
// width and height together — when you move to another icon.
//
// It lives in the bar's own full-screen window, which never resizes, so
// opening and closing never makes the bar jump.
FocusScope {
    id: host

    required property string screenName
    required property var bar                 // for anchorFor() when opened by a keybind
    property int sideMargin: 0                // keep clear of the screen's rounded corners

    readonly property string want: Drawers.screenName === screenName ? Drawers.current : ""
    readonly property bool open: want !== ""
    property string shown: ""        // stays set while the close animation plays
    property real openness: 0        // 0 closed … 1 open

    // the curve joining it to the bar (1px when Config.bar.ears is off: an arc of 0 breaks the path maths)
    readonly property int ear: Config.bar.ears ? Theme.radius.lg : 1
    readonly property int corner: Theme.radius.lg
    readonly property int pad: Theme.rem(1.1)

    // panels load the first time they're opened, then stay warm
    property var used: ({})

    // …except the wallpaper picker, which loads (and decodes its thumbnails) quietly
    // a few seconds after login, so even its first opening is instant
    Timer {
        running: true
        interval: 5000
        onTriggered: {
            if (!host.used.wallpaper)
                host.used = Object.assign({ wallpaper: true }, host.used);
        }
    }

    readonly property Item panel: shown === "centre" ? centrePanel.item : shown === "controls" ? controlsPanel.item : shown === "network" ? networkPanel.item : shown === "wallpaper" ? wallpaperPanel.item : null
    readonly property real targetW: panel ? panel.implicitWidth + pad * 2 : 0
    readonly property real targetH: panel ? Math.min(height - Theme.space.xl, panel.implicitHeight + pad * 2) : 0
    readonly property real anchorPx: Drawers.anchorX >= 0 ? Drawers.anchorX : bar.anchorFor(shown)
    readonly property real targetX: host.place(anchorPx, targetW, width, sideMargin + ear)

    // animated geometry: jumps while closed, glides while open
    property real dx: targetX
    property real dw: targetW
    property real dh: targetH
    readonly property bool morphing: openness > 0.02
    readonly property real vh: dh * openness

    // what the bar window lets clicks reach while nothing else is open
    property alias hit: hitBox

    Behavior on dx {
        enabled: host.morphing
        NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.move }
    }
    Behavior on dw {
        enabled: host.morphing
        NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.move }
    }
    Behavior on dh {
        enabled: host.morphing
        NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.move }
    }

    // centred under the icon, kept clear of the screen edges
    function place(centre, w, total, margin) {
        return Math.round(Math.max(margin, Math.min(total - w - margin, centre - w / 2)));
    }

    onWantChanged: {
        if (want) {
            if (!used[want])
                used = Object.assign({ [want]: true }, used);
            shown = want;
            closeAnim.stop();
            openAnim.restart();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }

    NumberAnimation {
        id: openAnim
        target: host
        property: "openness"
        to: 1
        duration: Theme.anim.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.anim.enter
    }

    NumberAnimation {
        id: closeAnim
        target: host
        property: "openness"
        to: 0
        duration: Theme.anim.fast
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.anim.exit
        onFinished: {
            if (!host.want)
                host.shown = "";
        }
    }

    Item {
        id: hitBox
        x: host.dx - host.ear
        width: host.vh > 0.5 ? host.dw + host.ear * 2 : 0
        height: host.vh

        // clicks on the panel's empty space stay on the panel instead of
        // reaching the click-away area underneath
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    // ── the shape ───────────────────────────────────────────────────────────
    Shape {
        id: shape

        readonly property real r: host.ear
        readonly property real w: host.dw
        readonly property real h: Math.max(1, host.vh)
        readonly property real er: Math.min(host.ear, h / 2)       // ears grow in with the panel
        readonly property real cr: Math.min(host.corner, h / 2, w / 2)

        x: host.dx - r
        width: w + r * 2
        height: h
        visible: host.vh > 0.5
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Theme.colors.frame
            strokeColor: "transparent"
            strokeWidth: -1
            startX: 0
            startY: 0

            // left ear: from the bar's edge, curving down into the panel's side
            PathArc { x: shape.r; y: shape.er; radiusX: shape.r; radiusY: shape.er }
            PathLine { x: shape.r; y: shape.h - shape.cr }
            PathArc { x: shape.r + shape.cr; y: shape.h; radiusX: shape.cr; radiusY: shape.cr; direction: PathArc.Counterclockwise }
            PathLine { x: shape.r + shape.w - shape.cr; y: shape.h }
            PathArc { x: shape.r + shape.w; y: shape.h - shape.cr; radiusX: shape.cr; radiusY: shape.cr; direction: PathArc.Counterclockwise }
            PathLine { x: shape.r + shape.w; y: shape.er }
            // right ear, back up to the bar
            PathArc { x: shape.r * 2 + shape.w; y: 0; radiusX: shape.r; radiusY: shape.er }
            PathLine { x: 0; y: 0 }
        }
    }

    // ── the contents ────────────────────────────────────────────────────────
    Item {
        id: clipper
        x: host.dx
        width: host.dw
        height: host.vh
        clip: true
        visible: host.vh > 0.5
        opacity: Math.min(1, host.openness * 1.6)

        Item {
            x: host.pad
            // contents drift down into place as the panel opens
            y: host.pad - (1 - host.openness) * Theme.rem(0.5)
            width: host.dw - host.pad * 2
            height: host.dh - host.pad * 2

            PanelSlot {
                id: centrePanel
                name: "centre"
                shownName: host.shown
                active: host.used.centre === true
                sourceComponent: CentrePanel {}
            }

            PanelSlot {
                id: controlsPanel
                name: "controls"
                shownName: host.shown
                active: host.used.controls === true
                sourceComponent: ControlsPanel {}
            }

            PanelSlot {
                id: networkPanel
                name: "network"
                shownName: host.shown
                active: host.used.network === true
                sourceComponent: NetworkPanel {}
            }

            PanelSlot {
                id: wallpaperPanel
                name: "wallpaper"
                shownName: host.shown
                active: host.used.wallpaper === true
                sourceComponent: WallpaperPanel {}
            }
        }
    }

    // one panel's contents; cross-fades when you swap panels
    component PanelSlot: Loader {
        property string name: ""
        property string shownName: ""
        readonly property bool current: shownName === name
        opacity: current ? 1 : 0
        visible: opacity > 0
        enabled: current

        Behavior on opacity {
            NumberAnimation { duration: Theme.anim.fast }
        }
    }
}
