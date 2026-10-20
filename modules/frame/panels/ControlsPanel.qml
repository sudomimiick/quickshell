pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.common
import qs.services
import qs.widgets

// The panel under the brightness · volume · Bluetooth icons:
//   Display    brightness, and Hyprland's scale for this screen
//   Sound      volume, microphone, where it plays
//   Bluetooth  on/off, scan, your devices
Item {
    id: panel

    readonly property int rowGap: Theme.rem(0.12)
    readonly property int maxDeviceRows: 4

    implicitWidth: Theme.rem(22 * Theme.ui.k)
    implicitHeight: col.implicitHeight

    // scan only while you're looking at the list
    Connections {
        target: Drawers
        function onCurrentChanged() {
            if (Drawers.current !== "controls")
                Bt.setScanning(false);
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.space.sm

        // ── display ─────────────────────────────────────────────────────────
        Heading {
            visible: Brightness.available || DisplayScale.available
            text: "Display"

            ChipButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: DisplayScale.remembered
                text: "Reset scale"
                onClicked: DisplayScale.reset()
            }
        }

        LevelRow {
            visible: Brightness.available
            glyph: Brightness.glyph
            value: Brightness.value
            showValue: false
            mutable: false
            onMoved: v => Brightness.set(v)
        }

        ScaleRow {
            visible: DisplayScale.available
        }

        Divider {
            visible: Brightness.available || DisplayScale.available
        }

        // ── sound ───────────────────────────────────────────────────────────
        Heading {
            text: "Sound"

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, panel.width * 0.55)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: Audio.sinkName
                color: Theme.colors.subtext
                font.pixelSize: Theme.ui.small
            }
        }

        LevelRow {
            glyph: Audio.glyph()
            value: Audio.volume
            to: Config.audio.max
            muted: Audio.muted
            onToggled: Audio.toggleMute()
            onMoved: v => Audio.setVolume(v)
        }

        LevelRow {
            visible: !!Audio.source
            glyph: Audio.micMuted ? "󰍭" : "󰍬"
            value: Audio.micVolume
            muted: Audio.micMuted
            onToggled: Audio.toggleMicMute()
            onMoved: v => Audio.setMicVolume(v)
        }

        // where sound goes (only worth showing when there's a choice)
        Column {
            width: parent.width
            spacing: panel.rowGap
            visible: Audio.sinks.length > 1

            Repeater {
                model: Audio.sinks

                delegate: ListRow {
                    id: sinkRow
                    required property var modelData
                    glyph: Audio.deviceGlyph(modelData)
                    title: Audio.nameOf(modelData)
                    selected: modelData === Audio.sink
                    onClicked: Audio.useSink(modelData)

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: sinkRow.selected
                        text: "󰄬"
                        color: Theme.colors.accent
                        font.pixelSize: Theme.ui.text
                    }
                }
            }
        }

        // ── Bluetooth ───────────────────────────────────────────────────────
        Divider {
            visible: Bt.available
        }

        Heading {
            visible: Bt.available
            text: "Bluetooth"

            ChipButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: Bt.enabled
                text: Bt.scanning ? "Scanning…" : "Scan"
                checked: Bt.scanning
                tint: Theme.colors.blue
                onClicked: Bt.setScanning(!Bt.scanning)
            }

            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: Bt.enabled
                onToggled: Bt.setEnabled(!Bt.enabled)
            }
        }

        Flickable {
            id: devices
            visible: Bt.available && Bt.enabled && Bt.list.length > 0
            width: parent.width
            height: Math.min(deviceList.implicitHeight, panel.maxDeviceRows * (Theme.rem(2.7 * Theme.ui.k) + panel.rowGap))
            contentWidth: width
            contentHeight: deviceList.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: deviceList
                width: devices.width
                spacing: panel.rowGap

                Repeater {
                    model: ScriptModel {
                        values: Bt.list
                    }

                    delegate: ListRow {
                        required property var modelData
                        glyph: Bt.glyphFor(modelData)
                        title: Bt.nameOf(modelData)
                        subtitle: Bt.status(modelData)
                        subtitleColor: modelData.connected ? Theme.colors.blue : Theme.colors.subtext
                        selected: modelData.connected
                        tint: Theme.colors.blue
                        onClicked: Bt.activate(modelData)
                    }
                }
            }
        }

        Hint {
            visible: Bt.available && Bt.enabled && Bt.list.length === 0
            text: Bt.scanning ? "Looking for devices…" : "No devices yet. Scan to find one."
        }
    }

    // icon (click to mute) · slider · percentage
    component LevelRow: Item {
        id: level

        property string glyph: ""
        property real value: 0
        property real to: 1
        property bool muted: false
        property bool mutable: true       // the icon is a mute button
        property bool showValue: true
        signal toggled
        signal moved(real v)

        width: parent ? parent.width : 0
        height: Theme.rem(2.1 * Theme.ui.k)

        Rectangle {
            id: muteButton
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.rem(2.0 * Theme.ui.k)
            height: width
            radius: Theme.radius.md
            color: level.mutable && muteHit.containsMouse ? Theme.colors.raised : "transparent"

            StyledText {
                anchors.centerIn: parent
                text: level.glyph
                color: level.muted ? Theme.colors.faint : Theme.colors.text
                font.pixelSize: Theme.ui.icon
            }

            MouseArea {
                id: muteHit
                anchors.fill: parent
                enabled: level.mutable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: level.toggled()
            }
        }

        Slider {
            anchors.left: muteButton.right
            anchors.leftMargin: Theme.space.sm
            anchors.right: level.showValue ? percent.left : parent.right
            anchors.rightMargin: level.showValue ? Theme.space.md : Theme.space.sm
            anchors.verticalCenter: parent.verticalCenter
            value: level.value
            to: level.to
            dim: level.muted
            onMoved: v => level.moved(v)
        }

        StyledText {
            id: percent
            visible: level.showValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.rem(2.7 * Theme.ui.k)
            horizontalAlignment: Text.AlignRight
            text: Math.round(level.value * 100) + "%"
            color: Theme.colors.subtext
            font.pixelSize: Theme.ui.small
        }
    }

    // Hyprland's scale for this screen. It snaps to scales Hyprland accepts and
    // is applied when you let go (or stop scrolling) — not on every step.
    component ScaleRow: Item {
        id: scaleRow

        property int pending: -1
        readonly property var options: DisplayScale.options
        readonly property int currentIndex: DisplayScale.indexOf(options, DisplayScale.current)
        readonly property int shownIndex: pending >= 0 ? pending : currentIndex

        // always sent, even when it looks unchanged: what Hyprland really has can
        // differ from what the shell last heard, and sending the same scale is harmless
        function commit() {
            const s = scaleRow.options[scaleRow.pending];
            if (scaleRow.pending < 0 || s === undefined) {
                scaleRow.pending = -1;
                return;
            }
            DisplayScale.apply(s);
            giveUp.restart();
        }

        width: parent ? parent.width : 0
        height: Theme.rem(2.1 * Theme.ui.k)

        Connections {
            target: DisplayScale
            function onCurrentChanged() {
                scaleRow.pending = -1;
            }
        }

        // if Hyprland didn't take it, show what it really is again
        Timer {
            id: giveUp
            interval: 4000
            onTriggered: scaleRow.pending = -1
        }

        StyledText {
            id: scaleGlyph
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.rem(2.0 * Theme.ui.k)
            horizontalAlignment: Text.AlignHCenter
            text: "󰩨"
            font.pixelSize: Theme.ui.icon
        }

        Slider {
            anchors.left: scaleGlyph.right
            anchors.leftMargin: Theme.space.sm
            anchors.right: scaleText.left
            anchors.rightMargin: Theme.space.md
            anchors.verticalCenter: parent.verticalCenter
            to: Math.max(1, scaleRow.options.length - 1)
            stepSize: 1
            value: scaleRow.shownIndex
            onMoved: v => scaleRow.pending = Math.round(v)
            onCommitted: scaleRow.commit()
        }

        StyledText {
            id: scaleText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.rem(2.7 * Theme.ui.k)
            horizontalAlignment: Text.AlignRight
            text: DisplayScale.label(scaleRow.options[scaleRow.shownIndex] ?? DisplayScale.current)
            color: scaleRow.pending >= 0 ? Theme.colors.accent : Theme.colors.subtext
            font.pixelSize: Theme.ui.small
        }
    }
}
