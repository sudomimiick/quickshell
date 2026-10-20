import QtQuick
import Quickshell

// The volume / brightness pop-up, one (invisible until needed) per monitor.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: OsdWindow {}
    }
}
