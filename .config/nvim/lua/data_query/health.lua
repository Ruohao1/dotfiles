local M = {}

local bootstrap_remediation = "run the dotfiles bootstrap"
local namespace_marker = "data-query-sandbox-ok"

local function nonempty(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function safe_text(value)
  local ok, result = pcall(tostring, value)
  return ok and result or "unprintable value"
end

local function field(value, key)
  if type(value) ~= "table" then
    return nil, false
  end
  local ok, result = pcall(rawget, value, key)
  return ok and result or nil, ok
end

local function with_bootstrap(message)
  if message:find(bootstrap_remediation, 1, true) then
    return message
  end
  return message .. "; " .. bootstrap_remediation
end

local function new(deps)
  local Health = {}

  local function report(level, message)
    local health = type(deps.health) == "table" and deps.health or nil
    local lookup_ok, reporter = pcall(function()
      return health and rawget(health, level) or nil
    end)
    if not lookup_ok or type(reporter) ~= "function" then
      return false
    end
    return pcall(reporter, message)
  end

  local function report_component(state, key, name)
    local value = field(state, key)
    local component = type(value) == "table" and value or nil
    local ok_value = component and field(component, "ok") or nil
    local version = component and nonempty(field(component, "version")) or nil
    local path = component and nonempty(field(component, "path")) or nil
    local ready = component ~= nil and ok_value == true and version ~= nil and path ~= nil
    local message
    if component then
      message = name .. " " .. (version or "unknown") .. ": " .. (path or "unavailable")
    else
      message = name .. " status unavailable"
    end
    report(ready and "ok" or "error", ready and message or with_bootstrap(message))
    return ready
  end

  local function report_path(state, key, name)
    local path = nonempty(field(state, key))
    local ready = path ~= nil
    local message = name .. ": " .. (path or "unavailable")
    report(ready and "ok" or "error", ready and message or with_bootstrap(message))
    return ready
  end

  local function report_platform(state)
    local platform = nonempty(field(state, "platform"))
    if platform == "Linux" then
      report("ok", "data query platform: Linux")
      return true
    end
    local detected = platform or "unavailable"
    report(
      "error",
      "data query platform: "
        .. detected
        .. "; query execution is Linux-only because it requires Bubblewrap"
    )
    return false
  end

  local function report_namespace(state)
    local sandbox = field(state, "sandbox")
    local probe = type(sandbox) == "table" and nonempty(field(sandbox, "probe")) or nil
    local ready = probe == namespace_marker
    local message = "Bubblewrap namespace probe: " .. (probe or "unavailable")
    report(ready and "ok" or "error", ready and message or with_bootstrap(message))
    return ready
  end

  local function report_runner(state)
    local value = field(state, "runner")
    local runner = type(value) == "table" and value or nil
    local ok_value = runner and field(runner, "ok") or nil
    local path = runner and nonempty(field(runner, "path")) or nil
    local ready = runner ~= nil and ok_value == true and path ~= nil
    local message = "data-query runner: " .. (path or "unavailable")
    report(ready and "ok" or "error", ready and message or with_bootstrap(message))
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
      report("error", with_bootstrap(message))
    end

    emit(initial)
    local errors = field(state, "errors")
    if errors == nil then
      if initial == nil then
        emit("data-query resolver returned malformed diagnostics")
      end
    elseif type(errors) ~= "table" then
      emit("data-query resolver returned malformed diagnostics")
    else
      local indices = {}
      local malformed = false
      local scan_ok = pcall(function()
        for key in next, errors do
          if type(key) == "number" and key >= 1 and key % 1 == 0 then
            indices[#indices + 1] = key
          else
            malformed = true
          end
        end
      end)
      if not scan_ok then
        malformed = true
      end
      table.sort(indices)
      for _, index in ipairs(indices) do
        local message = field(errors, index)
        if nonempty(message) then
          emit(message)
        else
          malformed = true
        end
      end
      if malformed then
        emit("data-query resolver returned malformed diagnostics")
      end
    end
    return count
  end

  local function report_command(name)
    local ok, result = pcall(deps.command_exists, name)
    if ok and result == true then
      report("ok", name .. " is registered")
      return true
    end
    if not ok then
      report("error", name .. " registration could not be inspected: " .. safe_text(result))
    elseif result == false then
      report("error", name .. " is not registered")
    else
      report("error", name .. " registration returned an invalid status")
    end
    return false
  end

  function Health.check()
    report("start", "Neovim Data query workflow")
    local ok, result = pcall(deps.probe, { refresh = true })
    local state = ok and type(result) == "table" and result or {}
    local probe_error
    if not ok then
      probe_error = "data-query resolver failed: " .. safe_text(result)
    elseif type(result) ~= "table" then
      probe_error = "data-query resolver returned an invalid report: " .. safe_text(result)
    end

    local platform_ready = report_platform(state)
    local uv_ready = report_component(state, "uv", "uv")
    local environment_ready = report_path(state, "environment", "managed environment")
    local python_ready = report_path(state, "python", "Python")
    local viewer_ready = report_component(state, "viewer", "VisiData")
    local pyarrow_ready = report_component(state, "pyarrow", "PyArrow")
    local duckdb_ready = report_component(state, "duckdb", "DuckDB")
    local sandbox_ready = report_component(state, "sandbox", "Bubblewrap")
    local namespace_ready = report_namespace(state)
    local runner_ready = report_runner(state)
    local error_count = report_errors(state, probe_error)
    local report_ok = field(state, "ok") == true
    local components_ready = platform_ready
      and uv_ready
      and environment_ready
      and python_ready
      and viewer_ready
      and pyarrow_ready
      and duckdb_ready
      and sandbox_ready
      and namespace_ready
      and runner_ready
    local resolver_ready = report_ok and components_ready and error_count == 0
    if not resolver_ready and components_ready and error_count == 0 then
      report("error", with_bootstrap("data-query resolver validation failed"))
    end

    local data_query_ready = report_command("DataQuery")
    local health_ready = report_command("DataQueryHealth")
    if resolver_ready and data_query_ready and health_ready then
      report("ok", "Data query workflow is ready")
    end
  end

  function Health.setup()
    local exists_ok, exists = pcall(deps.command_exists, "DataQueryHealth")
    if not exists_ok or type(exists) ~= "boolean" then
      return false
    end
    if exists then
      return true
    end
    local create_ok = pcall(deps.create_user_command, "DataQueryHealth", function()
      pcall(deps.run_checkhealth)
    end, { desc = "Check the Neovim data query workflow" })
    return create_ok
  end

  return Health
end

local runtime = new({
  command_exists = function(name)
    return vim.fn.exists(":" .. name) == 2
  end,
  create_user_command = function(name, callback, options)
    vim.api.nvim_create_user_command(name, callback, options)
  end,
  health = vim.health,
  probe = function(options)
    return require("data_query.tool").probe(options)
  end,
  run_checkhealth = function()
    vim.cmd("checkhealth data_query")
  end,
})

M.check = runtime.check
M.setup = runtime.setup
M._test = { new = new }

return M
