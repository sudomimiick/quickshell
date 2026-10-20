pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.services
import qs.widgets

// Battery charge and the power profile (three circles, the one in use filled).
// On a desktop without a battery it's just "Power" and the circles; with neither
// it hides itself.
Column {
    id: section

    readonly property bool wanted: Battery.available || Battery.profilesAvailable

    visible: wanted
    width: parent ? parent.width : 0
    spacing: Theme.space.sm

    Heading {
        text: Battery.available ? "Battery" : "Power"
        note: Battery.available ? `${Battery.percent}% · ${Battery.status}` : ""

        BatteryIcon {
            visible: Battery.available
            anchors.verticalCenter: parent.verticalCenter
            level: Battery.level
            charging: Battery.charging
            color: Battery.tint
        }
    }

    Item {
        visible: Battery.profilesAvailable
        width: parent.width
        height: Theme.rem(2.6 * Theme.ui.k)

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.rem(0.08)

            StyledText {
                text: Battery.profileName
                font.pixelSize: Theme.ui.text
            }
            StyledText {
                text: "Power profile"
                color: Theme.colors.subtext
                font.pixelSize: Theme.ui.small
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.sm

            Repeater {
                model: Battery.profiles

                delegate: Rectangle {
                    id: dot

                    required property var modelData
                    readonly property bool current: Battery.profile === modelData.id

                    width: Theme.rem(2.2 * Theme.ui.k)
                    height: width
                    radius: width / 2
                    color: dot.current ? Theme.colors.accent : dotHit.containsMouse ? Theme.colors.raised : Theme.colors.surface
                    border.width: dot.current ? 0 : 1
                    border.color: Theme.colors.border

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.name

                    Behavior on color {
                        ColorAnimation { duration: Theme.anim.fast }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: dot.modelData.glyph
                        color: dot.current ? Theme.colors.ink : dotHit.containsMouse ? Theme.colors.text : Theme.colors.subtext
                        font.pixelSize: Theme.ui.icon
                    }

                    MouseArea {
                        id: dotHit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Battery.setProfile(dot.modelData.id)
                    }
                }
            }
        }
    }
}
