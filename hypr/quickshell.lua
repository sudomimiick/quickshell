-- Quickshell desktop: start the shell and bind its keys.
-- install.sh puts this next to your hyprland.lua and loads it from there with
--   pcall(require, "quickshell")
-- Change any key you like; `hyprctl globalshortcuts` lists everything the shell offers.

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -n")  -- -n: don't start a second copy
    -- a polkit agent, so apps (and joining some networks) can ask for your password
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)

-- The shell's bar, wallpaper and panels animate themselves; Hyprland's own
-- open animation on top would only make them appear later at login.
hl.layer_rule({ match = { namespace = "^qs-" }, no_anim = true })

local mod = "SUPER"

hl.bind(mod .. " + D",      hl.dsp.global("quickshell:launcher"),      { description = "App launcher" })
hl.bind(mod .. " + N",      hl.dsp.global("quickshell:notifications"), { description = "Calendar and notifications" })
hl.bind(mod .. " + W",      hl.dsp.global("quickshell:network"),       { description = "Battery, Wi-Fi and VPN" })
hl.bind(mod .. " + A",      hl.dsp.global("quickshell:controls"),      { description = "Display, sound and Bluetooth" })
hl.bind(mod .. " + SHIFT + W", hl.dsp.global("quickshell:wallpaper"), { description = "Wallpaper picker" })
hl.bind(mod .. " + Escape", hl.dsp.global("quickshell:session"),       { description = "Power menu" })

-- Screenshots
hl.bind("Print",           hl.dsp.exec_cmd("qs ipc call screenshot region"), { description = "Screenshot: region or window" })
hl.bind("SHIFT + Print",   hl.dsp.exec_cmd("qs ipc call screenshot screen"), { description = "Screenshot: whole screen" })
hl.bind(mod .. " + Print", hl.dsp.exec_cmd("qs ipc call screenshot window"), { description = "Screenshot: active window" })

-- Volume and brightness keys. The pop-up shows whatever changes them, so if your
-- config already binds these keys (to wpctl / brightnessctl) keep yours and leave
-- these off — binding a key twice makes both fire.
-- hl.bind("XF86AudioRaiseVolume",  hl.dsp.global("quickshell:volumeUp"),       { locked = true, repeating = true })
-- hl.bind("XF86AudioLowerVolume",  hl.dsp.global("quickshell:volumeDown"),     { locked = true, repeating = true })
-- hl.bind("XF86AudioMute",         hl.dsp.global("quickshell:volumeMute"),     { locked = true })
-- hl.bind("XF86AudioMicMute",      hl.dsp.global("quickshell:micMute"),        { locked = true })
-- hl.bind("XF86MonBrightnessUp",   hl.dsp.global("quickshell:brightnessUp"),   { locked = true, repeating = true })
-- hl.bind("XF86MonBrightnessDown", hl.dsp.global("quickshell:brightnessDown"), { locked = true, repeating = true })
