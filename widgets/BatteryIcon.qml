import QtQuick
import qs.common
import qs.widgets

// A battery drawn as a little horizontal capsule that fills up, with a bolt in
// it while charging. Sized to sit in a bar cell like the glyphs next to it.
Item {
    id: battery

    property real level: 1            // 0…1
    property bool charging: false
    property color color: Theme.colors.text

    readonly property int bodyW: Math.round(Theme.ui.icon * 1.3)
    readonly property int bodyH: Math.round(Theme.ui.icon * 0.66)
    readonly property int nubW: Math.max(2, Math.round(Theme.ui.icon * 0.1))
    readonly property int line: Math.max(1, Math.round(Theme.ui.icon / 12))
    readonly property int gap: line + 1

    implicitWidth: bodyW + nubW + 1
    implicitHeight: Theme.ui.cell

    // the shell
    Rectangle {
        id: body
        anchors.verticalCenter: parent.verticalCenter
        width: battery.bodyW
        height: battery.bodyH
        radius: height / 2
        color: "transparent"
        border.width: battery.line
        border.color: Theme.alpha(battery.color, 0.55)

        // the charge inside it
        Rectangle {
            id: fill
            x: battery.gap
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - battery.gap * 2
            width: Math.max(height, (parent.width - battery.gap * 2) * Math.max(0, Math.min(1, battery.level)))
            radius: height / 2
            color: battery.color
            visible: battery.level > 0.02

            Behavior on width {
                NumberAnimation { duration: Theme.anim.normal }
            }
        }

        // the bolt: light over the empty part, dark over the charge
        StyledText {
            id: bolt
            anchors.centerIn: parent
            visible: battery.charging
            text: "󱐋"
            color: battery.color
            font.pixelSize: Math.round(battery.bodyH * 1.05)
        }

        Item {
            x: fill.x
            y: fill.y
            width: fill.visible ? fill.width : 0
            height: fill.height
            clip: true
            visible: battery.charging

            StyledText {
                x: bolt.x - fill.x
                y: bolt.y - fill.y
                text: bolt.text
                color: Theme.colors.frame
                font.pixelSize: bolt.font.pixelSize
            }
        }
    }

    // the nub
    Rectangle {
        anchors.left: body.right
        anchors.leftMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        width: battery.nubW
        height: Math.round(battery.bodyH * 0.42)
        radius: width / 2
        color: Theme.alpha(battery.color, 0.55)
    }
}
