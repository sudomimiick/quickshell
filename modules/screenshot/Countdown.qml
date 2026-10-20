import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services
import qs.widgets

// "Screenshot in 3…" pill for delayed captures. Gone before the frame is taken.
PanelWindow {
    id: win

    screen: Screenshot.focusedScreen()
    visible: Screenshot.phase === "countdown" && Screenshot.countdown > 0
    anchors.top: true
    margins.top: Theme.rem(1.5)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: pill.width
    implicitHeight: pill.height

    WlrLayershell.namespace: "qs-screenshot-countdown"
    WlrLayershell.layer: WlrLayer.Overlay

    Rectangle {
        id: pill
        width: label.implicitWidth + Theme.space.xl * 2
        height: label.implicitHeight + Theme.space.md * 2
        radius: height / 2
        color: Theme.colors.overlay
        border.width: 1
        border.color: Theme.colors.border

        StyledText {
            id: label
            anchors.centerIn: parent
            text: `󰄀  Screenshot in ${Screenshot.countdown}`
            font.pixelSize: Theme.font.lg
            font.weight: Font.DemiBold
        }

        // a little bump on every tick
        SequentialAnimation {
            id: bump
            NumberAnimation { target: pill; property: "scale"; to: 1.08; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: pill; property: "scale"; to: 1; duration: 200; easing.type: Easing.OutBack }
        }

        Connections {
            target: Screenshot
            function onCountdownChanged() {
                bump.restart();
            }
        }
    }
}
