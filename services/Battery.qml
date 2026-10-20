pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.common

// Battery and power profiles (UPower + power-profiles-daemon, both over D-Bus).
Singleton {
    id: root

    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property bool available: !!dev && dev.isLaptopBattery && dev.isPresent
    readonly property real level: dev?.percentage ?? 0              // 0…1
    readonly property int percent: Math.round(level * 100)
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging || dev?.state === UPowerDeviceState.PendingCharge
    readonly property bool full: dev?.state === UPowerDeviceState.FullyCharged
    readonly property bool plugged: !UPower.onBattery
    readonly property real secondsLeft: charging ? (dev?.timeToFull ?? 0) : (dev?.timeToEmpty ?? 0)

    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile

    // plain, except amber when low and rose when very low (and not charging)
    readonly property color tint: root.tintFor(percent, charging || full || plugged)

    readonly property string glyph: root.glyphFor(percent, charging || full)
    readonly property string profileName: ["Power saver", "Balanced", "Performance"][profile] ?? "Balanced"

    // the three power profiles, as the panel shows them (a speedometer each)
    readonly property var profiles: [
        { id: PowerProfile.PowerSaver, name: "Power saver", glyph: "󰾆" },
        { id: PowerProfile.Balanced, name: "Balanced", glyph: "󰾅" },
        { id: PowerProfile.Performance, name: "Performance", glyph: "󰓅" }
    ].filter(p => p.id !== PowerProfile.Performance || root.hasPerformance)
    // power-profiles-daemon (or tuned-ppd) is around to switch them
    property bool profilesAvailable: false

    function tintFor(p, plugged) {
        if (plugged || p > 20)
            return Theme.colors.text;
        return p <= 10 ? Theme.colors.critical : Theme.colors.warn;
    }

    function setProfile(p) {
        PowerProfiles.profile = p;
    }

    function glyphFor(p, plugged) {
        if (plugged)
            return "󰂄";
        if (p <= 5)
            return "󰂃";
        // 10, 20 … 90, full
        const steps = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
        return steps[Math.max(0, Math.min(9, Math.ceil(p / 10) - 1))];
    }

    // "2h 05m", "45m" — "" while UPower is still estimating
    function duration(s) {
        if (!(s > 0))
            return "";
        const m = Math.round(s / 60);
        if (m < 60)
            return `${m}m`;
        return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, "0")}m`;
    }

    readonly property string status: {
        if (!available)
            return "";
        if (full)
            return "Fully charged";
        const t = duration(secondsLeft);
        if (charging)
            return t ? `${t} until full` : "Charging";
        return t ? `${t} left` : "On battery";
    }

    function cycleProfile() {
        const order = root.hasPerformance ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance] : [PowerProfile.PowerSaver, PowerProfile.Balanced];
        const i = order.indexOf(root.profile);
        PowerProfiles.profile = order[(i + 1) % order.length];
    }

    // is anything answering for power profiles on the system bus?
    Process {
        running: true
        command: ["sh", "-c", "busctl --system list --no-legend 2>/dev/null | grep -qE '^(net\\.hadess|org\\.freedesktop\\.UPower)\\.PowerProfiles '"]
        onExited: code => root.profilesAvailable = code === 0
    }
}
