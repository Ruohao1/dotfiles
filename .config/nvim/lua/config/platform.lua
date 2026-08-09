local M = {}

local function is_executable(name)
  return vim.fn.executable(name) == 1
end

function M.detect()
  local sysname = vim.uv.os_uname().sysname

  if sysname == "Darwin" then
    return "macos"
  end

  if sysname == "Linux" then
    return "linux"
  end

  error("Unsupported operating system: " .. sysname)
end

function M.select_clipboard(context)
  local selected_platform = assert(context.platform, "clipboard context requires platform")
  local environment = assert(context.environment, "clipboard context requires environment")
  local executable = assert(context.executable, "clipboard context requires executable")

  if selected_platform == "macos" and executable("pbcopy") and executable("pbpaste") then
    return "pbcopy"
  end

  if
    selected_platform == "linux"
    and environment.WAYLAND_DISPLAY
    and executable("wl-copy")
    and executable("wl-paste")
  then
    return "wl-copy"
  end

  if environment.TMUX and executable("tmux") then
    return "tmux"
  end

  return "osc52"
end

function M.clipboard_definition(name)
  if name == "pbcopy" then
    return {
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
    }
  end

  if name == "wl-copy" then
    return {
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
    }
  end

  if name == "tmux" then
    return {
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
    }
  end

  if name == "osc52" then
    return "osc52"
  end

  error("Unsupported clipboard provider: " .. tostring(name))
end

function M.setup()
  M.name = M.detect()
  M.clipboard_provider = M.select_clipboard({
    platform = M.name,
    environment = vim.env,
    executable = is_executable,
  })

  vim.g.dotfiles_platform = M.name
  vim.g.dotfiles_clipboard_provider = M.clipboard_provider
  vim.g.clipboard = M.clipboard_definition(M.clipboard_provider)

  if vim.env.TMUX and is_executable("tmux") then
    vim.g.smart_splits_multiplexer_integration = "tmux"
  end

  return M
end

return M
