import QtQuick
import qs.common

// A hairline between two sections of a panel.
Item {
    width: parent ? parent.width : 0
    height: Theme.space.md

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 1
        color: Theme.colors.border
    }
}
