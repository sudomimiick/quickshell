pragma Singleton

import QtQuick
import Quickshell

// One clock for the whole shell, ticking on the minute.
Singleton {
    readonly property date date: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
