import QtQuick
import qs.common

// Text with the shell's font and colour already set. Use it everywhere instead of Text.
Text {
    color: Theme.colors.text
    font.family: Theme.font.family
    font.pixelSize: Theme.font.md
}
