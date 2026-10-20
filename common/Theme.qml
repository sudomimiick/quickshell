pragma Singleton

import QtQuick
import Quickshell

// Sizes, colours, fonts and motion for the whole shell.
// Rule: widgets never use raw pixel numbers — only Theme.rem(…) or a token below.
Singleton {
    id: root

    // ── size ─────────────────────────────────────────────────────────────────

    // 1rem in design px (a 13 px font). Every size in the shell is a multiple of it.
    readonly property real basePx: 13
    // Scaling.factor is the smart per-screen correction (see Scaling.qml).
    readonly property real remPx: basePx * Scaling.factor

    // rem(1.5) → 1.5rem, rounded to whole pixels so edges stay crisp.
    function rem(n) {
        return Math.round(n * remPx);
    }

    // Same colour, different opacity: Theme.alpha(Theme.colors.text, 0.2)
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property QtObject space: QtObject {
        readonly property int xs: root.rem(0.25)
        readonly property int sm: root.rem(0.5)
        readonly property int md: root.rem(0.75)
        readonly property int lg: root.rem(1)
        readonly property int xl: root.rem(1.5)
    }

    readonly property QtObject radius: QtObject {
        readonly property int sm: root.rem(0.4)
        readonly property int md: root.rem(0.65)  // ~8px
        readonly property int lg: root.rem(1.1)
    }

    readonly property QtObject font: QtObject {
        readonly property string family: "JetBrainsMono Nerd Font Propo"
        readonly property int xs: root.rem(0.8)
        readonly property int sm: root.rem(0.9)
        readonly property int md: root.rem(1)
        readonly property int lg: root.rem(1.15)
        readonly property int xl: root.rem(1.4)
    }

    readonly property QtObject anim: QtObject {
        readonly property int fast: 150
        readonly property int normal: 260
        readonly property int slow: 420
        // Material 3 motion curves, for Easing.BezierSpline:
        // things arriving (decelerate hard, settle softly) …
        readonly property var enter: [0.05, 0.7, 0.1, 1, 1, 1]
        // … things leaving (accelerate away) …
        readonly property var exit: [0.3, 0, 0.8, 0.15, 1, 1]
        // … and things changing shape in place.
        readonly property var move: [0.2, 0, 0, 1, 1, 1]
    }

    // Sizes for the bar and everything that hangs from it (panels, power menu).
    // One knob makes them all bigger or smaller: Config.bar.scale.
    readonly property QtObject ui: QtObject {
        readonly property real k: Config.bar.scale
        readonly property int icon: root.rem(1.15 * k)    // every glyph on the bar, one size
        readonly property int cell: root.rem(1.7 * k)     // …each centred in a square this big
        readonly property int logo: root.rem(1.35 * k)    // the launcher button
        readonly property int text: root.rem(0.92 * k)    // bar text, panel body text
        readonly property int small: root.rem(0.82 * k)   // secondary lines
        readonly property int tiny: root.rem(0.74 * k)    // keycaps, counts, hints
        readonly property int title: root.rem(1.0 * k)    // panel headings
    }

    // ── colour ──────────────────────────────────────────────────────────────
    // Near-black and greys, with a few soft, low-saturation colours used
    // sparingly: lavender for "selected / active", and blue, green, amber and
    // rose for state. Hex with alpha is #AARRGGBB.

    readonly property QtObject colors: QtObject {
        readonly property color frame: "#0d0d10"       // the bar and everything that grows out of it
        readonly property color base: "#f20f0f12"      // floating glass: popups, launcher, screenshot chips
        readonly property color surface: "#16161a"     // cards inside panels
        readonly property color raised: "#202026"      // hover, chips, slider tracks
        readonly property color overlay: "#f216161a"   // small floating bits (countdown pill, tooltips)
        readonly property color border: "#12ffffff"    // hairline, 7% white

        readonly property color text: "#ececf0"
        readonly property color subtext: "#9b9ba6"
        readonly property color faint: "#56565f"
        readonly property color ink: "#121218"         // text on a light fill

        readonly property color accent: "#b4a7e0"      // lavender: selection, active workspace, today, switches
        readonly property color blue: "#92acd6"        // connected things: Wi-Fi, Bluetooth
        readonly property color green: "#9dc6a7"       // good news: a VPN that is on
        readonly property color warn: "#dcb87f"        // amber: battery low, urgent workspace
        readonly property color critical: "#e08f8f"    // rose: critical notification, battery very low, shut down
    }
}
