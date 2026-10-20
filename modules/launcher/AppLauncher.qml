import QtQuick
import Quickshell

// The launcher, one window per monitor; whichever monitor has focus opens.
Scope {
    Variants {
        model: Quickshell.screens

        LauncherWindow {}
    }
}
