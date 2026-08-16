vim.g.mapleader = " "

local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format(
      "%s\nexpected: %s\nactual:   %s",
      label,
      vim.inspect(expected),
      vim.inspect(actual)
    )
  )
end

local function exact_keys(value, expected, label)
  local actual = {}
  for key in pairs(value) do
    actual[tostring(key)] = true
  end

  local wanted = {}
  for _, key in ipairs(expected) do
    wanted[key] = true
  end
  eq(actual, wanted, label)
end

local function count_plain(haystack, needle)
  local count = 0
  local offset = 1
  while true do
    local first = haystack:find(needle, offset, true)
    if not first then
      return count
    end
    count = count + 1
    offset = first + #needle
  end
end

local function normalized_modes(mode, label)
  local modes = type(mode) == "table" and vim.deepcopy(mode) or { mode }
  assert(#modes > 0, label .. " must declare at least one mode")
  table.sort(modes)
  return modes
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.env.DOTFILES_NVIM_ROOT or vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

local specs = require("plugins.key-helper")
eq(#specs, 1, "key helper plugin count")

local plugin = specs[1]
exact_keys(plugin, { "1", "dependencies", "event", "opts", "version" }, "WhichKey spec keys")
eq(plugin[1], "folke/which-key.nvim", "WhichKey repository")
eq(plugin.version, false, "WhichKey rolling version policy")
eq(plugin.event, "VeryLazy", "WhichKey load event")
eq(plugin.dependencies, { "nvim-mini/mini.icons" }, "WhichKey icon dependency")
assert(plugin.keys == nil and plugin.config == nil, "WhichKey must not create action mappings")

exact_keys(
  plugin.opts,
  { "delay", "filter", "plugins", "preset", "spec", "triggers" },
  "WhichKey option keys"
)
eq(plugin.opts.preset, "helix", "WhichKey preset")
eq(plugin.opts.delay, 300, "WhichKey delay")
assert(plugin.opts.defer == nil, "WhichKey must preserve the default defer policy")
assert(plugin.opts.timeoutlen == nil, "WhichKey must not configure timeoutlen")

local allowed_modes = { n = true, o = true, x = true }
for _, mode in ipairs({ "n", "x", "o" }) do
  assert(plugin.opts.filter({ mode = mode }), "filter rejected approved mode " .. mode)
end
for _, mode in ipairs({ "v", "i", "s", "c", "t", "", "N", "no", "!" }) do
  assert(not plugin.opts.filter({ mode = mode }), "filter accepted prohibited mode " .. mode)
end
assert(not plugin.opts.filter({}), "filter accepted a missing scalar mode")
assert(not plugin.opts.filter({ mode = { "n" } }), "filter accepted a nonscalar mode")

local required_triggers = {
  { "<auto>", { "n", "o", "x" } },
  { "<leader>", { "n", "x" } },
  { "g", { "n", "x" } },
  { "z", { "n" } },
  { "[", { "n" } },
  { "]", { "n" } },
  { "<C-w>", { "n" } },
  { "'", { "n" } },
  { "`", { "n" } },
  { '"', { "n", "x" } },
}

local trigger_counts = {}
for index, trigger in ipairs(plugin.opts.triggers) do
  exact_keys(trigger, { "1", "mode" }, "WhichKey trigger " .. index .. " keys")
  assert(type(trigger[1]) == "string" and trigger[1] ~= "", "WhichKey trigger prefix is invalid")

  local modes = normalized_modes(trigger.mode, "WhichKey trigger " .. trigger[1])
  for _, mode in ipairs(modes) do
    assert(allowed_modes[mode], "WhichKey trigger installed a prohibited mode: " .. tostring(mode))
    assert(mode ~= "v", "WhichKey trigger must use x instead of v")
  end

  local identity = trigger[1] .. "\0" .. table.concat(modes, "\0")
  trigger_counts[identity] = (trigger_counts[identity] or 0) + 1
end

for _, required in ipairs(required_triggers) do
  local identity = required[1] .. "\0" .. table.concat(required[2], "\0")
  eq(trigger_counts[identity], 1, "required WhichKey trigger " .. required[1])
end

eq(plugin.opts.plugins, {
  marks = true,
  registers = true,
  spelling = { enabled = false },
  presets = {
    operators = true,
    motions = true,
    text_objects = true,
    windows = true,
    nav = true,
    z = true,
    g = true,
  },
}, "WhichKey built-in descriptions")

local expected_groups = {
  ["<leader>b\0n"] = "Buffers",
  ["<leader>c\0n\0x"] = "Code",
  ["<leader>f\0n"] = "Find",
  ["<leader>h\0n"] = "Line pins",
  ["<leader>j\0n\0x"] = "Notebook",
  ["<leader>t\0n"] = "Toggle",
}
local actual_groups = {}
for index, group in ipairs(plugin.opts.spec) do
  exact_keys(group, { "1", "group", "mode" }, "WhichKey group " .. index .. " keys")
  assert(type(group[1]) == "string" and group[1] ~= "", "WhichKey group prefix is invalid")
  assert(type(group.group) == "string" and group.group ~= "", "WhichKey group label is invalid")
  assert(
    group[2] == nil and group.rhs == nil and group.callback == nil,
    "WhichKey group became executable"
  )
  assert(group[1] ~= "<leader>?", "manual key-helper mapping is forbidden")

  local modes = normalized_modes(group.mode, "WhichKey group " .. group[1])
  for _, mode in ipairs(modes) do
    assert(mode == "n" or mode == "x", "WhichKey group installed a prohibited mode: " .. mode)
    assert(mode ~= "v", "WhichKey group must use x instead of v")
  end
  local identity = group[1] .. "\0" .. table.concat(modes, "\0")
  assert(actual_groups[identity] == nil, "duplicate WhichKey group " .. group[1])
  actual_groups[identity] = group.group
end
eq(actual_groups, expected_groups, "WhichKey leader groups")

local lock_path = vim.fs.joinpath(nvim_root, "lazy-lock.json")
local lock = vim.json.decode(table.concat(vim.fn.readfile(lock_path), "\n"))
eq(lock, {
  ["fzf-lua"] = { branch = "main", commit = "05e44d38de0a79c11fba5f7bf8138791b1dbdd1e" },
  ["image.nvim"] = { branch = "master", commit = "da2be65c153ba15a14a342b05591652a6df70d58" },
  ["jupytext.nvim"] = {
    branch = "master",
    commit = "2e86acfa4345f611c86f57116db0c06ffecb721d",
  },
  ["lazy.nvim"] = { branch = "main", commit = "306a05526ada86a7b30af95c5cc81ffba93fef97" },
  ["mini.icons"] = { branch = "main", commit = "e56797f90192d81f1fda02e662fc3e8e3d775027" },
  ["mini.pairs"] = { branch = "main", commit = "4a014143fcb4e9df26198ccb3ecff3b9e77a048c" },
  ["mini.starter"] = {
    branch = "main",
    commit = "0575c96206d63fd98d7f786df78dc225bf847d95",
  },
  ["mini.surround"] = {
    branch = "main",
    commit = "580e4cb98c5900d9fe743865fb5a5b2178b4ab18",
  },
  ["molten-nvim"] = { branch = "main", commit = "a286aa914d9a154bc359131aab788b5a077a5a99" },
  ["nvim-treesitter"] = {
    branch = "main",
    commit = "074aa4422bf029908338e855d0c0f71470a971bb",
  },
  ["oil.nvim"] = { branch = "master", commit = "b73018b75affd13fa38e2fc94ef753b465f770d7" },
  ["otter.nvim"] = { branch = "main", commit = "f4a033d4e2bd86d4f09386a73d3861538601253d" },
  ["quarto-nvim"] = { branch = "main", commit = "17f1e5d664bc615478230dc0240666329efacf9b" },
  ["smart-splits.nvim"] = {
    branch = "master",
    commit = "ba2850ff3d3b09785a7105c69d06a12117d4b97d",
  },
  ["tokyonight.nvim"] = {
    branch = "main",
    commit = "545d72cde6400835d895160ecb5853874fd5156d",
  },
  ["which-key.nvim"] = {
    branch = "main",
    commit = "3aab2147e74890957785941f0c1ad87d0a44c15a",
  },
}, "Neovim plugin lock boundary")

local plugin_source_path = vim.fs.joinpath(nvim_root, "tests", "plugin_source.lua")
local plugin_source = table.concat(vim.fn.readfile(plugin_source_path), "\n")
eq(
  count_plain(plugin_source, '["which-key.nvim"] = true'),
  1,
  "WhichKey generated doc/tags allowance"
)

if vim.env.DOTFILES_KEY_HELPER_LIVE ~= "1" then
  print("Neovim key helper static assertions: ok")
  return
end

local mini_icons_root =
  assert(vim.env.DOTFILES_MINI_ICONS_ROOT, "DOTFILES_MINI_ICONS_ROOT must be set")
local which_key_root =
  assert(vim.env.DOTFILES_WHICH_KEY_ROOT, "DOTFILES_WHICH_KEY_ROOT must be set")
vim.opt.runtimepath:prepend(mini_icons_root)
vim.opt.runtimepath:prepend(which_key_root)

require("mini.icons").setup()
require("which-key").setup(plugin.opts)

local Config = require("which-key.config")
assert(
  vim.wait(1000, function()
    return Config.loaded
  end),
  "WhichKey did not load"
)
eq(Config.options.preset, "helix", "configured WhichKey preset")
eq(Config.options.plugins.spelling.enabled, false, "configured spelling replacement")
assert(type(Config.defer) == "function", "WhichKey default defer function is missing")
eq(Config.defer({ mode = "v", operator = "" }), false, "characterwise Visual defer")
eq(Config.defer({ mode = "V", operator = "" }), true, "linewise Visual defer")
eq(Config.defer({ mode = "<C-V>", operator = "" }), true, "blockwise Visual defer")
eq(Config.defer({ mode = "o", operator = "d" }), false, "Operator-pending defer")

local automatic_trigger_modes = {}
for mode, enabled in pairs(Config.triggers.modes) do
  assert(allowed_modes[mode], "automatic WhichKey trigger has prohibited mode: " .. tostring(mode))
  assert(enabled == true, "automatic WhichKey trigger mode is not enabled: " .. tostring(mode))
  automatic_trigger_modes[mode] = true
end
eq(automatic_trigger_modes, allowed_modes, "automatic WhichKey trigger modes")

local Buf = require("which-key.buf")
local Triggers = require("which-key.triggers")
local bufnr = vim.api.nvim_get_current_buf()
for _, mode in ipairs({ "n", "x", "o", "v", "i", "s", "c", "t" }) do
  Buf.get({ buf = bufnr, mode = mode })
end
assert(
  vim.wait(1000, function()
    local seen = {}
    for _, trigger in pairs(Triggers._triggers) do
      seen[trigger.mode] = true
    end
    return seen.n and seen.x and seen.o
  end, 10),
  "WhichKey trigger registry did not populate"
)

local installed_trigger_modes = {}
for id, trigger in pairs(Triggers._triggers) do
  assert(
    allowed_modes[trigger.mode],
    string.format("forbidden trigger mode %s at %s", tostring(trigger.mode), tostring(id))
  )
  installed_trigger_modes[trigger.mode] = true
end
eq(installed_trigger_modes, allowed_modes, "installed WhichKey trigger modes")

local function which_key_trigger(lhs, mode)
  local mapping = vim.fn.maparg(lhs, mode, false, true)
  return type(mapping) == "table"
    and type(mapping.desc) == "string"
    and mapping.desc:find("which-key-trigger", 1, true) ~= nil
end

assert(
  vim.wait(1000, function()
    return which_key_trigger("<leader>", "n") and which_key_trigger("g", "n")
  end),
  "approved WhichKey triggers did not install"
)

for _, required in ipairs(required_triggers) do
  if required[1] ~= "<auto>" then
    for _, mode in ipairs(required[2]) do
      assert(which_key_trigger(required[1], mode), mode .. " trigger missing for " .. required[1])
    end
  end
end

local State = require("which-key.state")
eq(State.delay({ mode = "n", keys = "<leader>" }), 300, "normal leader delay")
eq(State.delay({ mode = "x", keys = "g", plugin = "presets" }), 300, "plugin delay remains fixed")

local View = require("which-key.view")
View.hide()
local original_timer = View.timer
local original_state = State.state
local timeout
local repeat_interval
local scheduled_callback
local timer_ok, timer_error = xpcall(function()
  View.timer = {
    start = function(_, requested, repeating, scheduled)
      timeout = requested
      repeat_interval = repeating
      scheduled_callback = scheduled
    end,
  }
  State.state = {
    mode = { mode = "n" },
    node = { keys = "<leader>", plugin = nil },
  }
  View.update()
  eq(timeout, 300, "popup timer timeout")
  eq(repeat_interval, 0, "popup timer repeat")
  assert(type(scheduled_callback) == "function", "popup timer callback")
end, debug.traceback)
View.timer = original_timer
State.state = original_state
assert(timer_ok, timer_error)

local leader_trigger = vim.fn.maparg("<leader>", "n", false, true)
assert(type(leader_trigger.callback) == "function", "leader trigger callback missing")

local action_count = 0
vim.keymap.set("n", "<leader>qa", function()
  action_count = action_count + 1
end, { desc = "Key helper test action" })

vim.defer_fn(function()
  vim.api.nvim_input("qa")
end, 0)
local completion_ok, completion_error = pcall(leader_trigger.callback)
assert(completion_ok, "fast mapping completion failed: " .. tostring(completion_error))
eq(action_count, 1, "fast mapping execution count")
assert(not View.valid(), "fast mapping opened WhichKey")

local original_delay = Config.delay
Config.delay = 0
local before_buffer = vim.api.nvim_get_current_buf()
local before_lines = vim.api.nvim_buf_get_lines(before_buffer, 0, -1, false)
local popup_seen = false
vim.defer_fn(function()
  popup_seen = vim.wait(1000, function()
    return View.valid()
  end, 5)
  vim.api.nvim_input("<Esc>")
end, 0)
local popup_ok, popup_error = pcall(leader_trigger.callback)
Config.delay = original_delay
assert(popup_ok, "WhichKey popup smoke failed: " .. tostring(popup_error))
assert(popup_seen, "WhichKey popup did not open before the upper deadline")
assert(
  vim.wait(1000, function()
    return not View.valid()
  end, 5),
  "WhichKey popup did not close after Escape"
)
eq(vim.api.nvim_get_current_buf(), before_buffer, "WhichKey popup current buffer")
eq(
  vim.api.nvim_buf_get_lines(before_buffer, 0, -1, false),
  before_lines,
  "WhichKey popup buffer text"
)
eq(action_count, 1, "WhichKey popup cancellation action count")

for _, notification in ipairs(require("which-key.mappings").notifs) do
  assert(
    notification.level < vim.log.levels.ERROR,
    "WhichKey mapping diagnostic: " .. notification.msg
  )
end

vim.keymap.del("n", "<leader>qa")
print("Neovim key helper live assertions: ok")
