pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The popup stack: top-right of the primary screen, newest on top.
// It's a full-height transparent strip; only the cards themselves take clicks.
PanelWindow {
    id: win

    screen: Scaling.primary
    anchors {
        top: true
        right: true
        bottom: true
    }
    margins {
        top: Theme.space.sm
        right: Theme.space.sm
    }
    implicitWidth: Theme.rem(Config.notifications.width)
    exclusionMode: ExclusionMode.Normal // sit below the bar, reserve no space
    exclusiveZone: 0
    color: "transparent"

    // Hyprland matches its blur rule on this name.
    WlrLayershell.namespace: "qs-notifications"
    WlrLayershell.layer: WlrLayer.Overlay

    mask: Region {
        item: hitArea
    }

    Item {
        id: hitArea
        width: list.width
        height: list.contentHeight
    }

    ListView {
        id: list
        anchors.fill: parent
        spacing: Theme.space.sm
        interactive: false

        // ScriptModel diffs the array, so only changed cards animate.
        model: ScriptModel {
            values: Notifs.popups
            objectProp: "uid"
        }

        delegate: NotificationCard {
            required property var modelData
            entry: modelData
            width: list.width
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim.normal; easing.type: Easing.OutCubic }
                NumberAnimation { property: "x"; from: list.width; to: 0; duration: Theme.anim.slow; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
            }
        }

        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.anim.normal; easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; to: list.width; duration: Theme.anim.normal; easing.type: Easing.InCubic }
            }
        }

        displaced: Transition {
            ParallelAnimation {
                NumberAnimation { property: "y"; duration: Theme.anim.normal; easing.type: Easing.OutCubic }
                // if this interrupted an add/remove, settle the card back in place
                NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim.fast }
                NumberAnimation { property: "x"; to: 0; duration: Theme.anim.fast }
            }
        }
    }
}
