pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.common
import qs.services
import qs.widgets
import qs.modules.notifications

// Calendar on the left, notifications on the right — the panel under the clock.
// Notifications keep the popups' gestures: left click closes one, right click opens it.
Item {
    id: centre

    readonly property int count: Notifs.entries.length
    readonly property int listWidth: Theme.rem(20.5 * Theme.ui.k)
    readonly property int maxListHeight: Theme.rem(24 * Theme.ui.k)
    readonly property int gap: Theme.rem(1.8)

    implicitWidth: calendar.implicitWidth + gap + listWidth
    implicitHeight: Math.max(calendar.implicitHeight, notes.implicitHeight)

    Connections {
        target: Drawers
        function onCurrentChanged() {
            if (Drawers.current === "centre")
                calendar.reset();
        }
    }

    Calendar {
        id: calendar
    }

    Rectangle {
        x: calendar.implicitWidth + centre.gap / 2
        width: 1
        height: parent.height
        color: Theme.colors.border
    }

    Item {
        id: notes
        x: calendar.implicitWidth + centre.gap
        width: centre.listWidth
        implicitHeight: header.height + Theme.space.sm + (centre.count > 0 ? list.height : empty.height)

        // ── header ──────────────────────────────────────────────────────────
        Heading {
            id: header
            text: "Notifications"
            note: centre.count > 0 ? String(centre.count) : ""

            ChipButton {
                anchors.verticalCenter: parent.verticalCenter
                text: Notifs.dnd ? "󰂛" : "󰂚"
                label: "Do not disturb"
                checked: Notifs.dnd
                onClicked: Notifs.dnd = !Notifs.dnd
            }
            ChipButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: centre.count > 0
                text: "Clear all"
                onClicked: Notifs.dismissAll()
            }
        }

        // ── the list ────────────────────────────────────────────────────────
        ListView {
            id: list
            y: header.height + Theme.space.sm
            width: parent.width
            height: Math.min(contentHeight, centre.maxListHeight)
            visible: centre.count > 0
            spacing: Theme.space.sm
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            model: ScriptModel {
                values: Notifs.entries
                objectProp: "uid"
            }

            delegate: NotificationCard {
                required property var modelData
                entry: modelData
                history: true
                width: list.width
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim.normal }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.anim.fast }
                NumberAnimation { property: "x"; to: list.width * 0.3; duration: Theme.anim.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.exit }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.anim.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.move }
                NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim.fast }
                NumberAnimation { property: "x"; to: 0; duration: Theme.anim.fast }
            }
        }

        // ── nothing here ────────────────────────────────────────────────────
        Column {
            id: empty
            y: header.height + Theme.space.sm
            width: parent.width
            visible: centre.count === 0
            topPadding: Theme.space.xl
            spacing: Theme.space.xs

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifs.dnd ? "󰂛" : "󰂜"
                color: Theme.colors.faint
                font.pixelSize: Theme.rem(2.1 * Theme.ui.k)
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "You're all caught up"
                color: Theme.colors.subtext
                font.pixelSize: Theme.ui.text
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Notifs.dnd
                text: "Do not disturb is on"
                color: Theme.colors.faint
                font.pixelSize: Theme.ui.small
            }
        }
    }
}
