import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

// An invisible strip that only reserves the bar's height, so tiled windows start
// under the bar instead of behind it. (The bar's own window covers the whole
// screen so panels can grow out of it, and a full-screen layer can't reserve an
// edge; only a surface anchored to one side can.)
Scope {
    id: zones

    required property ShellScreen screen

    PanelWindow {
        screen: zones.screen
        anchors {
            top: true
            left: true
            right: true
        }
        color: "transparent"
        implicitHeight: 1
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: Theme.rem(Config.bar.height)
        mask: Region {}
        WlrLayershell.namespace: "qs-frame-zone"
        WlrLayershell.layer: WlrLayer.Bottom
    }
}
