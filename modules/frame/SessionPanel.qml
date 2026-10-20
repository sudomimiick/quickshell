import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.common
import qs.services
import qs.widgets

// The power menu. The screen under the bar greys out and a full-height panel
// slides in from the right, joined to the bar by the same curved ear as the
// panels — the chibi spinning on top, the actions underneath. Opens in about a
// fifth of a second.
//   ↑ ↓ / Tab · Enter · or the letter on its keycap · Esc or a click outside to go back
FocusScope {
    id: panel

    required property string screenName
    property int barHeight: 0       // the bar
    property int corner: 0          // the screen's rounded top corners
    property real dpr: 1

    readonly property bool here: Session.active && Session.screenName === screenName
    readonly property var actions: Session.actions
    property real t: 0              // 0 hidden … 1 fully out
    property int selected: 0
    property real uptime: 0

    // the curve joining it to the bar (1px when Config.bar.ears is off: an arc of 0 breaks the path maths)
    readonly property int ear: Config.bar.ears ? Theme.radius.lg : 1
    readonly property int pad: Theme.rem(1.4)
    readonly property int fullW: Math.round(Math.min(width / 5, Math.max(Theme.rem(15), width * Config.session.width)))
    readonly property real edgeX: width - fullW * t                    // the panel's left edge, sliding in
    readonly property int areaH: height - barHeight

    // one muted colour per action
    function tintFor(id) {
        switch (id) {
        case "lock":
        case "hibernate":
            return Theme.colors.blue;
        case "suspend":
            return Theme.colors.accent;
        case "logout":
            return Theme.colors.green;
        case "reboot":
            return Theme.colors.warn;
        case "poweroff":
            return Theme.colors.critical;
        }
        return Theme.colors.text;
    }

    onHereChanged: {
        if (here) {
            panel.selected = 0;
            uptimeFile.reload();
            outAnim.stop();
            inAnim.restart();
            panel.forceActiveFocus();
        } else {
            inAnim.stop();
            outAnim.restart();
        }
    }

    NumberAnimation {
        id: inAnim
        target: panel
        property: "t"
        to: 1
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.anim.enter
    }

    NumberAnimation {
        id: outAnim
        target: panel
        property: "t"
        to: 0
        duration: 150
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.anim.exit
        onFinished: Session.runPending() // the chosen action, now that we're off screen
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: panel.uptime = parseFloat(uptimeFile.text()) || 0
    }

    function move(d) {
        const n = panel.actions.length;
        panel.selected = ((panel.selected + d) % n + n) % n;
    }

    function handleKey(key, text) {
        if (key === Qt.Key_Escape) {
            Session.close();
            return true;
        }
        if (key === Qt.Key_Up || key === Qt.Key_Backtab || key === Qt.Key_K) {
            panel.move(-1);
            return true;
        }
        if (key === Qt.Key_Down || key === Qt.Key_Tab || key === Qt.Key_J) {
            panel.move(1);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            Session.choose(panel.actions[panel.selected].id);
            return true;
        }
        const letter = String(text ?? "").toUpperCase();
        for (const a of panel.actions) {
            if (letter && a.key === letter) {
                Session.choose(a.id);
                return true;
            }
        }
        return false;
    }

    Keys.onPressed: event => {
        if (panel.here && panel.handleKey(event.key, event.text))
            event.accepted = true;
    }

    // ── the grey-out, under the bar (its top corners follow the screen's) ──
    Rectangle {
        y: panel.barHeight
        width: panel.width
        height: panel.areaH + panel.corner * 2   // bottom corners off screen
        radius: panel.corner
        color: "black"
        opacity: 0.45 * panel.t
        visible: panel.t > 0
    }

    // ── the panel: full height, grown out of the bar on the right ───────────
    Shape {
        id: shape

        readonly property real r: panel.ear
        readonly property real w: panel.fullW
        readonly property real h: panel.areaH

        x: panel.edgeX - r
        y: panel.barHeight
        width: w + r
        height: h
        visible: panel.t > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Theme.colors.frame
            strokeColor: "transparent"
            strokeWidth: -1
            startX: 0
            startY: 0

            // the ear: from the bar's bottom edge, curving down into the panel's side
            PathArc { x: shape.r; y: shape.r; radiusX: shape.r; radiusY: shape.r }
            PathLine { x: shape.r; y: shape.h }
            PathLine { x: shape.r + shape.w; y: shape.h }
            PathLine { x: shape.r + shape.w; y: 0 }
            PathLine { x: 0; y: 0 }
        }
    }

    // clicks on the panel stay on the panel instead of closing it
    MouseArea {
        x: panel.edgeX
        y: panel.barHeight
        width: panel.fullW
        height: panel.areaH
        visible: panel.t > 0
        acceptedButtons: Qt.AllButtons
    }

    // ── what's on it ────────────────────────────────────────────────────────
    Column {
        id: content
        x: panel.edgeX + panel.pad
        y: panel.barHeight + Math.max(panel.pad, (panel.areaH - implicitHeight) / 2)
        width: panel.fullW - panel.pad * 2
        visible: panel.t > 0
        spacing: Theme.space.sm
        opacity: Math.min(1, panel.t * 1.4)

        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(content.width * 0.85, Theme.rem(13))
            height: width * 1.12
            running: panel.t > 0
            dpr: panel.dpr
        }

        Item {
            width: 1
            height: Theme.space.sm
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Session.user || "you"
            font.pixelSize: Theme.rem(1.25 * Theme.ui.k)
            font.weight: Font.DemiBold
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: [Session.host, panel.uptime > 0 ? "up " + Session.uptime(panel.uptime) : ""].filter(s => !!s).join("  ·  ")
            color: Theme.colors.subtext
            font.pixelSize: Theme.ui.small
        }

        Item {
            width: 1
            height: Theme.space.xl
        }

        Repeater {
            model: panel.actions

            delegate: Item {
                id: btn

                required property var modelData
                required property int index
                readonly property bool sel: panel.selected === index
                readonly property color tint: panel.tintFor(modelData.id)

                width: content.width
                height: Theme.rem(2.6 * Theme.ui.k)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius.md
                    color: Theme.alpha(btn.tint, 0.15)
                    opacity: btn.sel ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.anim.fast }
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space.md
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.md

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.rem(1.5)
                        horizontalAlignment: Text.AlignHCenter
                        text: btn.modelData.glyph
                        color: btn.sel ? btn.tint : Theme.colors.subtext
                        font.pixelSize: Theme.ui.icon
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: btn.modelData.label
                        color: btn.sel ? Theme.colors.text : Theme.alpha(Theme.colors.text, 0.82)
                        font.pixelSize: Theme.ui.text
                        font.weight: btn.sel ? Font.DemiBold : Font.Normal
                    }
                }

                // its key, as a little keycap
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space.sm
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.rem(1.4 * Theme.ui.k)
                    height: width
                    radius: Theme.radius.sm
                    color: "transparent"
                    border.width: 1
                    border.color: btn.sel ? Theme.alpha(btn.tint, 0.55) : Theme.colors.border

                    StyledText {
                        anchors.centerIn: parent
                        text: btn.modelData.key
                        color: btn.sel ? btn.tint : Theme.colors.faint
                        font.pixelSize: Theme.ui.tiny
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: panel.selected = btn.index
                    onClicked: Session.choose(btn.modelData.id)
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: Theme.space.md
            text: "Esc to go back"
            color: Theme.colors.faint
            font.pixelSize: Theme.ui.tiny
        }
    }
}
