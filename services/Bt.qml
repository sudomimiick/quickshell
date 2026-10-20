pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth (BlueZ over D-Bus): the adapter switch, your devices, pairing.
Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool available: !!adapter
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool scanning: adapter?.discovering ?? false

    readonly property var all: root.toArray(Bluetooth.devices.values)
    readonly property var connected: all.filter(d => d.connected)
    readonly property var first: connected.length ? connected[0] : null
    readonly property string label: first ? root.nameOf(first) + (first.batteryAvailable ? ` · ${Math.round(first.battery * 100)}%` : "") : ""

    // connected first, then the ones you've paired, then (while scanning) new ones
    readonly property var list: root.sorted(all, scanning)

    function sorted(devices, includeNew) {
        const rank = d => d.connected ? 0 : d.paired ? 1 : 2;
        return devices.filter(d => (d.paired || d.connected || includeNew) && root.nameOf(d) !== "")
                      .sort((a, b) => rank(a) - rank(b) || root.nameOf(a).localeCompare(root.nameOf(b)));
    }

    function toArray(list) {
        const out = [];
        for (let i = 0; i < (list?.length ?? 0); i++)
            out.push(list[i]);
        return out;
    }

    function nameOf(d) {
        return d ? (d.name || d.deviceName || "") : "";
    }

    // a glyph from the icon name BlueZ gives the device ("audio-headset", "input-mouse", …)
    function glyphFor(d) {
        const i = String(d?.icon ?? "");
        if (/headset/.test(i))
            return "󰋎";
        if (/headphone/.test(i))
            return "󰋋";
        if (/audio|speaker/.test(i))
            return "󰓃";
        if (/mouse/.test(i))
            return "󰍽";
        if (/keyboard/.test(i))
            return "󰌌";
        if (/gaming|joystick/.test(i))
            return "󰊗";
        if (/tablet/.test(i))
            return "󰓶";
        if (/phone/.test(i))
            return "󰄜";
        if (/computer|laptop/.test(i))
            return "󰌢";
        if (/watch/.test(i))
            return "󰖉";
        if (/display|video/.test(i))
            return "󰔂";
        return "󰂯";
    }

    function status(d) {
        if (d.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (d.pairing)
            return "Pairing…";
        if (d.connected)
            return d.batteryAvailable ? `Connected · ${Math.round(d.battery * 100)}%` : "Connected";
        return d.paired ? "Paired" : "New";
    }

    function setEnabled(value) {
        if (root.adapter)
            root.adapter.enabled = value;
    }

    function setScanning(value) {
        if (root.adapter && root.enabled)
            root.adapter.discovering = value;
    }

    // click on a device: connect / disconnect, or pair (and trust) a new one
    function activate(d) {
        if (d.connected) {
            d.disconnect();
        } else if (d.paired) {
            d.connect();
        } else {
            d.trusted = true;
            d.pair();
        }
    }
}
