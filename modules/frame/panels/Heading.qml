import QtQuick
import qs.common
import qs.widgets

// A panel section's title, with an optional note after it and controls on the right.
//   Heading { text: "Wi-Fi"; Toggle { … } }
Item {
    id: heading

    property string text: ""
    property string note: ""
    default property alias trailing: tail.data

    width: parent ? parent.width : 0
    height: Theme.rem(1.95 * Theme.ui.k)

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.sm

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: heading.text
            font.pixelSize: Theme.ui.title
            font.weight: Font.DemiBold
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: heading.note !== ""
            text: heading.note
            color: Theme.colors.subtext
            font.pixelSize: Theme.ui.small
        }
    }

    Row {
        id: tail
        anchors.right: parent.right
        height: parent.height
        spacing: Theme.space.sm
    }
}
