import QtQuick
import Quickshell
import qs.common

// The little one on top of the power menu: the bundled chibi in the shell's soft
// colours by default (assets/chibi-mono.svg is the grey one), or any image/GIF
// from Config.session.avatar.
// "twirl" spins it on the spot.
Item {
    id: av

    property bool running: true
    property real dpr: 1

    readonly property string spin: Config.session.spin
    readonly property string src: {
        const a = Config.session.avatar;
        if (!a)
            return "file://" + Quickshell.shellPath("assets/chibi.svg");
        const p = a.replace(/^~(?=\/|$)/, String(Quickshell.env("HOME") ?? ""));
        return p.includes("://") ? p : "file://" + p;
    }
    readonly property bool gif: /\.(gif|webp)$/i.test(src)
    readonly property bool turning: spin === "twirl" || spin === "turn"

    // a soft shadow on the floor, narrowing as it turns side-on
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: av.width * 0.5 * (av.spin === "twirl" ? 0.65 + 0.35 * Math.abs(Math.cos(turn.angle * Math.PI / 180)) : 1)
        height: av.height * 0.06
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.35)
        visible: av.spin !== "none"
    }

    Item {
        id: figure
        width: parent.width
        height: parent.height * 0.93

        transform: [
            Rotation {
                id: turn
                origin.x: figure.width / 2
                origin.y: figure.height / 2
                axis {
                    x: 0
                    y: av.spin === "twirl" ? 1 : 0
                    z: av.spin === "twirl" ? 0 : 1
                }
                angle: 0
            },
            Translate {
                id: bob
            }
        ]

        AnimatedImage {
            anchors.fill: parent
            visible: av.gif
            source: av.gif ? av.src : ""
            playing: av.running
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Image {
            anchors.fill: parent
            visible: !av.gif
            source: av.gif ? "" : av.src
            sourceSize: Qt.size(Math.ceil(width * av.dpr), Math.ceil(height * av.dpr))
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    NumberAnimation {
        target: turn
        property: "angle"
        from: 0
        to: 360
        duration: av.spin === "twirl" ? 1400 : 2800
        loops: Animation.Infinite
        running: av.running && av.turning
    }

    SequentialAnimation {
        loops: Animation.Infinite
        running: av.running && (av.spin === "bob" || av.spin === "twirl")
        NumberAnimation { target: bob; property: "y"; to: -av.height * 0.04; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { target: bob; property: "y"; to: 0; duration: 700; easing.type: Easing.InOutSine }
    }
}
