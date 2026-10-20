import QtQuick
import QtQuick.Layouts
import qs.common

// A rounded button: icon (Nerd Font glyph), label, and an optional faint key hint.
Rectangle {
    id: btn

    property string icon: ""
    property string label: ""
    property string hint: ""
    property bool primary: false
    property color accent: Theme.colors.accent
    readonly property bool hovered: area.containsMouse

    signal clicked

    implicitWidth: row.implicitWidth + Theme.space.md * 2
    implicitHeight: row.implicitHeight + Theme.space.sm * 2
    radius: height / 2
    color: primary
        ? (hovered ? "#ffffff" : accent)
        : Theme.alpha(Theme.colors.text, hovered ? 0.14 : 0.06)
    readonly property color ink: primary ? Theme.colors.ink : Theme.colors.text

    Behavior on color {
        ColorAnimation { duration: Theme.anim.fast }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.xs

        StyledText {
            visible: btn.icon !== ""
            text: btn.icon
            color: btn.ink
            font.pixelSize: Theme.font.md
        }
        StyledText {
            visible: btn.label !== ""
            text: btn.label
            color: btn.ink
            font.pixelSize: Theme.font.sm
            font.weight: Font.Medium
        }
        StyledText {
            visible: btn.hint !== ""
            text: btn.hint
            color: btn.ink
            font.pixelSize: Theme.font.xs
            opacity: 0.55
        }
    }

    // A MouseArea (not a TapHandler) so the press never leaks to whatever is underneath.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
