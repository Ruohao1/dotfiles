-- Portable Hyprland window-management configuration.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "auto",
})

hl.config({
    general = {
        layout = "dwindle",
    },
    dwindle = {
        preserve_split = true,
    },
    input = {
        follow_mouse = 0,
    },
})

hl.bind("SUPER + H", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + L", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
hl.bind("SUPER + SHIFT + K", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + L", hl.dsp.window.move({ direction = "right" }))
hl.bind("SUPER + CTRL + H", hl.dsp.window.resize({ x = -50, y = 0, relative = true }))
hl.bind("SUPER + CTRL + J", hl.dsp.window.resize({ x = 0, y = 50, relative = true }))
hl.bind("SUPER + CTRL + K", hl.dsp.window.resize({ x = 0, y = -50, relative = true }))
hl.bind("SUPER + CTRL + L", hl.dsp.window.resize({ x = 50, y = 0, relative = true }))
hl.bind("SUPER + comma", hl.dsp.focus({ monitor = "-1" }))
hl.bind("SUPER + period", hl.dsp.focus({ monitor = "+1" }))
hl.bind("SUPER + SHIFT + comma", hl.dsp.window.move({ monitor = "-1", follow = true }))
hl.bind("SUPER + SHIFT + period", hl.dsp.window.move({ monitor = "+1", follow = true }))
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind("SUPER + SHIFT + SPACE", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprctl reload"))

hl.bind("SUPER + 1", hl.dsp.focus({ workspace = "name:0" }))
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = "name:1" }))
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = "name:2" }))
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = "name:3" }))
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = "name:4" }))
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = "name:5" }))
hl.bind("SUPER + 7", hl.dsp.focus({ workspace = "name:6" }))
hl.bind("SUPER + 8", hl.dsp.focus({ workspace = "name:7" }))
hl.bind("SUPER + 9", hl.dsp.focus({ workspace = "name:8" }))
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = "name:9" }))
hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = "name:0" }))
hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = "name:1" }))
hl.bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = "name:2" }))
hl.bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = "name:3" }))
hl.bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = "name:4" }))
hl.bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = "name:5" }))
hl.bind("SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = "name:6" }))
hl.bind("SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = "name:7" }))
hl.bind("SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = "name:8" }))
hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = "name:9" }))

local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
    config_home = assert(os.getenv("HOME"), "HOME is required") .. "/.config"
end

local local_config = config_home .. "/hypr/local.lua"
local local_file = io.open(local_config, "r")
if local_file then
    local_file:close()
    dofile(local_config)
end
