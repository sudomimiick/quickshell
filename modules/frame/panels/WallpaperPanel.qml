pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.services
import qs.widgets

// The wallpaper picker: your wallpapers in a row, the chosen one in the middle.
//   ← → (h l, Tab, scroll)  choose · Enter or click  set it · Esc  close
// While you browse, the picture you rest on is decoded at full size in the
// background, so setting it starts the transition straight away.
Item {
    id: picker

    readonly property real aspect: Screen.height > 0 ? Screen.width / Screen.height : 16 / 10
    readonly property int thumbH: Theme.rem(8.6 * Theme.ui.k)
    readonly property int thumbW: Math.round(thumbH * aspect)
    readonly property int gap: Theme.rem(0.7)
    readonly property int ring: Theme.rem(0.22)
    readonly property bool open: Drawers.current === "wallpaper"
    readonly property string chosen: Wallpaper.files[list.currentIndex] ?? ""
    property bool moved: false        // you've browsed since opening (don't jump back)

    implicitWidth: Math.round(Math.min(Screen.width * 0.64, Theme.rem(78 * Theme.ui.k)))
    implicitHeight: col.implicitHeight

    function apply(i) {
        const p = Wallpaper.files[i];
        if (!p)
            return;
        Wallpaper.set(p);
        Drawers.close();
    }

    // open on the wallpaper you have now, centred, without a scroll animation
    function showCurrent() {
        if (!list.count)
            return;
        list.currentIndex = Math.max(0, Wallpaper.indexOf(Wallpaper.current));
        list.positionViewAtIndex(list.currentIndex, ListView.Center);
    }

    function opened() {
        picker.moved = false;
        picker.showCurrent();
        Qt.callLater(() => list.forceActiveFocus());
    }

    function go(d) {
        picker.moved = true;
        const n = list.count;
        if (n)
            list.currentIndex = Math.max(0, Math.min(n - 1, list.currentIndex + d));
    }

    Connections {
        target: Drawers
        function onCurrentChanged() {
            if (Drawers.current === "wallpaper")
                picker.opened();
        }
    }

    // the list arrives a moment after opening the first time
    Connections {
        target: Wallpaper
        function onFilesChanged() {
            if (picker.open && !picker.moved)
                Qt.callLater(picker.showCurrent);
        }
    }

    Component.onCompleted: {
        if (picker.open)
            picker.opened();
    }

    // decode the full-size picture of the one you rest on
    Timer {
        id: previewDelay
        interval: 180
        onTriggered: {
            if (picker.open && picker.chosen !== Wallpaper.current)
                Wallpaper.preview = picker.chosen;
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.space.sm

        Heading {
            text: "Wallpapers"
            note: Wallpaper.files.length ? `${list.currentIndex + 1} of ${Wallpaper.files.length}` : ""

            ChipButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: Wallpaper.files.length > 1
                text: "󰒝  Random"
                onClicked: {
                    Wallpaper.random();
                    Drawers.close();
                }
            }
        }

        // ── the strip ───────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: picker.thumbH + picker.ring * 4
            visible: Wallpaper.files.length > 0

            ListView {
                id: list

                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: picker.gap
                clip: true
                focus: true
                keyNavigationEnabled: false // keys are handled below, one wallpaper per press
                boundsBehavior: Flickable.StopAtBounds
                // the chosen one always sits in the middle; the row glides to it
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - picker.thumbW) / 2
                preferredHighlightEnd: (width + picker.thumbW) / 2
                highlightMoveDuration: 220
                highlightMoveVelocity: -1
                // build (and decode) a few screens' worth either side, so nothing pops in
                cacheBuffer: picker.thumbW * 8

                model: ScriptModel {
                    values: Wallpaper.files
                }

                onCurrentIndexChanged: previewDelay.restart()

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_H:
                    case Qt.Key_Backtab:
                        picker.go(-1);
                        break;
                    case Qt.Key_L:
                    case Qt.Key_Tab:
                        picker.go(1);
                        break;
                    case Qt.Key_Left:
                        picker.go(-1);
                        break;
                    case Qt.Key_Right:
                        picker.go(1);
                        break;
                    case Qt.Key_PageUp:
                        picker.go(-5);
                        break;
                    case Qt.Key_PageDown:
                        picker.go(5);
                        break;
                    case Qt.Key_Home:
                        picker.go(-list.count);
                        break;
                    case Qt.Key_End:
                        picker.go(list.count);
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        picker.apply(list.currentIndex);
                        break;
                    default:
                        return; // Esc and the rest go on to the panel
                    }
                    event.accepted = true;
                }

                delegate: Item {
                    id: card

                    required property string modelData
                    required property int index
                    readonly property bool chosen: ListView.isCurrentItem
                    readonly property bool inUse: modelData === Wallpaper.current
                    readonly property string thumb: Wallpaper.thumbUrl(modelData)

                    width: picker.thumbW
                    height: ListView.view ? ListView.view.height : 0
                    scale: chosen ? 1 : 0.84
                    opacity: chosen ? 1 : 0.5

                    Behavior on scale {
                        NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.move }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180 }
                    }

                    // a lavender ring round the chosen one
                    Rectangle {
                        anchors.centerIn: parent
                        width: picker.thumbW + picker.ring * 2
                        height: picker.thumbH + picker.ring * 2
                        radius: Theme.radius.lg + picker.ring
                        color: "transparent"
                        border.width: Math.max(2, Math.round(picker.ring * 0.7))
                        border.color: Theme.colors.accent
                        opacity: card.chosen ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 180 }
                        }
                    }

                    ClippingRectangle {
                        anchors.centerIn: parent
                        width: picker.thumbW
                        height: picker.thumbH
                        radius: Theme.radius.lg
                        color: Theme.colors.surface

                        Image {
                            anchors.fill: parent
                            // the cached thumbnail; the picture itself only if no thumbnailer is installed
                            source: card.thumb || (Wallpaper.scanning ? "" : Wallpaper.url(card.modelData))
                            sourceSize.width: Math.round(picker.thumbW * Screen.devicePixelRatio)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            opacity: status === Image.Ready ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.anim.fast }
                            }
                        }
                    }

                    // the one you have now
                    Rectangle {
                        visible: card.inUse
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: Theme.rem(0.5)
                        anchors.bottomMargin: (parent.height - picker.thumbH) / 2 + Theme.rem(0.5)
                        width: Theme.rem(1.5)
                        height: width
                        radius: width / 2
                        color: Theme.colors.accent

                        StyledText {
                            anchors.centerIn: parent
                            text: "󰄬"
                            color: Theme.colors.ink
                            font.pixelSize: Theme.ui.small
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.apply(card.index)
                    }
                }

            }

            // one wallpaper per scroll notch (clicks go through to the cards)
            MouseArea {
                property real wheelAcc: 0

                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: event => {
                    wheelAcc += event.angleDelta.y || -event.angleDelta.x;
                    while (wheelAcc >= 120) {
                        picker.go(-1);
                        wheelAcc -= 120;
                    }
                    while (wheelAcc <= -120) {
                        picker.go(1);
                        wheelAcc += 120;
                    }
                }
            }

            // the row fades out at both ends
            Rectangle {
                width: Theme.rem(3)
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.colors.frame }
                    GradientStop { position: 1; color: Theme.alpha(Theme.colors.frame, 0) }
                }
            }
            Rectangle {
                anchors.right: parent.right
                width: Theme.rem(3)
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.alpha(Theme.colors.frame, 0) }
                    GradientStop { position: 1; color: Theme.colors.frame }
                }
            }
        }

        // the chosen one's name, and how to drive it
        Item {
            visible: Wallpaper.files.length > 0
            width: parent.width
            height: Theme.rem(1.8 * Theme.ui.k)

            StyledText {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width * 0.6)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: Wallpaper.title(picker.chosen)
                font.pixelSize: Theme.ui.text
            }
            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "← → choose · Enter set · Esc close"
                color: Theme.colors.faint
                font.pixelSize: Theme.ui.tiny
            }
        }

        Hint {
            visible: Wallpaper.files.length === 0
            text: Wallpaper.scanning ? "Looking for wallpapers…"
                : `No pictures in ${Wallpaper.directory.replace(Wallpaper.home, "~")}. Put some there, or point Config.wallpaper.directory somewhere else.`
        }
    }
}
