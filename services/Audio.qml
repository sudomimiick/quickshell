pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.common

// Speakers and microphones, straight from PipeWire (no pactl, no polling).
// The pop-up appears whatever changes the volume (wpctl keys, an app, this shell).
//
//   qs ipc call audio up | down | mute | micMute | set 40
//   hl.bind("XF86AudioRaiseVolume", hl.dsp.global("quickshell:volumeUp"), { locked = true, repeating = true })
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool ready: !!sink?.audio
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false

    readonly property string sinkName: root.nameOf(sink)
    readonly property bool headphones: /head(phone|set)|buds|airpods|bluez/i.test((sink?.name ?? "") + " " + (sink?.description ?? ""))

    // every real output / input (not app streams)
    readonly property var sinks: root.devices(true)
    readonly property var sources: root.devices(false)

    function devices(wantSinks) {
        const all = Pipewire.nodes.values;
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const n = all[i];
            if (n.audio && !n.isStream && n.isSink === wantSinks)
                out.push(n);
        }
        return out;
    }

    // "Speakers", "WH-1000XM4", … (nickname is the short one PipeWire shows in its UI)
    function nameOf(n) {
        return n ? (n.nickname || n.description || n.name) : "";
    }

    // a glyph for an output in the list: headphones, a screen's speakers, or speakers
    function deviceGlyph(n) {
        const s = `${n?.name ?? ""} ${n?.description ?? ""} ${n?.nickname ?? ""}`.toLowerCase();
        if (/bluez|head|earbud|buds|airpod/.test(s))
            return "󰋋";
        if (/hdmi|displayport/.test(s))
            return "󰍹";
        return "󰓃";
    }

    function glyph() {
        if (root.muted)
            return "󰝟";
        if (root.headphones)
            return "󰋋";
        return root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾";
    }

    function setVolume(v) {
        if (!root.ready)
            return;
        root.sink.audio.muted = false;
        root.sink.audio.volume = Math.max(0, Math.min(Config.audio.max, Math.round(v * 100) / 100));
    }

    function step(notches) {
        root.setVolume(root.volume + notches * Config.audio.step);
    }

    function toggleMute() {
        if (root.ready)
            root.sink.audio.muted = !root.sink.audio.muted;
    }

    function setMicVolume(v) {
        if (!root.source?.audio)
            return;
        root.source.audio.muted = false;
        root.source.audio.volume = Math.max(0, Math.min(1, Math.round(v * 100) / 100));
    }

    function toggleMicMute() {
        if (root.source?.audio)
            root.source.audio.muted = !root.source.audio.muted;
    }

    function useSink(n) {
        Pipewire.preferredDefaultAudioSink = n;
    }

    // keeps volume/mute live on the default devices
    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => !!n)
    }

    GlobalShortcut {
        name: "volumeUp"
        description: "Louder"
        onPressed: root.step(Config.audio.keyStep / Config.audio.step)
    }

    GlobalShortcut {
        name: "volumeDown"
        description: "Quieter"
        onPressed: root.step(-Config.audio.keyStep / Config.audio.step)
    }

    GlobalShortcut {
        name: "volumeMute"
        description: "Mute or unmute the speakers"
        onPressed: root.toggleMute()
    }

    GlobalShortcut {
        name: "micMute"
        description: "Mute or unmute the microphone"
        onPressed: root.toggleMicMute()
    }

    IpcHandler {
        target: "audio"

        function up(): void {
            root.step(Config.audio.keyStep / Config.audio.step);
        }
        function down(): void {
            root.step(-Config.audio.keyStep / Config.audio.step);
        }
        function mute(): void {
            root.toggleMute();
        }
        function micMute(): void {
            root.toggleMicMute();
        }
        function set(percent: int): void {
            root.setVolume(percent / 100);
        }
    }
}
