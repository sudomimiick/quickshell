import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.common
import qs.services
import qs.widgets

// The bar.
//   left    launcher · workspaces · focused window
//   centre  time · notifications · date   → calendar + notifications panel
//   right   tray · brightness, volume, Bluetooth · Wi-Fi │ VPN country, battery · power
Item {
    id: bar

    required property var win          // the bar window (for tray menus)
    required property string screenName
    required property HyprlandMonitor monitor

    readonly property int unread: Notifs.unread.length

    // Where a panel hangs from when it's opened by a keybind instead of a click.
    function anchorFor(name) {
        const item = name === "controls" ? controls : name === "network" ? netButton : centre;
        return item.mapToItem(null, item.width / 2, 0).x;
    }

    // where the volume/brightness pop-up hangs: under the controls icons
    readonly property real osdAnchor: right.x + controls.x + controls.width / 2
    onOsdAnchorChanged: Osd.setAnchor(bar.screenName, bar.osdAnchor)
    Component.onCompleted: Osd.setAnchor(bar.screenName, bar.osdAnchor)

    function run(cmd) {
        if (cmd && cmd.length)
            Quickshell.execDetached(cmd);
    }

    function openPanel(name, item) {
        Session.close();
        Drawers.toggle(name, bar.screenName, item.centreX());
    }

    function hoverPanel(name, item) {
        if (Config.bar.hoverSwitch)
            Drawers.hover(name, bar.screenName, item.centreX());
    }

    // empty bar: a click closes whatever is open, a scroll switches workspace
    MouseArea {
        anchors.fill: parent
        onClicked: {
            Drawers.close();
            Session.close();
        }
        onWheel: event => workspaces.wheel(event)
    }

    // ── left ────────────────────────────────────────────────────────────────
    Row {
        id: left
        x: Theme.rem(0.8)
        height: parent.height
        spacing: Theme.space.md

        BarButton {
            anchors.verticalCenter: parent.verticalCenter
            lit: Launcher.active
            onClicked: Launcher.toggle()

            StyledText {
                text: "󰣇"
                color: Theme.colors.accent
                font.pixelSize: Theme.ui.logo
            }
        }

        Workspaces {
            id: workspaces
            anchors.verticalCenter: parent.verticalCenter
            monitor: bar.monitor
        }

        ActiveWindow {
            anchors.verticalCenter: parent.verticalCenter
            // stop well short of the clock
            maxWidth: Math.max(0, centre.x - left.x - x - Theme.space.xl)
        }
    }

    // ── centre ──────────────────────────────────────────────────────────────
    BarButton {
        id: centre
        anchors.centerIn: parent
        padX: Theme.space.md
        spacing: Theme.space.md
        lit: Drawers.current === "centre" && Drawers.screenName === bar.screenName
        onClicked: button => {
            if (button === Qt.RightButton)
                Notifs.dnd = !Notifs.dnd;
            else if (button === Qt.MiddleButton)
                Notifs.hideAllPopups();
            else
                bar.openPanel("centre", centre);
        }
        onHoveredChanged: {
            if (hovered)
                bar.hoverPanel("centre", centre);
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(Time.date, Config.bar.timeFormat)
            font.pixelSize: Theme.ui.text
            font.weight: Font.DemiBold
        }

        // unread count in a soft lavender square; a bell when there's nothing new
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(Theme.rem(1.6 * Theme.ui.k), badge.implicitWidth + Theme.rem(0.7))
            height: Theme.rem(1.6 * Theme.ui.k)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius.sm
                color: Theme.alpha(Theme.colors.accent, 0.16)
                border.width: 1
                border.color: Theme.alpha(Theme.colors.accent, 0.45)
                opacity: bar.unread > 0 && !Notifs.dnd ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: Theme.anim.fast }
                }
            }

            StyledText {
                id: badge
                anchors.centerIn: parent
                text: Notifs.dnd ? "󰂛" : bar.unread > 0 ? (bar.unread > 99 ? "99+" : String(bar.unread)) : "󰂜"
                color: Notifs.dnd ? Theme.colors.faint : bar.unread > 0 ? Theme.colors.accent : Theme.colors.subtext
                font.pixelSize: bar.unread > 0 && !Notifs.dnd ? Theme.ui.small : Theme.ui.icon
                font.weight: Font.DemiBold
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(Time.date, Config.bar.dateFormat)
            color: Theme.colors.subtext
            font.pixelSize: Theme.ui.text
        }
    }

    // ── right ───────────────────────────────────────────────────────────────
    // Every icon sits in the same square cell (BarIcon), so they line up.
    // Two groups, one panel each:
    //   brightness · volume · Bluetooth   → display, sound, Bluetooth
    //   Wi-Fi │ VPN country · battery     → battery and power profile, Wi-Fi, VPN
    Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem(0.8)
        height: parent.height
        spacing: Theme.space.xs

        Tray {
            anchors.verticalCenter: parent.verticalCenter
            menuWindow: bar.win
        }

        BarButton {
            id: controls
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.rem(0.15)
            padX: Theme.rem(0.25)
            lit: Drawers.current === "controls" && Drawers.screenName === bar.screenName
            onClicked: button => {
                if (button !== Qt.MiddleButton)
                    bar.openPanel("controls", controls);
            }
            onHoveredChanged: {
                if (hovered)
                    bar.hoverPanel("controls", controls);
            }

            // scroll: brightness (no number, just the sun filling up)
            BarIcon {
                visible: Brightness.available
                glyph: Brightness.glyph
                scrollable: true
                onScrolled: n => Brightness.step(n)
            }
            // scroll: volume · middle click: mute
            BarIcon {
                glyph: Audio.glyph()
                color: Audio.muted ? Theme.colors.faint : Theme.colors.text
                scrollable: true
                middleClickable: true
                onScrolled: n => Audio.step(n)
                onMiddleClicked: Audio.toggleMute()
            }
            BarIcon {
                visible: Bt.available
                glyph: !Bt.enabled ? "󰂲" : Bt.first ? "󰂱" : "󰂯"
                color: !Bt.enabled ? Theme.colors.faint : Bt.first ? Theme.colors.blue : Theme.colors.text
            }
        }

        // Wi-Fi (or Ethernet), "│ India" / "│ NL" while a VPN is up, then the battery
        BarButton {
            id: netButton
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.rem(0.3)
            padX: Theme.rem(0.25)
            lit: Drawers.current === "network" && Drawers.screenName === bar.screenName
            onClicked: button => {
                if (button !== Qt.MiddleButton)
                    bar.openPanel("network", netButton);
            }
            onHoveredChanged: {
                if (hovered)
                    bar.hoverPanel("network", netButton);
            }

            // middle click: Wi-Fi on/off
            BarIcon {
                glyph: Network.glyph
                color: Network.kind === "offline" ? Theme.colors.faint : Theme.colors.text
                middleClickable: true
                onMiddleClicked: Network.setWifiEnabled(!Network.wifiOn)
            }
            Rectangle {
                visible: Network.vpnShown
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: Math.round(Theme.ui.icon * 0.85)
                color: Theme.alpha(Theme.colors.text, 0.25)
            }
            StyledText {
                visible: Network.vpnShown
                anchors.verticalCenter: parent.verticalCenter
                text: Network.vpnLabel
                color: Network.vpnUp ? Theme.colors.text : Theme.colors.faint
                font.pixelSize: Theme.ui.text
                font.weight: Font.Medium
            }
            Row {
                visible: Battery.available
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.rem(0.3)
                leftPadding: Theme.rem(0.3)
                rightPadding: Theme.rem(0.2)

                BatteryIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    level: Battery.level
                    charging: Battery.charging
                    color: Battery.tint
                }
                StyledText {
                    visible: Config.bar.batteryPercent
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.percent + "%"
                    color: Battery.tint
                    font.pixelSize: Theme.ui.text
                }
            }
        }

        BarButton {
            anchors.verticalCenter: parent.verticalCenter
            padX: Theme.rem(0.25)
            lit: Session.active && Session.screenName === bar.screenName
            onClicked: Session.toggle()

            BarIcon {
                glyph: "⏻"
                color: Theme.colors.critical
            }
        }
    }
}
