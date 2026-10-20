pragma Singleton

import QtQuick
import Quickshell

// Behaviour knobs for the whole shell. Sizes and colours live in Theme.qml.
Singleton {
    readonly property QtObject notifications: QtObject {
        readonly property real width: 24               // card width, in rem
        readonly property int timeout: 6000            // ms, normal urgency
        readonly property int timeoutLow: 3500         // ms, low urgency
        readonly property bool criticalSticky: true    // critical ones stay until you click them
        readonly property bool respectAppTimeout: true // use the app's own timeout when it sends one
        readonly property int maxPopups: 4             // older popups slide into history
        readonly property int maxHistory: 60           // kept for the notification centre
        readonly property bool showHints: true         // "L close · R open" while hovering
        readonly property bool appColors: false        // tint cards with each app's brand colour (off = monochrome)
    }

    readonly property QtObject screenshot: QtObject {
        readonly property string capture: "native"        // "native" (Quickshell screencopy) or "grim" (fallback)
        readonly property string directory: ""            // "" = <your Pictures folder>/Screenshots; "~/…" works
        readonly property string prefix: "Screenshot_"
        readonly property string timeFormat: "yyyyMMdd_HHmmss"
        // What Enter / click-a-window / screen / window shots do. Default: copy only —
        // the notification's Save button keeps it as a file if you want it.
        readonly property bool copy: true                 // copy to clipboard
        readonly property bool save: false                // also save a file every time
        readonly property bool confirmRegion: true        // Spectacle-style: adjust, then Enter. false = capture on release (slurp-style)
        readonly property bool clickWindowCaptures: true  // click a window = capture it (Shift+click just selects it)
        readonly property bool rememberRegion: false      // start from the last region
        readonly property bool includeCursor: false
        readonly property bool flash: true
        readonly property bool notify: true               // notification with Open / Save (or Show in folder) / Annotate / Delete
        readonly property int keepCopiesDays: 2           // copy-only shots are temp files; cleared after this many days
    }

    readonly property QtObject launcher: QtObject {
        readonly property real width: 34                // box width, in rem
        readonly property int lines: 8                  // rows on screen (fuzzel: lines)
        readonly property bool showActions: true        // desktop actions ("New Private Window") turn up when you search for them
        readonly property bool calculator: true         // "2^10", "sqrt(2)*3" → answer on top, Enter copies; "=" forces it
        readonly property bool runCommands: true        // "> cmd" runs a shell command; Shift+Enter runs whatever you typed
        readonly property bool importFuzzelHistory: true // first start: seed launch counts from ~/.cache/fuzzel
        readonly property bool preloadIcons: true       // render every app icon once in the background after login
        // Keep the launcher's surface mapped as an invisible, click-through 1×1 pixel while
        // closed, so opening is one resize + one frame. false = create the window on every open.
        readonly property bool persistent: true
        readonly property var terminal: []              // [] = auto ($TERMINAL, then kitty/foot/…). e.g. ["kitty"], ["alacritty", "-e"]
        readonly property var launchPrefix: []          // e.g. ["uwsm", "app", "--"] or ["app2unit", "--"]
        readonly property var hidden: []                // desktop ids to never show, e.g. ["avahi-discover", "qv4l2"]
    }

    readonly property QtObject bar: QtObject {
        readonly property real height: 2.75                 // rem
        readonly property real scale: 1.0                   // icons and text on the bar and in its panels (1.1 = 10% bigger)
        readonly property bool corners: false               // round the screen's top corners under the bar
        readonly property real cornerRadius: 1.2            // rem
        readonly property bool ears: true                   // the curves where a panel meets the bar (false = square)
        readonly property bool batteryPercent: true         // the number next to the battery
        readonly property int workspaces: 5                 // always shown, like waybar's persistent-workspaces
        readonly property string timeFormat: "hh:mm AP"     // Qt date format: "HH:mm" for 24-hour
        readonly property string dateFormat: "ddd dd MMM"
        readonly property string windowFallback: "Let's get to work"
        readonly property bool tray: true                   // app tray icons (Discord, Steam, …); hidden when empty
        readonly property bool hoverSwitch: true            // with a panel open, hovering another icon swaps to its panel
    }

    readonly property QtObject audio: QtObject {
        readonly property real step: 0.02                   // scroll on the volume icon: 2% per notch
        readonly property real keyStep: 0.05                // the volume keys, if you bind them to quickshell:volumeUp/Down
        readonly property real max: 1.0                     // 1.5 lets you boost past 100%
    }

    readonly property QtObject brightness: QtObject {
        readonly property string device: ""                 // "" = the first in /sys/class/backlight
        readonly property real step: 0.05                   // scroll on the brightness icon
        readonly property real keyStep: 0.05                // quickshell:brightnessUp/Down
    }

    // Hyprland's own monitor scale, from the slider in the controls panel.
    readonly property QtObject display: QtObject {
        readonly property real minScale: 0.75
        readonly property real maxScale: 2.5
        readonly property int minWidth: 1000                // never scale so far the screen is narrower than this (logical px)
        // Keep your choice after a restart (it's re-applied when the shell starts and
        // whenever Hyprland reloads its config). "Reset" in the panel goes back to your config.
        readonly property bool rememberScale: true
    }

    // The little notch that shows volume or brightness when they change.
    readonly property QtObject osd: QtObject {
        readonly property bool enabled: true
        readonly property int timeout: 1400                 // ms on screen after the last change
        readonly property bool showValue: false             // print the number too
    }

    readonly property QtObject network: QtObject {
        readonly property var settingsApp: ["nm-connection-editor"]   // "Network settings", and Wi-Fi the panel can't join (work/uni logins)
        readonly property bool scan: true                   // look for Wi-Fi networks while the panel is open
        readonly property int maxNetworks: 5                // rows in the Wi-Fi list before it scrolls
        // With a VPN up the bar shows "󰤨 │ India": the country's name when it's this
        // short, its code otherwise ("NL" for the Netherlands).
        readonly property int countryNameMax: 7
        // Most VPNs name their connection after the server ("ProtonVPN NL#12"), which is
        // where the country comes from. For ones that don't, a command that prints a
        // two-letter country code, e.g. ["curl", "-sf", "--max-time", "5", "https://ipinfo.io/country"]
        // (that asks a web service where your traffic appears to come from). [] = never ask.
        readonly property var vpnCountryLookup: []

        // NetworkManager VPN and WireGuard profiles show up in the panel on their own.
        // VPN apps with their own command line go here:
        //   match       regex against the NetworkManager connection (or interface) the app
        //               creates — that's how the panel knows it's up
        //   connect / disconnect   what the switch runs
        //   app         optional: a button that opens the app (server picker, settings)
        // Their NetworkManager profiles are then shown as this one switch, not one per server.
        readonly property var vpnProviders: [
            {
                name: "Proton VPN",
                match: "proton",
                connect: ["protonvpn", "connect"],          // the official CLI (proton-vpn-cli); add "--country", "CH" for a country
                disconnect: ["protonvpn", "disconnect"],
                app: ["protonvpn-app"]
            }
            // { name: "Mullvad", match: "mullvad", connect: ["mullvad", "connect"], disconnect: ["mullvad", "disconnect"] },
            // { name: "Tailscale", match: "tailscale", connect: ["tailscale", "up"], disconnect: ["tailscale", "down"] },
        ]
    }

    readonly property QtObject session: QtObject {
        // The little one on top of the power menu. "" = the bundled chibi, in the shell's
        // soft colours ("~/.config/quickshell/assets/chibi-mono.svg" is the grey one).
        // Any image or GIF works: "~/Pictures/spin.gif". Set spin to "none" for a GIF that already moves.
        readonly property string avatar: ""
        readonly property string spin: "twirl"              // "twirl" (spins on the spot) · "turn" (rotates) · "bob" · "none"
        readonly property real width: 0.18                  // share of the screen width (never more than 1/5)
        readonly property var lock: ["sh", "-c", "pidof hyprlock || hyprlock || loginctl lock-session"]
        readonly property var suspend: ["systemctl", "suspend"]
        readonly property var reboot: ["systemctl", "reboot"]
        readonly property var poweroff: ["systemctl", "poweroff"]
        readonly property var hibernate: []                 // e.g. ["systemctl", "hibernate"] to add a Hibernate button
    }

    // Wallpapers: SUPER+SHIFT+W opens the picker (← → to choose, Enter to set).
    readonly property QtObject wallpaper: QtObject {
        readonly property string directory: "~/Pictures/Wallpapers"   // looked through 3 folders deep
        // The shell draws the wallpaper itself (that's what makes the transition
        // possible). false = leave it to hyprpaper/swww/… and only run onChange.
        readonly property bool draw: true
        readonly property string transition: "split"   // "split" (the screen opens in the middle) · "fade" · "none"
        readonly property int duration: 750             // ms
        // Run after every change; "%f" becomes the picture. For colour schemes or your
        // lock screen, e.g. ["matugen", "image", "%f"] or ["swww", "img", "%f"] with draw: false.
        readonly property var onChange: []
        readonly property int thumbnailSize: 512         // px; cached in ~/.cache/quickshell/…/wallpapers
    }

    readonly property QtObject scaling: QtObject {
        readonly property string mode: "auto"          // "auto" = smart scaling, "fixed" = Hyprland's scale only
        readonly property real userScale: 1.0          // global multiplier on top of everything
        readonly property var overrides: ({})          // per monitor, e.g. ({ "HDMI-A-1": 1.1 })
    }
}
