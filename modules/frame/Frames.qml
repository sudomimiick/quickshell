import QtQuick
import Quickshell

// A bar on every monitor, plus the invisible strip that reserves its space.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: perScreen

            required property ShellScreen modelData

            FrameWindow {
                modelData: perScreen.modelData
            }

            Zones {
                screen: perScreen.modelData
            }
        }
    }
}
