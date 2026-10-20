import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.widgets

// The focused app's name — "Firefox", "Kitty", "Files" — not the window title.
// From its desktop entry when it has one, otherwise tidied up from its app id
// ("org.gnome.Nautilus" → "Nautilus"). Nothing focused → Config.bar.windowFallback.
Item {
    id: aw

    property real maxWidth: Theme.rem(28)

    // (not "top": Item already has a FINAL anchor line by that name)
    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property var entry: toplevel?.appId ? DesktopEntries.heuristicLookup(toplevel.appId) : null
    readonly property string title: toplevel ? aw.appName(toplevel.appId, entry?.name ?? "", toplevel.title) : Config.bar.windowFallback

    function appName(appId, entryName, windowTitle) {
        if (entryName)
            return entryName;
        // "org.gnome.Nautilus" → "Nautilus", "code-oss" → "Code oss", "firefox" → "Firefox"
        const last = String(appId ?? "").split(".").filter(s => !!s).pop() ?? "";
        const words = last.replace(/[-_]+/g, " ").trim();
        if (words)
            return words.charAt(0).toUpperCase() + words.slice(1);
        return windowTitle ?? "";
    }

    implicitWidth: Math.min(maxWidth, row.implicitWidth)
    implicitHeight: Theme.rem(Config.bar.height)
    clip: true

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.sm

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, aw.maxWidth))
            text: aw.title
            elide: Text.ElideRight
            color: aw.toplevel ? Theme.alpha(Theme.colors.text, 0.8) : Theme.colors.faint
            font.pixelSize: Theme.ui.text
        }
    }
}
