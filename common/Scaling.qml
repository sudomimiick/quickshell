pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Smart scaling: keeps the shell the same *apparent* size on any screen.
//
// Hyprland's monitor scale (auto or manual) already multiplies everything Quickshell
// draws. What it can't know is how big the panel physically is or how far away you
// sit, so a 24" 1080p monitor and a 14" laptop end up looking very different.
// This adds one correction factor on top, from the panel's real size (EDID):
//
//   • Your built-in laptop panel is the reference: the shell looks exactly as
//     designed there (factor 1.0, Hyprland's scale does the rest).
//   • Any other screen is matched to it by visual angle — bigger, farther-away
//     monitors get proportionally bigger UI, dense ones get more logical pixels.
//   • No built-in panel ever seen (desktop)? Fall back to the CSS reference pixel.
//
// Check what it decided:   qs ipc call scaling info
// Try a size live:         qs ipc call scaling setUserScale 1.1
Singleton {
    id: root

    readonly property string mode: Config.scaling.mode
    property real userScale: Config.scaling.userScale
    readonly property var overrides: Config.scaling.overrides

    // Built-in panel (eDP / LVDS / DSI) if connected.
    readonly property var builtin: findScreen(s => /^(eDP|LVDS|DSI)/.test(s.name))
    // The screen the shell sizes itself for.
    readonly property var primary: builtin ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    // The one number Theme multiplies every size by.
    readonly property real factor: factorFor(primary)

    // ── measuring ────────────────────────────────────────────────────────────

    function findScreen(pred) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (pred(screens[i]))
                return screens[i];
        return null;
    }

    // ~50 cm for a 14" laptop, ~66 cm for 24", ~70 cm for 27". A heuristic, not a law.
    function viewingDistance(diagIn) {
        return Math.max(40, Math.min(120, 30 + 1.5 * diagIn));
    }

    // physicalPixelDensity is *logical* px per physical mm (QScreen::physicalDotsPerInch / 25.4),
    // and width/height are logical px, so width / density = the panel's real width in mm.
    function measure(s) {
        if (!s)
            return null;
        const pxPerMm = s.physicalPixelDensity;
        if (!(pxPerMm > 1 && pxPerMm < 40))
            return null; // EDID missing or nonsense
        const diagIn = Math.hypot(s.width / pxPerMm, s.height / pxPerMm) / 25.4;
        if (!(diagIn > 7 && diagIn < 100))
            return null;
        return { pxPerMm: pxPerMm, diagIn: diagIn, distCm: viewingDistance(diagIn) };
    }

    function manualFor(s) {
        const o = s ? overrides[s.name] : undefined;
        return userScale * (o !== undefined ? o : 1);
    }

    function factorFor(s) {
        const manual = manualFor(s);
        if (mode !== "auto" || !s || (builtin && s === builtin))
            return manual;
        const m = measure(s);
        if (!m)
            return manual;

        let f;
        if (ref.pxPerMm > 0) {
            // same visual angle as the built-in panel
            f = (m.pxPerMm / ref.pxPerMm) * (m.distCm / viewingDistance(ref.diagIn));
        } else {
            // CSS reference pixel: 1 px = 0.2646 mm seen from 71 cm
            f = m.pxPerMm * 0.2646 * (m.distCm / 71);
        }
        return Math.max(0.6, Math.min(2.5, f)) * manual;
    }

    function describe(s) {
        if (!s)
            return "no screen";
        const m = measure(s);
        const size = m ? `${m.diagIn.toFixed(1)}" panel, ~${Math.round(m.distCm)} cm away` : "unknown physical size";
        const tag = s === builtin ? "  [built-in reference]" : s === primary ? "  [primary]" : "";
        return `${s.name}: ${s.width}x${s.height} logical @ scale ${s.devicePixelRatio.toFixed(2)}, ${size} → factor ${factorFor(s).toFixed(2)}${tag}`;
    }

    // ── remembering the built-in panel ───────────────────────────────────────
    // Survives config reloads, so after you close the lid an external monitor
    // is still matched to the laptop you were just using.

    PersistentProperties {
        id: ref
        reloadableId: "smartScalingRef"
        property real pxPerMm: 0
        property real diagIn: 0
    }

    readonly property var builtinMetrics: measure(builtin)
    onBuiltinMetricsChanged: remember()
    Component.onCompleted: remember()

    function remember() {
        if (builtinMetrics) {
            ref.pxPerMm = builtinMetrics.pxPerMm;
            ref.diagIn = builtinMetrics.diagIn;
        }
    }

    IpcHandler {
        target: "scaling"

        function info(): string {
            const lines = [`mode: ${root.mode}, userScale: ${root.userScale}, factor in use: ${root.factor.toFixed(2)}`];
            const screens = Quickshell.screens;
            for (let i = 0; i < screens.length; i++)
                lines.push(root.describe(screens[i]));
            return lines.join("\n");
        }

        function setUserScale(value: real): void {
            root.userScale = value;
        }
    }
}
