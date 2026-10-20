import QtQuick
import qs.common

// A thin slider. Drag, click anywhere on it, or scroll. `value` runs 0…`to`;
// it only reports `moved` — the owner decides what the value becomes.
// With a `stepSize` it snaps to steps (and a scroll notch is one step), and
// `committed` says when you've let go / stopped scrolling — for settings that
// are expensive to apply on every tiny move.
Item {
    id: slider

    property real value: 0
    property real to: 1
    property bool dim: false              // muted: grey instead of lavender
    property real stepSize: 0             // 0 = continuous
    readonly property real frac: Math.max(0, Math.min(1, value / to))
    readonly property real shown: area.pressed ? slider.snap(area.live) : frac

    signal moved(real value)
    signal committed

    // 0…1 along the track → 0…1, landing on a step if there are steps
    function snap(f) {
        if (!(slider.stepSize > 0))
            return f;
        return Math.round(f * slider.to / slider.stepSize) * slider.stepSize / slider.to;
    }

    implicitWidth: Theme.rem(10)
    implicitHeight: Theme.rem(1.6)

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Theme.rem(0.36)
        radius: height / 2
        color: Theme.colors.raised

        Rectangle {
            width: Math.max(track.height, track.width * slider.shown)
            height: parent.height
            radius: parent.radius
            color: slider.dim ? Theme.colors.faint : Theme.colors.accent
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: slider.shown * (slider.width - width)
        width: Theme.rem(1.0)
        height: width
        radius: width / 2
        color: slider.dim ? Theme.colors.subtext : "#ffffff"
        scale: area.pressed || area.containsMouse ? 1.15 : 1

        Behavior on scale {
            NumberAnimation { duration: Theme.anim.fast }
        }
    }

    MouseArea {
        id: area

        property real live: 0
        property real wheelAcc: 0

        function at(x) {
            return Math.max(0, Math.min(1, x / width));
        }

        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: event => {
            live = at(event.x);
            slider.moved(slider.snap(live) * slider.to);
        }
        onPositionChanged: event => {
            if (pressed) {
                live = at(event.x);
                slider.moved(slider.snap(live) * slider.to);
            }
        }
        onReleased: slider.committed()
        onWheel: event => {
            wheelAcc += event.angleDelta.y || -event.angleDelta.x;
            const notches = Math.trunc(wheelAcc / 120);
            if (notches !== 0) {
                wheelAcc -= notches * 120;
                const step = slider.stepSize > 0 ? slider.stepSize : 0.02 * slider.to;
                slider.moved(Math.max(0, Math.min(slider.to, slider.value + notches * step)));
                settle.restart();
            }
        }
    }

    // scrolling counts as done once the wheel stops for a moment
    Timer {
        id: settle
        interval: 450
        onTriggered: slider.committed()
    }
}
