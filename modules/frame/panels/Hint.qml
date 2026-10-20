import QtQuick
import qs.common
import qs.widgets

// A line of quiet text in a panel ("No devices yet", "Wi-Fi is off").
StyledText {
    width: parent ? parent.width : 0
    wrapMode: Text.WordWrap
    color: Theme.colors.faint
    font.pixelSize: Theme.ui.small
    topPadding: Theme.space.xs
    bottomPadding: Theme.space.xs
}
