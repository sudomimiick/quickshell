pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.common

// Wi-Fi and Ethernet from Quickshell's NetworkManager backend, plus VPNs.
//
// NetworkManager doesn't show VPNs through that backend, so `nmcli monitor`
// says when anything changes and one `nmcli` call re-reads every connection
// profile (VPN and WireGuard ones become switches in the panel) and every
// interface (so VPN apps that bring their own, like proton0 or wg0-mullvad, are
// seen too).
Singleton {
    id: root

    // ── Wi-Fi and Ethernet ──────────────────────────────────────────────────
    readonly property var devices: Networking.devices.values
    readonly property var wifi: root.firstDevice(devices, DeviceType.Wifi, false)
    readonly property var wired: root.firstDevice(devices, DeviceType.Wired, true)      // a cable that's connected
    readonly property var ethernet: root.firstDevice(devices, DeviceType.Wired, false)  // any wired port
    readonly property var wifiNet: root.connectedNetwork(wifi)
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool wifiBlocked: !Networking.wifiHardwareEnabled

    readonly property string kind: wired ? "wired" : wifiNet ? "wifi" : "offline"
    readonly property string ssid: wifiNet?.name ?? ""
    readonly property real strength: wifiNet?.signalStrength ?? 0

    // what the panel lists: connected first, then saved, then the rest by signal
    readonly property var networks: root.sortNetworks(root.toArray(wifi?.networks?.values))

    // the network whose password the panel is asking for ("" = none)
    property string asking: ""
    // name → why the last try failed ("Wrong password", …)
    property var failures: ({})

    readonly property string glyph: {
        if (kind === "wired")
            return "󰈀";
        if (kind === "offline")
            return wifiOn ? "󰤯" : "󰖪";
        return root.wifiGlyph(strength);
    }

    readonly property string label: kind === "wired" ? "Ethernet" : kind === "wifi" ? ssid : wifiOn ? "Not connected" : "Wi-Fi off"

    // ── VPN ─────────────────────────────────────────────────────────────────
    // every NetworkManager profile: [{ name, uuid, type, active, state, device }]
    property var connections: []
    // every interface: [{ device, type, state }]
    property var interfaces: []
    // key → "Connecting…" / "Disconnecting…" while a switch is working
    property var busy: ({})
    // key → the last error a VPN command printed
    property var errors: ({})

    // what the panel shows: the VPN apps from Config first, then NetworkManager's own
    readonly property var vpns: root.vpnItems(Config.network.vpnProviders, connections, interfaces, busy, errors)
    readonly property var vpnOn: vpns.filter(v => v.up)
    readonly property bool vpnUp: vpnOn.length > 0
    readonly property bool vpnBusy: Object.keys(busy).length > 0
    readonly property string vpnName: vpnOn.length ? vpnOn[0].name : ""

    // ── where the VPN comes out, for the bar ("󰤨 │ India", "󰤨 │ NL") ──────────
    // From the server in the connection's name ("ProtonVPN NL#123"); for VPNs that
    // don't say, from Config.network.vpnCountryLookup if you've set one.
    readonly property string vpnDetail: vpnOn.length ? (vpnOn[0].detail || vpnOn[0].name) : ""
    readonly property string nameCountry: root.countryFromName(vpnDetail)
    property string lookedUpCountry: ""
    readonly property string vpnCountry: nameCountry || lookedUpCountry
    readonly property bool vpnShown: vpnUp || vpnBusy
    readonly property string vpnLabel: {
        if (vpnUp)
            return vpnCountry ? Countries.label(vpnCountry, Config.network.countryNameMax) : "VPN";
        return vpnBusy ? "…" : "";
    }

    onVpnDetailChanged: {
        root.lookedUpCountry = "";
        if (root.vpnUp && !root.nameCountry && Config.network.vpnCountryLookup.length)
            lookupDelay.restart();
    }

    // "ProtonVPN NL#123" → NL, "CH-NL#1" (Secure Core, out in the Netherlands) → NL,
    // "US-NY#12" → US, "nl-ams-wg-001" (Mullvad) → NL
    function countryFromName(text) {
        const s = String(text ?? "");
        let m = /\b([A-Za-z]{2})(?:-([A-Za-z]{2}))?(?:-FREE)?#\d+/i.exec(s);
        if (m) {
            const a = m[1].toUpperCase();
            const b = (m[2] ?? "").toUpperCase();
            return b && ["CH", "IS", "SE"].includes(a) ? b : a;
        }
        m = /\b([a-z]{2})-[a-z]{3}-(?:wg|ovpn)-\d+/i.exec(s);
        return m ? m[1].toUpperCase() : "";
    }

    // ── Wi-Fi helpers ───────────────────────────────────────────────────────
    function wifiGlyph(s) {
        const steps = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"];
        return steps[Math.max(0, Math.min(4, Math.round(s * 4)))];
    }

    function toArray(list) {
        const out = [];
        for (let i = 0; i < (list?.length ?? 0); i++)
            out.push(list[i]);
        return out;
    }

    function firstDevice(list, type, mustBeConnected) {
        for (let i = 0; i < (list?.length ?? 0); i++)
            if (list[i].type === type && (!mustBeConnected || list[i].connected))
                return list[i];
        return null;
    }

    function connectedNetwork(dev) {
        const nets = dev?.networks?.values ?? [];
        for (let i = 0; i < nets.length; i++)
            if (nets[i].connected)
                return nets[i];
        return null;
    }

    // by signal *bars*, not the exact number, so rows don't keep swapping places
    function sortNetworks(list) {
        const rank = n => n.connected ? 0 : n.stateChanging ? 1 : n.known ? 2 : 3;
        const bars = n => Math.round((n.signalStrength ?? 0) * 4);
        return list.filter(n => !!n.name).sort((a, b) => rank(a) - rank(b) || bars(b) - bars(a) || a.name.localeCompare(b.name));
    }

    function isOpen(sec) {
        return sec === WifiSecurityType.Open || sec === WifiSecurityType.Owe;
    }

    // a plain password is all it needs
    function isPsk(sec) {
        return sec === WifiSecurityType.WpaPsk || sec === WifiSecurityType.Wpa2Psk || sec === WifiSecurityType.Sae;
    }

    // a username, certificates… — that's a job for the settings app
    function isEnterprise(sec) {
        return sec === WifiSecurityType.Wpa2Eap || sec === WifiSecurityType.WpaEap || sec === WifiSecurityType.Wpa3SuiteB192 || sec === WifiSecurityType.Leap || sec === WifiSecurityType.DynamicWep || sec === WifiSecurityType.StaticWep;
    }

    // what a click on a network should do
    function joinAction(n) {
        if (n.connected || n.stateChanging)
            return "none";
        if (n.known || root.isOpen(n.security) || n.security === WifiSecurityType.Unknown)
            return "connect";
        if (root.isPsk(n.security))
            return "password";
        return "settings";
    }

    // WPA wants 8–63 characters; WPA3 (SAE) takes any length
    function passwordOk(sec, text) {
        const n = String(text ?? "").length;
        return sec === WifiSecurityType.Sae ? n > 0 : n >= 8 && n <= 63;
    }

    function netStatus(n, failure) {
        if (n.state === ConnectionState.Connecting)
            return "Connecting…";
        if (n.state === ConnectionState.Disconnecting)
            return "Disconnecting…";
        if (n.connected)
            return "Connected";
        if (failure)
            return failure;
        const kind = root.isOpen(n.security) ? "Open" : root.isEnterprise(n.security) ? "Work or school login" : "Secured";
        return n.known ? `Saved · ${kind}` : kind;
    }

    function failText(reason) {
        switch (reason) {
        case ConnectionFailReason.NoSecrets:
            return "Wrong password";
        case ConnectionFailReason.WifiAuthTimeout:
            return "Timed out — try again";
        case ConnectionFailReason.WifiNetworkLost:
            return "Out of range";
        }
        return "Couldn't connect";
    }

    function wiredStatus(dev) {
        if (!dev)
            return "";
        if (dev.state === ConnectionState.Connecting)
            return "Connecting…";
        if (dev.connected)
            return dev.linkSpeed > 0 ? `Connected · ${dev.linkSpeed >= 1000 ? dev.linkSpeed / 1000 + " Gb/s" : dev.linkSpeed + " Mb/s"}` : "Connected";
        return dev.hasLink ? "Not connected" : "Cable unplugged";
    }

    // ── Wi-Fi actions ───────────────────────────────────────────────────────
    function setWifiEnabled(value) {
        Networking.wifiEnabled = value;
        if (!value)
            root.asking = "";
    }

    function setScanning(value) {
        if (root.wifi)
            root.wifi.scannerEnabled = value;
    }

    function join(n) {
        root.clearFailure(n.name);
        const action = root.joinAction(n);
        if (action === "connect") {
            root.asking = "";
            n.connect();
        } else if (action === "password") {
            root.asking = n.name;
        } else if (action === "settings") {
            root.openSettings();
        }
    }

    function joinWithPassword(n, psk) {
        root.clearFailure(n.name);
        root.asking = "";
        n.connectWithPsk(psk);
    }

    function forget(n) {
        root.clearFailure(n.name);
        if (root.asking === n.name)
            root.asking = "";
        n.forget();
    }

    function noteFailure(n, reason) {
        const f = Object.assign({}, root.failures);
        f[n.name] = root.failText(reason);
        root.failures = f;
        // a saved password that stopped working: ask for the new one
        if (reason === ConnectionFailReason.NoSecrets && root.isPsk(n.security))
            root.asking = n.name;
    }

    function clearFailure(name) {
        if (!(name in root.failures))
            return;
        const f = Object.assign({}, root.failures);
        delete f[name];
        root.failures = f;
    }

    function toggleWired() {
        const dev = root.ethernet;
        if (!dev)
            return;
        if (dev.connected)
            dev.disconnect();
        else
            dev.network?.connect();
    }

    function openSettings() {
        Drawers.close();
        if (Config.network.settingsApp.length)
            Quickshell.execDetached(Config.network.settingsApp);
    }

    // ── VPN helpers ─────────────────────────────────────────────────────────
    function matches(p, text) {
        return !!p.match && new RegExp(p.match, "i").test(text);
    }

    function providerFor(c) {
        for (const p of Config.network.vpnProviders)
            if (root.matches(p, `${c.name} ${c.device}`))
                return p;
        return null;
    }

    function isVpnType(type) {
        return type === "vpn" || type === "wireguard";
    }

    function vpnItems(providers, conns, ifaces, busy, errors) {
        const out = [];
        for (const p of providers) {
            const key = "app:" + p.name;
            const conn = conns.find(c => c.active && root.matches(p, `${c.name} ${c.device}`));
            const iface = conn ? null : ifaces.find(d => d.state.startsWith("connected") && root.matches(p, d.device));
            out.push({
                key: key,
                kind: "app",
                name: p.name,
                provider: p,
                up: !!(conn || iface),
                detail: conn ? conn.name : iface ? iface.device : "",
                busy: busy[key] ?? "",
                error: errors[key] ?? ""
            });
        }
        const profiles = conns.filter(c => root.isVpnType(c.type) && !providers.some(p => root.matches(p, `${c.name} ${c.device}`)));
        profiles.sort((a, b) => a.name.localeCompare(b.name));
        for (const c of profiles) {
            const key = "nm:" + c.uuid;
            const starting = c.active && c.state === "activating";
            out.push({
                key: key,
                kind: "profile",
                name: c.name,
                uuid: c.uuid,
                type: c.type,
                up: c.active && !starting,
                detail: "",
                busy: busy[key] ?? (starting ? "Connecting…" : ""),
                error: errors[key] ?? ""
            });
        }
        return out;
    }

    function vpnStatus(v) {
        if (v.busy)
            return v.busy;
        if (v.error)
            return v.error;
        if (v.up)
            return v.detail && v.detail !== v.name ? `Connected · ${v.detail}` : "Connected";
        if (v.kind === "app")
            return "Off";
        return v.type === "wireguard" ? "WireGuard" : "VPN";
    }

    // the command a switch runs to turn this VPN on or off
    function vpnCommand(v, turnOn) {
        if (v.kind === "profile")
            return ["nmcli", "connection", turnOn ? "up" : "down", "uuid", v.uuid];
        return (turnOn ? v.provider.connect : v.provider.disconnect) ?? [];
    }

    // the last useful line of what a failed command said
    function errorLine(text, cmd) {
        const lines = String(text ?? "").split("\n").map(l => l.replace(/^Error:\s*/i, "").trim()).filter(l => !!l);
        const line = lines.length ? lines[lines.length - 1] : `${cmd[0]} failed`;
        return line.length > 90 ? line.slice(0, 89) + "…" : line;
    }

    // ── VPN actions ─────────────────────────────────────────────────────────
    function toggleVpn(v) {
        if (root.busy[v.key])
            return;
        const cmd = root.vpnCommand(v, !v.up);
        if (!cmd.length)
            return;
        root.setEntry("busy", v.key, v.up ? "Disconnecting…" : "Connecting…");
        root.setEntry("errors", v.key, null);
        job.createObject(root, {
            key: v.key,
            command: cmd
        });
    }

    function openVpnApp(v) {
        if (v.provider?.app?.length) {
            Drawers.close();
            Quickshell.execDetached(v.provider.app);
        }
    }

    function jobDone(key, code, text, cmd) {
        root.setEntry("busy", key, null);
        if (code !== 0)
            root.setEntry("errors", key, code === -1 ? `${cmd[0]} isn't installed` : root.errorLine(text, cmd));
        root.refresh();
    }

    // busy/errors are replaced, not edited, so bindings notice the change
    function setEntry(which, key, value) {
        const m = Object.assign({}, root[which]);
        if (value === null)
            delete m[key];
        else
            m[key] = value;
        root[which] = m;
    }

    Timer {
        id: lookupDelay
        interval: 1500 // let the routes settle first
        onTriggered: {
            if (root.vpnUp && !lookup.running)
                lookup.running = true;
        }
    }

    Process {
        id: lookup
        command: Config.network.vpnCountryLookup
        stdout: StdioCollector {
            id: looked
            onStreamFinished: {
                const code = looked.text.trim().toUpperCase();
                root.lookedUpCountry = /^[A-Z]{2}$/.test(code) ? code : "";
            }
        }
    }

    Component {
        id: job

        Process {
            id: proc

            property string key: ""
            property bool done: false

            running: true
            stdout: StdioCollector {
                id: out
            }
            stderr: StdioCollector {
                id: err
            }
            onExited: code => {
                proc.done = true;
                root.jobDone(proc.key, code, err.text || out.text, proc.command);
                proc.destroy();
            }
            // the program isn't there: no "exited", just stopped
            onRunningChanged: {
                if (!proc.running && !proc.done) {
                    proc.done = true;
                    root.jobDone(proc.key, -1, "", proc.command);
                    proc.destroy();
                }
            }
        }
    }

    // ── reading NetworkManager ──────────────────────────────────────────────

    // `nmcli -t` output: fields split on ':', with '\:' and '\\' escaped inside values
    function parseTerse(text) {
        const rows = [];
        for (const line of String(text ?? "").split("\n")) {
            if (!line)
                continue;
            const fields = [];
            let cur = "";
            for (let i = 0; i < line.length; i++) {
                const c = line[i];
                if (c === "\\" && i + 1 < line.length) {
                    cur += line[++i];
                } else if (c === ":") {
                    fields.push(cur);
                    cur = "";
                } else {
                    cur += c;
                }
            }
            fields.push(cur);
            rows.push(fields);
        }
        return rows;
    }

    // one read: the profiles, a marker line, then the interfaces
    function readAll(text) {
        const parts = String(text ?? "").split(/^@@interfaces@@$/m);
        root.connections = root.parseTerse(parts[0]).filter(f => f.length >= 6 && f[2] !== "loopback").map(f => ({
                    name: f[0],
                    uuid: f[1],
                    type: f[2],
                    active: f[3] === "yes",
                    state: f[4],
                    device: f[5]
                }));
        root.interfaces = root.parseTerse(parts[1] ?? "").filter(f => f.length >= 3 && f[1] !== "loopback").map(f => ({
                    device: f[0],
                    type: f[1],
                    state: f[2]
                }));
    }

    function refresh() {
        if (!lister.running)
            lister.running = true;
        else
            again.restart();
    }

    // the panel scans for networks while it's open, and forgets a half-typed password when it closes
    Connections {
        target: Drawers
        function onCurrentChanged() {
            const open = Drawers.current === "network";
            root.setScanning(open && Config.network.scan && root.wifiOn);
            if (open)
                root.refresh();
            else
                root.asking = "";
        }
    }

    // a failed connection says why on the network itself
    Variants {
        model: root.toArray(root.wifi?.networks?.values)

        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) {
                root.noteFailure(modelData, reason);
            }
        }
    }

    Process {
        id: lister
        running: true
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE,ACTIVE,STATE,DEVICE connection show; echo @@interfaces@@; nmcli -t -f DEVICE,TYPE,STATE device status"]
        stdout: StdioCollector {
            id: listed
            onStreamFinished: root.readAll(listed.text)
        }
    }

    // anything changes → one re-read, a moment later (changes come in bursts)
    Process {
        id: monitor
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: settle.restart()
        }
        onExited: revive.start()
    }

    Timer {
        id: settle
        interval: 350
        onTriggered: root.refresh()
    }

    Timer {
        id: again
        interval: 300
        onTriggered: root.refresh()
    }

    // NetworkManager restarted (or nmcli was missing): try again later
    Timer {
        id: revive
        interval: 10000
        onTriggered: monitor.running = true
    }
}
