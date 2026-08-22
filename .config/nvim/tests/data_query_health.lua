local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local function contains(value, needle)
  return type(value) == "string" and value:find(needle, 1, true) ~= nil
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)
local health_module = require("data_query.health")

local function ready_report()
  return {
    duckdb = {
      ok = true,
      path = "/tools/visidata/lib/python3.13/site-packages/duckdb/__init__.py",
      version = "1.5.5",
    },
    environment = "/tools/visidata",
    errors = {},
    ok = true,
    platform = "Linux",
    pyarrow = {
      ok = true,
      path = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
      version = "25.0.0",
    },
    python = "/tools/visidata/bin/python",
    runner = { ok = true, path = nvim_root .. "/scripts/data-query-runner.py" },
    sandbox = {
      ok = true,
      path = "/usr/bin/bwrap",
      probe = "data-query-sandbox-ok",
      version = "0.11.0",
    },
    uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
    viewer = { ok = true, path = "/tools/visidata/bin/vd", version = "3.4" },
  }
end

local function fixture(overrides)
  local reports, commands = {}, {}
  local command_state = { DataQuery = true, DataQueryHealth = true }
  local calls = {
    cache = 0,
    cleanup = 0,
    install = 0,
    network = 0,
    probe = 0,
    workspace = 0,
  }
  local deps = {
    cache = function()
      calls.cache = calls.cache + 1
      error("health touched cache state")
    end,
    cleanup = function()
      calls.cleanup = calls.cleanup + 1
      error("health ran stale cleanup")
    end,
    command_exists = function(name)
      return command_state[name] == true
    end,
    create_user_command = function(name, callback, options)
      commands[#commands + 1] = { callback = callback, name = name, options = options }
      command_state[name] = true
    end,
    health = {},
    install = function()
      calls.install = calls.install + 1
      error("health invoked an installer")
    end,
    network = function()
      calls.network = calls.network + 1
      error("health touched the network")
    end,
    probe = function(options)
      calls.probe = calls.probe + 1
      expect(type(options) == "table" and options.refresh == true, "health did not refresh")
      return ready_report()
    end,
    run_checkhealth = function()
      commands.checkhealth = (commands.checkhealth or 0) + 1
    end,
    workspace = function()
      calls.workspace = calls.workspace + 1
      error("health touched a query workspace")
    end,
  }
  for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
    deps.health[level] = function(message)
      reports[#reports + 1] = { level = level, message = message }
    end
  end
  for key, value in pairs(overrides or {}) do
    deps[key] = value
  end
  return health_module._test.new(deps), reports, commands, calls, command_state
end

local function has(reports, level, needle)
  for _, report in ipairs(reports) do
    if report.level == level and contains(report.message, needle) then
      return true
    end
  end
  return false
end

local function count(reports, level, needle)
  local matches = 0
  for _, report in ipairs(reports) do
    if report.level == level and contains(report.message, needle) then
      matches = matches + 1
    end
  end
  return matches
end

local function expect_passive(calls, context)
  for _, name in ipairs({ "cache", "cleanup", "install", "network", "workspace" }) do
    expect(calls[name] == 0, context .. " invoked the " .. name .. " adapter")
  end
end

do
  local init = table.concat(vim.fn.readfile(nvim_root .. "/init.lua"), "\n")
  local sequence = table.concat({
    'require("parquet.viewer").setup()',
    'require("parquet.health").setup()',
    'require("data_query.workflow").setup()',
    'require("data_query.health").setup()',
  }, "\n")
  expect(contains(init, sequence), "data-query setup is not directly after Parquet setup")
end

do
  local health, reports, _, calls = fixture()
  local ok, detail = pcall(health.check)
  expect(ok, "ready health check raised: " .. tostring(detail))
  expect(calls.probe == 1, "health did not refresh the resolver exactly once")
  expect(has(reports, "start", "Data query"), "missing health heading")
  expect(has(reports, "ok", "Linux"), "missing Linux platform result")
  expect(has(reports, "ok", "uv 0.11.6"), "missing uv result")
  expect(has(reports, "ok", "/usr/bin/uv"), "missing uv path")
  expect(has(reports, "ok", "managed environment"), "missing managed environment")
  expect(has(reports, "ok", "/tools/visidata/bin/python"), "missing Python path")
  expect(has(reports, "ok", "VisiData 3.4"), "missing VisiData result")
  expect(has(reports, "ok", "PyArrow 25.0.0"), "missing PyArrow result")
  expect(has(reports, "ok", "site-packages/pyarrow"), "missing PyArrow import path")
  expect(has(reports, "ok", "DuckDB 1.5.5"), "missing DuckDB result")
  expect(has(reports, "ok", "site-packages/duckdb"), "missing DuckDB import path")
  expect(has(reports, "ok", "Bubblewrap 0.11.0"), "missing Bubblewrap result")
  expect(has(reports, "ok", "/usr/bin/bwrap"), "missing Bubblewrap path")
  expect(has(reports, "ok", "namespace probe"), "missing namespace-probe result")
  expect(has(reports, "ok", "data-query-sandbox-ok"), "missing namespace-probe marker")
  expect(has(reports, "ok", "data-query-runner.py"), "missing runner result")
  expect(has(reports, "ok", "DataQuery is registered"), "missing DataQuery result")
  expect(has(reports, "ok", "DataQueryHealth is registered"), "missing health-command result")
  expect(has(reports, "ok", "workflow is ready"), "missing overall readiness result")
  expect(not has(reports, "error", ""), "ready health check emitted an error")
  expect_passive(calls, "health check")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.duckdb = {
        ok = false,
        path = "/tools/visidata/lib/python3.13/site-packages/duckdb/__init__.py",
        version = "1.4.0",
      }
      report.errors = { "managed DuckDB 1.5.5 is required" }
      report.ok = false
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "DuckDB 1.4.0"), "DuckDB mismatch was hidden")
  expect(has(reports, "error", "DuckDB 1.5.5 is required"), "exact DuckDB requirement was hidden")
  expect(has(reports, "error", "run the dotfiles bootstrap"), "dependency remediation is missing")
  expect(not has(reports, "ok", "workflow is ready"), "mismatched DuckDB was reported ready")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = { "Bubblewrap executable must not be group-writable or world-writable" }
      report.ok = false
      report.sandbox = { ok = false, path = "/usr/bin/bwrap", version = "0.11.0" }
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "Bubblewrap 0.11.0"), "unsafe Bubblewrap was hidden")
  expect(has(reports, "error", "group-writable"), "Bubblewrap safety diagnostic was hidden")
  expect(has(reports, "error", "run the dotfiles bootstrap"), "sandbox remediation is missing")
  expect(not has(reports, "ok", "workflow is ready"), "unsafe Bubblewrap was reported ready")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = { "Bubblewrap namespace probe failed with exit 1" }
      report.ok = false
      report.sandbox = {
        ok = false,
        path = "/usr/bin/bwrap",
        version = "0.11.0",
      }
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "namespace probe"), "failed namespace probe was hidden")
  expect(has(reports, "error", "exit 1"), "namespace-probe diagnostic was hidden")
  expect(not has(reports, "ok", "workflow is ready"), "failed namespace probe was ready")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = { "data-query runner is not readable" }
      report.ok = false
      report.runner = { ok = false, path = nvim_root .. "/scripts/data-query-runner.py" }
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "data-query runner"), "missing runner was hidden")
  expect(has(reports, "error", "not readable"), "runner diagnostic was hidden")
  expect(not has(reports, "ok", "workflow is ready"), "missing runner was reported ready")
end

do
  local calls = 0
  local health, reports = fixture({
    probe = function(options)
      calls = calls + 1
      expect(options.refresh == true, "malformed probe did not refresh")
      return {
        duckdb = { ok = true, path = false, version = "1.5.5" },
        environment = {},
        errors = {},
        ok = true,
        platform = 42,
        pyarrow = "invalid",
        python = false,
        runner = { ok = true, path = {} },
        sandbox = { ok = true, path = false, probe = {}, version = "0.11.0" },
        uv = 42,
        viewer = { ok = true, path = {}, version = "3.4" },
      }
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "malformed component state raised: " .. tostring(detail))
  expect(calls == 1, "malformed resolver refreshed more than once")
  for _, name in ipairs({
    "platform",
    "uv",
    "managed environment",
    "Python",
    "VisiData",
    "PyArrow",
    "DuckDB",
    "Bubblewrap",
    "namespace probe",
    "data-query runner",
  }) do
    expect(has(reports, "error", name), "malformed " .. name .. " state was hidden")
  end
  expect(not has(reports, "ok", "workflow is ready"), "malformed report was ready")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = {
        "first actionable error",
        "second actionable error",
        "first actionable error",
      }
      report.ok = false
      return report
    end,
  })
  health.check()
  expect(count(reports, "error", "first actionable error") == 1, "duplicate error was reported")
  expect(has(reports, "error", "second actionable error"), "unique error was lost")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = {
        [1] = "first sparse error",
        [3] = "last sparse error",
      }
      report.ok = false
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "first sparse error"), "first sparse diagnostic was lost")
  expect(has(reports, "error", "last sparse error"), "last sparse diagnostic was lost")
end

do
  local calls = 0
  local health, reports = fixture({
    probe = function(options)
      calls = calls + 1
      expect(options.refresh == true, "exceptional probe did not refresh")
      error("resolver exploded")
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "resolver exception escaped: " .. tostring(detail))
  expect(calls == 1, "exceptional resolver refreshed more than once")
  expect(has(reports, "error", "resolver exploded"), "resolver exception detail was hidden")
  expect(has(reports, "error", "run the dotfiles bootstrap"), "resolver failure lacks remediation")
  expect(not has(reports, "ok", "workflow is ready"), "exceptional resolver was ready")
end

do
  local health, reports = fixture({
    probe = function()
      return "not a report"
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "non-table resolver result raised: " .. tostring(detail))
  expect(has(reports, "error", "invalid report"), "non-table resolver result was hidden")
  expect(not has(reports, "ok", "workflow is ready"), "non-table resolver result was ready")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = "not an error list"
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "malformed diagnostics"), "malformed diagnostics were accepted")
  expect(not has(reports, "ok", "workflow is ready"), "malformed diagnostics were ready")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = nil
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "malformed diagnostics"), "missing diagnostics were accepted")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = { "" }
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "malformed diagnostics"), "empty diagnostic was accepted")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = {}
      report.ok = false
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "validation failed"), "inconsistent resolver state was accepted")
  expect(not has(reports, "ok", "workflow is ready"), "inconsistent resolver state was ready")
end

do
  local health, reports = fixture({
    probe = function()
      local report = ready_report()
      report.errors = { "data queries are supported only on Linux (detected Darwin)" }
      report.ok = false
      report.platform = "Darwin"
      report.sandbox = { ok = false }
      return report
    end,
  })
  health.check()
  expect(has(reports, "error", "Linux-only"), "non-Linux limitation was not explicit")
  expect(has(reports, "error", "Darwin"), "detected platform was hidden")
  expect(not has(reports, "ok", "workflow is ready"), "non-Linux platform was ready")
end

do
  local health, reports = fixture({
    command_exists = function()
      return false
    end,
  })
  health.check()
  expect(has(reports, "error", "DataQuery is not registered"), "missing DataQuery was hidden")
  expect(
    has(reports, "error", "DataQueryHealth is not registered"),
    "missing DataQueryHealth was hidden"
  )
  expect(not has(reports, "ok", "workflow is ready"), "missing command was reported ready")
end

do
  local health, reports = fixture({
    command_exists = function(name)
      if name == "DataQuery" then
        error("command lookup exploded")
      end
      return "registered"
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "command inspection exception escaped: " .. tostring(detail))
  expect(has(reports, "error", "command lookup exploded"), "command exception was hidden")
  expect(has(reports, "error", "DataQueryHealth"), "malformed command state was hidden")
end

do
  local health = fixture({
    health = {
      error = function()
        error("error reporter exploded")
      end,
      info = function()
        error("info reporter exploded")
      end,
      ok = function()
        error("ok reporter exploded")
      end,
      start = function()
        error("start reporter exploded")
      end,
      warn = function()
        error("warn reporter exploded")
      end,
    },
  })
  local ok, detail = pcall(health.check)
  expect(ok, "health reporter exception escaped: " .. tostring(detail))
end

do
  local health = fixture({
    health = setmetatable({}, {
      __index = function()
        error("reporter lookup exploded")
      end,
    }),
  })
  local ok, detail = pcall(health.check)
  expect(ok, "health reporter lookup exception escaped: " .. tostring(detail))
end

do
  local health, _, commands, calls, command_state = fixture()
  command_state.DataQueryHealth = false
  expect(health.setup() == true, "first health setup failed")
  expect(health.setup() == true, "second health setup failed")
  expect(#commands == 1, "health setup was not idempotent")
  expect(commands[1].name == "DataQueryHealth", "wrong health command name")
  expect(
    commands[1].options.desc == "Check the Neovim data query workflow",
    "wrong health command description"
  )
  expect(calls.probe == 0, "setup probed the data-query runtime")
  expect_passive(calls, "health setup")
  commands[1].callback()
  expect(commands.checkhealth == 1, "command did not run checkhealth data_query")
end

do
  local existence_calls, create_calls = 0, 0
  local health = fixture({
    command_exists = function()
      existence_calls = existence_calls + 1
      if existence_calls == 1 then
        error("command lookup exploded")
      end
      return false
    end,
    create_user_command = function()
      create_calls = create_calls + 1
    end,
  })
  expect(health.setup() == false, "failed command lookup was accepted")
  expect(create_calls == 0, "command was created after an uncertain lookup")
  expect(health.setup() == true, "setup did not retry after lookup failure")
  expect(create_calls == 1, "setup retry did not create the command")
end

do
  local create_calls = 0
  local health = fixture({
    command_exists = function()
      return false
    end,
    create_user_command = function()
      create_calls = create_calls + 1
      if create_calls == 1 then
        error("command creation exploded")
      end
    end,
  })
  expect(health.setup() == false, "failed command creation was accepted")
  expect(health.setup() == true, "setup did not retry after creation failure")
  expect(create_calls == 2, "command creation was not retried exactly once")
end

do
  local create_calls = 0
  local health = fixture({
    command_exists = function()
      return nil
    end,
    create_user_command = function()
      create_calls = create_calls + 1
    end,
  })
  expect(health.setup() == false, "malformed command lookup was accepted")
  expect(create_calls == 0, "command was created after a malformed lookup")
end

do
  pcall(vim.api.nvim_del_user_command, "DataQueryHealth")
  local created
  local original_create_user_command = vim.api.nvim_create_user_command
  vim.api.nvim_create_user_command = function(name, callback, options)
    created = { callback = callback, name = name, options = options }
  end
  local setup_ok, setup_result = pcall(health_module.setup)
  vim.api.nvim_create_user_command = original_create_user_command
  expect(setup_ok and setup_result == true, "production health setup failed")
  expect(type(created) == "table", "production health command was not created")

  local dispatched
  local original_cmd = vim.cmd
  vim.cmd = function(command)
    dispatched = command
  end
  local callback_ok, callback_detail = pcall(created.callback)
  vim.cmd = original_cmd
  expect(callback_ok, "production health callback raised: " .. tostring(callback_detail))
  expect(dispatched == "checkhealth data_query", "health command dispatched the wrong check")
end

print("data query health assertions: ok")
