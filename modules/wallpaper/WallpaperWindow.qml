import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// One monitor's wallpaper, on Hyprland's background layer.
//
// Changing it: the new picture is decoded underneath, then the old one splits
// down the middle and its two halves slide apart to the edges while the new one
// settles in from a slight zoom. Both halves are the old picture drawn twice from
// the same decoded image (no copies, no shaders), so it stays smooth.
// Until you've picked a wallpaper nothing is drawn, so hyprpaper & co. still show.
PanelWindow {
    id: win

    required property ShellScreen modelData

    // decode at the screen's real pixel size: sharp, and no bigger than needed
    readonly property real dpr: modelData.devicePixelRatio || 1
    readonly property size decodeSize: Qt.size(Math.round(width * dpr), Math.round(height * dpr))

    property string shown: ""        // fully on screen
    property string incoming: ""     // being revealed
    property real t: 0               // 0 → 1 as the halves slide away
    readonly property string mode: Config.wallpaper.transition

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}

    WlrLayershell.namespace: "qs-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function change(path) {
        if (!path || path === win.incoming || (path === win.shown && !win.incoming))
            return;
        if (!win.shown) {
            // the first one fades in once it's loaded
            win.shown = path;
            win.tryStart();
            return;
        }
        if (split.running) {
            // a new pick mid-transition: finish the old one at once
            split.stop();
            win.shown = win.incoming;
        }
        win.t = 0;
        win.incoming = path; // the halves now cover the screen; the new one loads behind them
        win.tryStart();
    }

    function tryStart() {
        if (base.status === Image.Ready && base.opacity < 1 && !fadeIn.running)
            fadeIn.restart();
        if (win.incoming && base.status === Image.Ready && !split.running)
            split.restart();
        else if (win.incoming && base.status === Image.Error)
            win.incoming = ""; // couldn't read it: keep the old one
    }

    function finish() {
        win.shown = win.incoming;
        win.incoming = "";
        win.t = 0;
    }

    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            win.change(Wallpaper.current);
        }
    }

    Component.onCompleted: win.change(Wallpaper.current)

    // ── the new picture (or the only one) ───────────────────────────────────
    Image {
        id: base
        anchors.fill: parent
        source: Wallpaper.url(win.incoming || win.shown)
        sourceSize: win.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: 0
        // settles in from a slight zoom while the halves part
        scale: win.incoming && win.mode === "split" ? 1.06 - 0.06 * win.t : 1
        onStatusChanged: win.tryStart()

        // quick, so login doesn't feel like it's waiting on it
        NumberAnimation on opacity {
            id: fadeIn
            running: false
            to: 1
            duration: Theme.anim.fast
            easing.type: Easing.OutCubic
        }
    }

    // the picture being left behind, as two halves (split) or one layer (fade)
    Item {
        id: old
        anchors.fill: parent
        visible: win.incoming !== ""

        Item {
            x: win.mode === "split" ? -win.t * win.width / 2 : 0
            width: win.width / 2
            height: win.height
            clip: true
            opacity: win.mode === "fade" ? 1 - win.t : 1

            Image {
                width: win.width
                height: win.height
                source: Wallpaper.url(win.shown)
                sourceSize: win.decodeSize
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            // a soft shadow along the opening edge
            Rectangle {
                anchors.right: parent.right
                width: Theme.rem(4)
                height: parent.height
                visible: win.mode === "split"
                opacity: Math.min(1, win.t * 4)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }
        }

        Item {
            x: win.width / 2 + (win.mode === "split" ? win.t * win.width / 2 : 0)
            width: win.width - win.width / 2
            height: win.height
            clip: true
            opacity: win.mode === "fade" ? 1 - win.t : 1

            Image {
                x: -win.width / 2
                width: win.width
                height: win.height
                source: Wallpaper.url(win.shown)
                sourceSize: win.decodeSize
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Rectangle {
                width: Theme.rem(4)
                height: parent.height
                visible: win.mode === "split"
                opacity: Math.min(1, win.t * 4)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.45) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
    }

    NumberAnimation {
        id: split
        target: win
        property: "t"
        from: 0
        to: 1
        duration: win.mode === "none" ? 0 : Config.wallpaper.duration
        // start gently, open fast, glide out
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.65, 0, 0.25, 1, 1, 1]
        onFinished: win.finish()
    }

    // the picker's current choice, decoded at full size ahead of time: when you
    // press Enter it's already in memory and the transition starts at once
    Image {
        visible: false
        source: Wallpaper.url(Wallpaper.preview)
        sourceSize: win.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
}
