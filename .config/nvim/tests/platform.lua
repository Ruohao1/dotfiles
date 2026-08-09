local platform = require("config.platform")

local function executable_set(names)
  local present = {}
  for _, name in ipairs(names) do
    present[name] = true
  end

  return function(name)
    return present[name] == true
  end
end

local function assert_equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local definitions = {
  pbcopy = {
    name = "pbcopy",
    copy = {
      ["+"] = { "pbcopy" },
      ["*"] = { "pbcopy" },
    },
    paste = {
      ["+"] = { "pbpaste" },
      ["*"] = { "pbpaste" },
    },
    cache_enabled = 0,
  },
  ["wl-copy"] = {
    name = "wl-copy",
    copy = {
      ["+"] = { "wl-copy", "--type", "text/plain" },
      ["*"] = { "wl-copy", "--primary", "--type", "text/plain" },
    },
    paste = {
      ["+"] = { "wl-paste", "--no-newline" },
      ["*"] = { "wl-paste", "--no-newline", "--primary" },
    },
    cache_enabled = 1,
  },
  tmux = {
    name = "tmux",
    copy = {
      ["+"] = { "tmux", "load-buffer", "-w", "-" },
      ["*"] = { "tmux", "load-buffer", "-w", "-" },
    },
    paste = {
      ["+"] = { "tmux", "save-buffer", "-" },
      ["*"] = { "tmux", "save-buffer", "-" },
    },
    cache_enabled = 1,
  },
  osc52 = "osc52",
}

local cases = {
  {
    context = {
      platform = "macos",
      environment = {},
      executable = executable_set({ "pbcopy", "pbpaste" }),
    },
    provider = "pbcopy",
  },
  {
    context = {
      platform = "linux",
      environment = { WAYLAND_DISPLAY = "wayland-1" },
      executable = executable_set({ "wl-copy", "wl-paste" }),
    },
    provider = "wl-copy",
  },
  {
    context = {
      platform = "linux",
      environment = { TMUX = "/tmp/tmux/default,1,0" },
      executable = executable_set({ "tmux" }),
    },
    provider = "tmux",
  },
  {
    context = {
      platform = "macos",
      environment = { TMUX = "/tmp/tmux/default,1,0" },
      executable = executable_set({ "tmux" }),
    },
    provider = "tmux",
  },
  {
    context = {
      platform = "linux",
      environment = {},
      executable = executable_set({}),
    },
    provider = "osc52",
  },
}

for _, case in ipairs(cases) do
  local provider = platform.select_clipboard(case.context)
  assert(provider == case.provider, string.format("expected %s, got %s", case.provider, provider))
  assert_equal(
    platform.clipboard_definition(provider),
    definitions[provider],
    provider .. " definition mismatch"
  )
end

local incomplete_contexts = {
  {},
  { platform = "linux" },
  { platform = "linux", environment = {} },
}

for _, context in ipairs(incomplete_contexts) do
  assert(not pcall(platform.select_clipboard, context), "incomplete clipboard context must fail")
end

assert(not pcall(platform.clipboard_definition, "xsel"), "unsupported clipboard provider must fail")

print("platform clipboard matrix: ok")
