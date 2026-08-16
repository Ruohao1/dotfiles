local M = {}

local function nonempty(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function safe_text(value)
  local ok, result = pcall(tostring, value)
  return ok and result or "unprintable value"
end

local function new(deps)
  local Health = {}

  local function report(level, message)
    local health = type(deps.health) == "table" and deps.health or nil
    local reporter = health and rawget(health, level) or nil
    if type(reporter) ~= "function" then
      return false
    end
    return pcall(reporter, message)
  end

  local function report_component(state, key, name)
    local value = rawget(state, key)
    local component = type(value) == "table" and value or nil
    local version = component and nonempty(rawget(component, "version")) or nil
    local path = component and nonempty(rawget(component, "path")) or nil
    local ready = component ~= nil
      and rawget(component, "ok") == true
      and version ~= nil
      and path ~= nil
    local message
    if component then
      message = name .. " " .. (version or "unknown") .. ": " .. (path or "unavailable")
    else
      message = name .. " status unavailable"
    end
    if not ready then
      message = message .. "; run the dotfiles bootstrap"
    end
    report(ready and "ok" or "error", message)
    return ready
  end

  local function report_errors(state, initial)
    local seen = {}
    local count = 0

    local function emit(message)
      message = nonempty(message)
      if not message or seen[message] then
        return
      end
      seen[message] = true
      count = count + 1
      report("error", message .. "; run the dotfiles bootstrap")
    end

    emit(initial)
    local errors = rawget(state, "errors")
    if errors == nil then
      if initial == nil then
        emit("dependency probe returned malformed diagnostics")
      end
    elseif type(errors) ~= "table" then
      emit("dependency probe returned malformed diagnostics")
    elseif type(errors) == "table" then
      local malformed = false
      local indices = {}
      for key in next, errors do
        if type(key) == "number" and key >= 1 and key % 1 == 0 then
          indices[#indices + 1] = key
        else
          malformed = true
        end
      end
      table.sort(indices)
      for _, index in ipairs(indices) do
        local message = rawget(errors, index)
        if nonempty(message) then
          emit(message)
        else
          malformed = true
        end
      end
      if malformed then
        emit("dependency probe returned malformed diagnostics")
      end
    end
    return count
  end

  function Health.check()
    report("start", "Neovim Parquet viewer")
    local ok, result = pcall(deps.probe, { refresh = true })
    local state = ok and type(result) == "table" and result or {}
    local probe_error
    if not ok then
      probe_error = "dependency probe failed: " .. safe_text(result)
    elseif type(result) ~= "table" then
      probe_error = "dependency probe returned an invalid report: " .. safe_text(result)
    end

    local uv_ready = report_component(state, "uv", "uv")
    local viewer_ready = report_component(state, "viewer", "VisiData")
    local pyarrow_ready = report_component(state, "pyarrow", "PyArrow")
    local error_count = report_errors(state, probe_error)
    local components_ready = uv_ready and viewer_ready and pyarrow_ready
    local tool_ready = rawget(state, "ok") == true and components_ready and error_count == 0
    if not tool_ready and components_ready and error_count == 0 then
      report("error", "dependency validation failed; run the dotfiles bootstrap")
    end

    local autocmd_ok, autocmd_result = pcall(deps.autocmd_registered)
    local autocmd_ready = autocmd_ok and autocmd_result == true
    if autocmd_ready then
      report("ok", "automatic BufReadCmd *.parquet interception is registered")
    elseif not autocmd_ok then
      report(
        "error",
        "automatic BufReadCmd *.parquet interception is unavailable: " .. safe_text(autocmd_result)
      )
    else
      report("error", "automatic BufReadCmd *.parquet interception is unavailable")
    end

    if tool_ready and autocmd_ready then
      report("ok", "Parquet viewer is ready")
    end
  end

  function Health.setup()
    local exists_ok, exists = pcall(deps.command_exists, "ParquetHealth")
    if not exists_ok or type(exists) ~= "boolean" then
      return false
    end
    if exists then
      return true
    end
    local create_ok = pcall(deps.create_user_command, "ParquetHealth", function()
      deps.run_checkhealth()
    end, { desc = "Check the Neovim Parquet viewer" })
    return create_ok
  end

  return Health
end

local runtime = new({
  autocmd_registered = function()
    return #vim.api.nvim_get_autocmds({
      event = "BufReadCmd",
      group = "dotfiles-parquet-viewer",
      pattern = "*.parquet",
    }) == 1
  end,
  command_exists = function(name)
    return vim.fn.exists(":" .. name) == 2
  end,
  create_user_command = function(name, callback, options)
    vim.api.nvim_create_user_command(name, callback, options)
  end,
  health = vim.health,
  probe = function(options)
    return require("parquet.tool").probe(options)
  end,
  run_checkhealth = function()
    vim.cmd("checkhealth parquet")
  end,
})

M.check = runtime.check
M.setup = runtime.setup
M._test = { new = new }

return M
