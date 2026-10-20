import QtQuick
import qs.common
import qs.widgets

// A small text or glyph button for panel headers. "checked" gives it a soft
// tinted outline (lavender unless you pass another tint).
Rectangle {
    id: chip

    property string text: ""
    property string label: ""          // for screen readers, when text is a glyph
    property bool checked: false
    property color tint: Theme.colors.accent
    readonly property bool hovered: hit.containsMouse
    signal clicked

    width: chipText.implicitWidth + Theme.space.md * 2
    height: Theme.rem(1.65 * Theme.ui.k)
    radius: Theme.radius.sm
    color: chip.checked ? Theme.alpha(chip.tint, 0.16) : chip.hovered ? Theme.colors.raised : "transparent"
    border.width: chip.checked ? 1 : 0
    border.color: Theme.alpha(chip.tint, 0.4)

    Accessible.role: Accessible.Button
    Accessible.name: chip.label || chip.text

    Behavior on color {
        ColorAnimation { duration: Theme.anim.fast }
    }

    StyledText {
        id: chipText
        anchors.centerIn: parent
        text: chip.text
        color: chip.checked ? chip.tint : chip.hovered ? Theme.colors.text : Theme.colors.subtext
        font.pixelSize: Theme.ui.small
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
