import QtQuick
import qs.common
import qs.widgets

// One glyph on the bar, centred in a square cell. Every icon on the bar is one
// of these, so they all come out the same size and the same distance apart.
// It can take scrolls (volume, brightness) and a middle click (mute) for itself;
// everything else goes to the button it sits in.
Item {
    id: icon

    property string glyph: ""
    property color color: Theme.colors.text
    property bool scrollable: false
    property bool middleClickable: false

    signal scrolled(int notches)       // +1 = up / away from you
    signal middleClicked

    implicitWidth: Theme.ui.cell
    implicitHeight: Theme.ui.cell

    StyledText {
        anchors.centerIn: parent
        text: icon.glyph
        color: icon.color
        font.pixelSize: Theme.ui.icon

        Behavior on color {
            ColorAnimation { duration: Theme.anim.fast }
        }
    }

    // no hover and no left/right buttons, so the button underneath still gets those
    MouseArea {
        property real wheelAcc: 0

        anchors.fill: parent
        enabled: icon.scrollable || icon.middleClickable
        acceptedButtons: icon.middleClickable ? Qt.MiddleButton : Qt.NoButton
        onClicked: icon.middleClicked()
        onWheel: event => {
            if (!icon.scrollable) {
                event.accepted = false;
                return;
            }
            wheelAcc += event.angleDelta.y || -event.angleDelta.x;
            while (wheelAcc >= 120) {
                icon.scrolled(1);
                wheelAcc -= 120;
            }
            while (wheelAcc <= -120) {
                icon.scrolled(-1);
                wheelAcc += 120;
            }
        }
    }
}
