import QtQuick
import Quickshell

// One frozen-frame overlay per monitor, plus the countdown pill.
Scope {
    Variants {
        model: Quickshell.screens

        ShotWindow {}
    }

    Countdown {}
}
