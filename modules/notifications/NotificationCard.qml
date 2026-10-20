pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.common
import qs.services
import qs.widgets

// One notification card.
//   left click   → close it
//   right click  → open it (the app's default action, else focus or launch the app)
//   middle click → slide every popup into history
//   hover        → pauses the countdown
Item {
    id: card

    required property var entry
    property bool history: false // in the notification centre: no countdown, no popup gestures

    readonly property color accent: entry.accent
    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property int timeout: history ? 0 : Notifs.timeoutFor(entry)
    readonly property bool hovered: hover.hovered

    readonly property string iconSrc: resolve(entry.appIcon) || resolve(entry.appName.toLowerCase())
    readonly property string imageSrc: resolve(entry.image)
    readonly property bool hasImage: imageSrc !== "" && avatar.status !== Image.Error
    // screenshots get a real preview instead of a small thumbnail
    readonly property bool wide: hasImage && /screenshot/i.test(entry.appName)

    // Action buttons; "default" isn't shown because right click runs it.
    readonly property var buttons: {
        const n = entry.notification;
        const out = [];
        if (!n)
            return out;
        for (let i = 0; i < n.actions.length; i++)
            if (n.actions[i].identifier !== "default")
                out.push(n.actions[i]);
        return out;
    }

    property real remaining: 1 // countdown, 1 → 0

    implicitHeight: content.implicitHeight + Theme.space.lg * 2
    height: implicitHeight

    // Icon name, absolute path or URL → something Image can load ("" if nothing).
    function resolve(src) {
        if (!src)
            return "";
        if (src.startsWith("/"))
            return "file://" + src;
        if (src.includes("://"))
            return src;
        return Quickshell.iconPath(src, true);
    }

    // Apps may send a little markup (<b>, <i>, <a>). Keep that, neutralise the rest.
    function formatBody(b) {
        if (!b)
            return "";
        return b.replace(/<img[^>]*>/gi, "")
                .replace(/<(?!\/?(b|i|u|a|br)\b)/gi, "&lt;")
                .replace(/\n/g, "<br/>");
    }

    // ── timeout ──────────────────────────────────────────────────────────────

    NumberAnimation {
        id: countdown
        target: card
        property: "remaining"
        from: 1
        to: 0
        duration: card.timeout
        running: card.timeout > 0
        paused: running && card.hovered
        onFinished: Notifs.hidePopup(card.entry)
    }

    Connections {
        target: card.entry
        function onRevisionChanged() {
            if (card.timeout > 0)
                countdown.restart();
        }
    }

    // ── background ───────────────────────────────────────────────────────────

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radius.lg
        color: card.history ? Theme.colors.surface : Theme.colors.base
        border.width: 1
        border.color: card.critical ? Theme.alpha(Theme.colors.critical, 0.7) : card.hovered ? Theme.alpha(Theme.colors.text, 0.16) : Theme.colors.border

        Behavior on border.color {
            ColorAnimation { duration: Theme.anim.fast }
        }
    }

    // ── input ────────────────────────────────────────────────────────────────

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        enabled: !card.entry.gone
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.RightButton)
                Notifs.open(card.entry);
            else if (event.button === Qt.MiddleButton) {
                if (!card.history)
                    Notifs.hideAllPopups();
            } else
                Notifs.dismiss(card.entry);
        }
    }

    // ── content ──────────────────────────────────────────────────────────────

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.space.lg
        }
        spacing: Theme.space.sm

        // header: app · time ············ hint
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.xs

            StyledText {
                Layout.maximumWidth: card.width * 0.55
                text: card.entry.appName || "Notification"
                color: card.critical ? Theme.colors.critical : Theme.colors.subtext
                font.pixelSize: Theme.font.xs
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
                elide: Text.ElideRight
            }

            StyledText {
                text: "·  " + Notifs.relTime(card.entry.time)
                color: Theme.colors.subtext
                font.pixelSize: Theme.font.xs
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                visible: Config.notifications.showHints
                opacity: card.hovered ? 0.75 : 0
                text: "L close · R open"
                color: Theme.colors.subtext
                font.pixelSize: Theme.font.xs

                Behavior on opacity {
                    NumberAnimation { duration: Theme.anim.fast }
                }
            }
        }

        // icon/avatar + text
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.md

            Item {
                id: visual
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: Theme.rem(2.75)
                Layout.preferredHeight: Theme.rem(2.75)

                // The notification's own picture (avatar, album art, thumbnail).
                ClippingRectangle {
                    anchors.fill: parent
                    visible: card.hasImage && !card.wide
                    radius: Theme.radius.md
                    color: Theme.colors.overlay

                    Image {
                        id: avatar
                        anchors.fill: parent
                        source: card.imageSrc
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(width * 2, height * 2)
                    }
                }

                // No picture: the app icon on a tinted tile (or its first letter).
                Rectangle {
                    anchors.fill: parent
                    visible: !card.hasImage || card.wide
                    radius: Theme.radius.md
                    color: Theme.colors.raised

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.round(parent.width * 0.6)
                        source: card.iconSrc
                        asynchronous: true
                        visible: card.iconSrc !== ""
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: card.iconSrc === ""
                        text: (card.entry.appName || "?").charAt(0).toUpperCase()
                        color: Theme.colors.text
                        font.pixelSize: Math.round(parent.width * 0.45)
                        font.weight: Font.Bold
                    }
                }

                // Picture + icon: the icon becomes a small badge.
                Rectangle {
                    visible: card.hasImage && !card.wide && card.iconSrc !== ""
                    width: Theme.rem(1.25)
                    height: width
                    radius: width / 2
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: -Theme.rem(0.25)
                    }
                    color: Theme.colors.raised
                    border.width: 1
                    border.color: Theme.colors.border

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.round(parent.width * 0.68)
                        source: card.iconSrc
                        asynchronous: true
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Theme.rem(0.15)

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.entry.summary
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.font.md
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.formatBody(card.entry.body)
                    textFormat: Text.StyledText
                    color: Theme.colors.subtext
                    linkColor: Theme.colors.text
                    font.pixelSize: Theme.font.sm
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
        }

        // screenshot preview
        ClippingRectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Theme.rem(11), width * (preview.implicitWidth > 0 ? preview.implicitHeight / preview.implicitWidth : 0.5625))
            visible: card.wide
            radius: Theme.radius.md
            color: Theme.colors.overlay

            Image {
                id: preview
                anchors.fill: parent
                source: card.wide ? card.imageSrc : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: Math.round(parent.width * 2)
            }
        }

        // action buttons
        Flow {
            Layout.fillWidth: true
            visible: card.buttons.length > 0
            spacing: Theme.space.xs

            Repeater {
                model: card.buttons

                delegate: Rectangle {
                    id: pill
                    required property var modelData

                    implicitWidth: pillLabel.implicitWidth + Theme.space.md * 2
                    implicitHeight: pillLabel.implicitHeight + Theme.space.xs * 2
                    radius: Theme.radius.sm
                    color: pillHover.hovered ? Qt.lighter(Theme.colors.raised, 1.35) : Theme.colors.raised

                    Behavior on color {
                        ColorAnimation { duration: Theme.anim.fast }
                    }

                    StyledText {
                        id: pillLabel
                        anchors.centerIn: parent
                        text: pill.modelData.text
                        font.pixelSize: Theme.font.sm
                        font.weight: Font.Medium
                    }

                    HoverHandler {
                        id: pillHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Notifs.invokeAction(card.entry, pill.modelData)
                    }
                }
            }
        }

        // countdown line (dims while paused)
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space.xs
            visible: card.timeout > 0
            implicitHeight: Math.max(2, Theme.rem(0.15))
            radius: height / 2
            color: Theme.alpha(Theme.colors.text, 0.07)

            Rectangle {
                width: parent.width * card.remaining
                height: parent.height
                radius: parent.radius
                color: Theme.alpha(Theme.colors.text, card.hovered ? 0.25 : 0.5)
            }
        }
    }
}
