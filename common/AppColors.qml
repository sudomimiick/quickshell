pragma Singleton

import QtQuick
import Quickshell

// Per-app accent colours. Off by default in the monochrome theme
// (Config.notifications.appColors): every app then gets the same neutral.
//
// Matching is case-insensitive against the app name, its desktop entry and its icon
// name, and a rule matches if any of those *contains* one of its words — so
// "discord", "com.discordapp.Discord" and "vesktop" all land on Discord blurple.
// Apps without a rule get a stable colour from your own palette (same app → same colour).
Singleton {
    id: root

    // Add or change apps here. First matching rule wins.
    readonly property var rules: [
        { match: ["discord", "vesktop", "webcord", "legcord", "equibop", "armcord"], color: "#5865f2" },
        { match: ["telegram", "ayugram", "64gram"], color: "#2aabee" },
        { match: ["whatsapp", "zapzap", "karere"], color: "#25d366" },
        { match: ["signal"], color: "#3a76f0" },
        { match: ["slack"], color: "#e01e5a" },
        { match: ["teams"], color: "#7b83eb" },
        { match: ["thunderbird", "betterbird"], color: "#0a84ff" },
        { match: ["spotify"], color: "#1ed760" },
        { match: ["vlc"], color: "#ff8800" },
        { match: ["firefox", "librewolf", "floorp"], color: "#ff7139" },
        { match: ["chromium", "google-chrome"], color: "#4285f4" },
        { match: ["brave"], color: "#fb542b" },
        { match: ["steam"], color: "#66c0f4" },
        { match: ["obsidian"], color: "#a882ff" },
        { match: ["visual-studio-code", "vscode", "code-oss", "vscodium"], color: "#22a7f2" },
        { match: ["proton"], color: "#6d4aff" },
        { match: ["networkmanager", "nm-applet"], color: "#60a5fa" },
        { match: ["blueman", "bluetooth", "bluez"], color: "#93c5fd" },
        { match: ["battery", "upower", "power-profiles"], color: "#f97316" },
        { match: ["screenshot", "spectacle"], color: "#b388ff" }
    ]

    // Unknown apps draw from these.
    readonly property var fallback: ["#8b5cf6", "#60a5fa", "#b388ff", "#75f1fa", "#22c55e", "#fdba74", "#dc91ff", "#93c5fd"]

    function forApp(appName, desktopEntry, appIcon) {
        if (!Config.notifications.appColors)
            return Theme.colors.subtext;
        const keys = [appName, desktopEntry, appIcon].filter(n => !!n).map(n => String(n).toLowerCase());
        for (const rule of rules)
            for (const word of rule.match)
                for (const key of keys)
                    if (key.includes(word))
                        return rule.color;
        if (keys.length === 0)
            return Theme.colors.accent;
        return fallback[hash(keys[0]) % fallback.length];
    }

    function hash(s) {
        let h = 0;
        for (let i = 0; i < s.length; i++)
            h = (h * 31 + s.charCodeAt(i)) | 0;
        return Math.abs(h);
    }
}
