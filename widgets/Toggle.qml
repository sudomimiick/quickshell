import QtQuick
import qs.common

// An on/off switch: lavender track with a dark knob when on, grey when off.
Item {
    id: toggle

    property bool checked: false
    signal toggled

    implicitWidth: Theme.rem(2.3)
    implicitHeight: Theme.rem(1.35)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: toggle.checked ? Theme.colors.accent : Theme.colors.raised

        Behavior on color {
            ColorAnimation { duration: Theme.anim.fast }
        }

        Rectangle {
            readonly property int pad: Theme.rem(0.2)
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? parent.width - width - pad : pad
            width: parent.height - pad * 2
            height: width
            radius: width / 2
            color: toggle.checked ? Theme.colors.ink : Theme.colors.subtext

            Behavior on x {
                NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled()
    }
}
