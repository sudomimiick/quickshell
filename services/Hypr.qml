pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Hyprland actions that work with both config flavours: in Lua mode (your
// hyprland.lua) dispatchers are Lua expressions, otherwise the classic syntax.
Singleton {
    id: root

    function focusWorkspace(id) {
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.focus({ workspace = "${id}" })`);
        else
            Hyprland.dispatch(`workspace ${id}`);
    }

    function exit() {
        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.exit()" : "exit");
    }

    // Workspace ids a bar shows: 1…count always (like waybar's persistent-workspaces),
    // plus any other normal workspace that lives on this monitor.
    function workspaceIds(all, monitorName, count) {
        const ids = [];
        for (let i = 1; i <= count; i++)
            ids.push(i);
        for (const w of all) {
            if (!w || w.id <= count || w.name.startsWith("special:"))
                continue;
            if (w.monitor && w.monitor.name !== monitorName)
                continue;
            if (!ids.includes(w.id))
                ids.push(w.id);
        }
        return ids.sort((a, b) => a - b);
    }

    // Next/previous workspace for a scroll on the bar (stays inside what's shown).
    function stepWorkspace(ids, current, d) {
        if (!ids.length)
            return current;
        const i = ids.indexOf(current);
        if (i < 0)
            return d > 0 ? ids[0] : ids[ids.length - 1];
        return ids[Math.max(0, Math.min(ids.length - 1, i + d))];
    }
}
