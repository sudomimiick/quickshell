import QtQuick
import qs.common

// Anything clickable on the bar: no box until you hover it (or its panel is
// open), then a soft grey one. What goes inside is laid out in a row, above the
// button's own mouse area — so an icon inside can take scrolls for itself.
Item {
    id: btn

    default property alias content: row.data
    property bool lit: false
    property int padX: Theme.rem(0.4)
    property alias spacing: row.spacing
    property bool wantsWheel: false       // otherwise scrolls fall through to the bar (workspaces)
    readonly property bool hovered: mouse.containsMouse

    signal clicked(int button)
    signal scrolled(int notches) // +1 = up / away from you

    implicitWidth: row.implicitWidth + padX * 2
    implicitHeight: Theme.rem(Config.bar.height) - Theme.rem(0.7)

    function centreX() {
        return btn.mapToItem(null, btn.width / 2, 0).x;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.md
        color: Theme.colors.raised
        opacity: btn.lit ? 1 : btn.hovered ? 0.7 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.anim.fast }
        }
    }

    MouseArea {
        id: mouse

        property real wheelAcc: 0

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => btn.clicked(event.button)
        onWheel: event => {
            if (!btn.wantsWheel) {
                event.accepted = false;
                return;
            }
            // a mouse notch is 120; touchpads send many small deltas
            wheelAcc += event.angleDelta.y || -event.angleDelta.x;
            while (wheelAcc >= 120) {
                btn.scrolled(1);
                wheelAcc -= 120;
            }
            while (wheelAcc <= -120) {
                btn.scrolled(-1);
                wheelAcc += 120;
            }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.xs
    }
}
