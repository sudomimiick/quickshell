import QtQuick
import Quickshell
import qs.common

// The wallpaper on every monitor (unless Config.wallpaper.draw is off).
Scope {
    Variants {
        model: Config.wallpaper.draw ? Quickshell.screens : []

        delegate: WallpaperWindow {}
    }
}
