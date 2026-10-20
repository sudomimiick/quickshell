pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.common
import qs.services
import qs.widgets

// Battery, Wi-Fi, Ethernet and VPNs — the panel under the Wi-Fi and battery icons.
//   Battery: charge, and the power profile as three circles.
//   Wi-Fi: click a network to join it (it asks for a password when it needs one),
//          hover for Disconnect / Forget, right click a saved one to forget it.
//   VPN:   one switch per VPN — your VPN apps from Config.network.vpnProviders,
//          then every VPN and WireGuard profile in NetworkManager.
Item {
    id: panel

    readonly property int rowGap: Theme.rem(0.12)
    readonly property int maxListHeight: Config.network.maxNetworks * (Theme.rem(2.7 * Theme.ui.k) + rowGap)

    implicitWidth: Theme.rem(22 * Theme.ui.k)
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: Theme.space.sm

        // ── battery and power profile ───────────────────────────────────────
        BatterySection {
            id: battery
        }

        Divider {
            visible: battery.wanted
        }

        // ── Wi-Fi ───────────────────────────────────────────────────────────
        Heading {
            text: "Wi-Fi"

            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!Network.wifi && !Network.wifiBlocked
                checked: Network.wifiOn
                onToggled: Network.setWifiEnabled(!Network.wifiOn)
            }
        }

        Hint {
            visible: !Network.wifi
            text: "No Wi-Fi adapter found."
        }
        Hint {
            visible: !!Network.wifi && Network.wifiBlocked
            text: "Turned off by a hardware switch or airplane mode."
        }
        Hint {
            visible: !!Network.wifi && !Network.wifiBlocked && !Network.wifiOn
            text: "Wi-Fi is off."
        }

        Flickable {
            id: list
            visible: !!Network.wifi && Network.wifiOn && Network.networks.length > 0
            width: parent.width
            height: Math.min(nets.implicitHeight, panel.maxListHeight)
            contentWidth: width
            contentHeight: nets.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: nets
                width: list.width
                spacing: panel.rowGap

                Repeater {
                    // keeps each row (and a half-typed password) when the list re-sorts
                    model: ScriptModel {
                        values: Network.networks
                    }

                    delegate: NetRow {}
                }
            }
        }

        Hint {
            visible: !!Network.wifi && Network.wifiOn && Network.networks.length === 0
            text: "Looking for networks…"
        }

        // ── Ethernet ────────────────────────────────────────────────────────
        ListRow {
            visible: !!Network.ethernet
            glyph: "󰈀"
            title: "Ethernet"
            subtitle: Network.wiredStatus(Network.ethernet)
            subtitleColor: Network.ethernet?.connected ? Theme.colors.blue : Theme.colors.subtext
            selected: Network.ethernet?.connected ?? false
            tint: Theme.colors.blue
            onClicked: Network.toggleWired()
        }

        Divider {}

        // ── VPN ─────────────────────────────────────────────────────────────
        Heading {
            text: "VPN"
            note: Network.vpnUp ? "On" : ""
        }

        Column {
            width: parent.width
            spacing: panel.rowGap

            Repeater {
                model: ScriptModel {
                    values: Network.vpns
                }

                delegate: ListRow {
                    id: vpnRow

                    required property var modelData
                    readonly property bool failed: !modelData.busy && !!modelData.error

                    glyph: modelData.up ? "󰦝" : "󰒙"
                    title: modelData.name
                    subtitle: Network.vpnStatus(modelData)
                    subtitleColor: failed ? Theme.colors.critical : modelData.up ? Theme.colors.green : Theme.colors.subtext
                    selected: modelData.up
                    tint: Theme.colors.green
                    onClicked: Network.toggleVpn(modelData)

                    // the app's own window: server picker, settings
                    ChipButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: vpnRow.modelData.kind === "app" && (vpnRow.modelData.provider.app?.length ?? 0) > 0
                        text: "󰏌"
                        label: "Open " + vpnRow.modelData.name
                        onClicked: Network.openVpnApp(vpnRow.modelData)
                    }

                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        // while it's working, show where it's going
                        checked: vpnRow.modelData.busy ? vpnRow.modelData.busy.startsWith("Connecting") : vpnRow.modelData.up
                        opacity: vpnRow.modelData.busy ? 0.6 : 1
                        onToggled: Network.toggleVpn(vpnRow.modelData)
                    }
                }
            }
        }

        Hint {
            visible: Network.vpns.length === 0
            text: "No VPNs yet. Import one in network settings, or add your VPN app to Config.network.vpnProviders."
        }

        // ── footer ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: Theme.rem(1.95 * Theme.ui.k)

            ChipButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.network.settingsApp.length > 0
                text: "󰒓  Network settings"
                onClicked: Network.openSettings()
            }
        }
    }

    // a Wi-Fi network, and its password field when it's asking for one
    component NetRow: Column {
        id: net

        required property var modelData
        readonly property bool asking: Network.asking === modelData.name
        readonly property string failure: Network.failures[modelData.name] ?? ""
        readonly property bool secured: !Network.isOpen(modelData.security)
        property bool reveal: false

        function submit() {
            if (!Network.passwordOk(net.modelData.security, pw.text))
                return;
            Network.joinWithPassword(net.modelData, pw.text);
            pw.text = "";
        }

        width: parent ? parent.width : 0
        spacing: Theme.rem(0.15)

        onAskingChanged: {
            if (asking) {
                pw.text = "";
                net.reveal = false;
                Qt.callLater(() => pw.forceActiveFocus());
            }
        }

        ListRow {
            id: line

            glyph: Network.wifiGlyph(net.modelData.signalStrength)
            title: net.modelData.name
            subtitle: Network.netStatus(net.modelData, net.failure)
            subtitleColor: net.modelData.connected ? Theme.colors.blue : net.failure ? Theme.colors.critical : Theme.colors.subtext
            selected: net.modelData.connected
            tint: Theme.colors.blue
            onClicked: button => {
                if (button === Qt.RightButton) {
                    if (net.modelData.known)
                        Network.forget(net.modelData);
                } else {
                    Network.join(net.modelData);
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: net.secured && !line.hovered
                text: "󰌾"
                color: Theme.colors.faint
                font.pixelSize: Theme.ui.small
            }
            ChipButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: line.hovered && net.modelData.connected
                text: "Disconnect"
                onClicked: net.modelData.disconnect()
            }
            ChipButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: line.hovered && net.modelData.known && !net.modelData.connected
                text: "Forget"
                onClicked: Network.forget(net.modelData)
            }
        }

        // ── the password, typed right here ──────────────────────────────────
        Item {
            visible: net.asking
            width: parent.width
            height: visible ? Theme.rem(2.35 * Theme.ui.k) : 0

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Theme.space.sm
                anchors.right: buttons.left
                anchors.rightMargin: Theme.space.sm
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.rem(2.05 * Theme.ui.k)
                radius: Theme.radius.md
                color: Theme.colors.surface
                border.width: 1
                border.color: pw.activeFocus ? Theme.alpha(Theme.colors.blue, 0.6) : Theme.colors.border

                TextInput {
                    id: pw

                    anchors.fill: parent
                    anchors.leftMargin: Theme.space.md
                    anchors.rightMargin: Theme.space.md
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: net.reveal ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: Theme.colors.text
                    selectionColor: Theme.alpha(Theme.colors.blue, 0.4)
                    selectedTextColor: Theme.colors.text
                    font.family: Theme.font.family
                    font.pixelSize: Theme.ui.text
                    clip: true
                    selectByMouse: true
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

                    Keys.onReturnPressed: net.submit()
                    Keys.onEnterPressed: net.submit()
                    // Esc closes the field first, the panel on the next press
                    Keys.onEscapePressed: Network.asking = ""
                }

                StyledText {
                    anchors.left: pw.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pw.text === ""
                    text: "Password for " + net.modelData.name
                    color: Theme.colors.faint
                    font.pixelSize: Theme.ui.small
                }
            }

            Row {
                id: buttons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.rem(0.1)

                ChipButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: net.reveal ? "󰈉" : "󰈈"
                    label: net.reveal ? "Hide password" : "Show password"
                    onClicked: net.reveal = !net.reveal
                }
                ChipButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Join"
                    checked: Network.passwordOk(net.modelData.security, pw.text)
                    tint: Theme.colors.blue
                    onClicked: net.submit()
                }
            }
        }
    }
}
