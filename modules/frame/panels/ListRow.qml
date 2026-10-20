import QtQuick
import qs.common
import qs.widgets

// One row in a panel list: a glyph, a title, an optional second line, and
// anything you put inside it on the right (a switch, a button, a note).
// Selected rows get a soft tint (lavender unless you pass another).
Rectangle {
    id: row

    property string glyph: ""
    property color glyphColor: Theme.colors.subtext
    property string title: ""
    property string subtitle: ""
    property color subtitleColor: Theme.colors.subtext
    property bool selected: false
    property color tint: Theme.colors.accent
    property bool clickable: true
    default property alias trailing: tail.data
    readonly property bool hovered: hit.containsMouse
    readonly property int baseHeight: row.subtitle !== "" ? Theme.rem(2.7 * Theme.ui.k) : Theme.rem(2.25 * Theme.ui.k)

    signal clicked(int button)

    width: parent ? parent.width : 0
    height: baseHeight
    radius: Theme.radius.md
    color: row.selected ? Theme.alpha(row.tint, 0.13) : row.hovered && row.clickable ? Theme.colors.surface : "transparent"

    Behavior on color {
        ColorAnimation { duration: Theme.anim.fast }
    }

    // Everything sits inside the mouse area, so hovering a button on the right
    // still counts as hovering the row.
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (row.clickable)
                row.clicked(event.button);
        }

        StyledText {
            id: glyphText
            x: Theme.space.sm
            y: (row.baseHeight - height) / 2
            width: row.glyph !== "" ? Theme.rem(1.6 * Theme.ui.k) : 0
            horizontalAlignment: Text.AlignHCenter
            text: row.glyph
            color: row.selected ? row.tint : row.glyphColor
            font.pixelSize: Theme.ui.icon
        }

        Column {
            anchors.left: glyphText.right
            anchors.leftMargin: row.glyph !== "" ? Theme.space.sm : 0
            anchors.right: tail.left
            anchors.rightMargin: Theme.space.sm
            y: (row.baseHeight - height) / 2
            spacing: Theme.rem(0.08)

            StyledText {
                width: parent.width
                text: row.title
                elide: Text.ElideRight
                color: row.selected ? Theme.colors.text : Theme.alpha(Theme.colors.text, 0.86)
                font.pixelSize: Theme.ui.text
                font.weight: row.selected ? Font.Medium : Font.Normal
            }
            StyledText {
                width: parent.width
                visible: row.subtitle !== ""
                text: row.subtitle
                elide: Text.ElideRight
                color: row.subtitleColor
                font.pixelSize: Theme.ui.small
            }
        }

        Row {
            id: tail
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.sm
            height: row.baseHeight
            spacing: Theme.space.sm
        }
    }
}
