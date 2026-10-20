import QtQuick
import Quickshell
import qs.common
import qs.services
import qs.modules.notifications
import qs.modules.screenshot
import qs.modules.launcher
import qs.modules.frame
import qs.modules.osd
import qs.modules.wallpaper

ShellRoot {
    // ── first: what you see the moment you log in ───────────────────────────
    // Quickshell compiles every file each time it starts, so the less that's
    // built before the first frame, the sooner the wallpaper and bar appear.
    Wallpapers {}
    Frames {}

    // ── then, a moment later, everything that waits for you to do something ─
    LazyLoader {
        id: later

        Scope {
            // Singletons start on first use; these must be up even before you use
            // them: the notification daemon owns D-Bus, the launcher indexes apps,
            // and they all register the global shortcuts Hyprland binds to.
            // (Audio, Brightness: volume/brightness keys; Osd: the pop-up;
            // DisplayScale: puts your remembered scale back)
            readonly property var services: [Notifs, Screenshot, Scaling, Launcher, Drawers, Session, Audio, Brightness, Osd, DisplayScale, Wallpaper]

            OsdWindows {}
            NotificationPopups {}
            ScreenshotOverlay {}
            AppLauncher {}
        }
    }

    Timer {
        running: true
        interval: 150 // after the bar's first frame
        onTriggered: later.active = true
    }
}
