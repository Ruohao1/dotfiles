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
local health_module = require("parquet.health")

local function fixture(overrides)
  local reports, commands = {}, {}
  local exists = false
  local probe_calls = 0
  local deps = {
    autocmd_registered = function()
      return true
    end,
    command_exists = function()
      return exists
    end,
    create_user_command = function(name, callback, options)
      commands[#commands + 1] = { callback = callback, name = name, options = options }
      exists = true
    end,
    health = {},
    probe = function(options)
      probe_calls = probe_calls + 1
      expect(options.refresh == true, "health did not refresh")
      return {
        environment = "/tools/visidata",
        errors = {},
        ok = true,
        pyarrow = {
          ok = true,
          path = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
          version = "25.0.0",
        },
        python = "/tools/visidata/bin/python",
        uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
        viewer = { ok = true, path = "/tools/visidata/bin/vd", version = "3.4" },
      }
    end,
    run_checkhealth = function()
      commands.checkhealth = (commands.checkhealth or 0) + 1
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
  return health_module._test.new(deps), reports, commands, function()
    return probe_calls
  end
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

do
  local health, reports = fixture()
  health.check()
  expect(has(reports, "start", "Parquet viewer"), "missing health heading")
  expect(has(reports, "ok", "uv 0.11.6"), "missing uv result")
  expect(has(reports, "ok", "VisiData 3.4"), "missing VisiData result")
  expect(has(reports, "ok", "PyArrow 25.0.0"), "missing PyArrow result")
  expect(has(reports, "ok", "site-packages/pyarrow"), "missing PyArrow import path")
  expect(has(reports, "ok", "BufReadCmd"), "missing autocmd result")
  expect(has(reports, "ok", "ready"), "missing readiness result")
end

do
  local health, reports = fixture({
    probe = function()
      return {
        errors = {
          "managed VisiData 3.4 is required",
          "managed PyArrow 25.0.0 is required",
        },
        ok = false,
        pyarrow = { ok = false, path = "/tools/visidata/site-packages/pyarrow", version = "24.0.0" },
        uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
        viewer = { ok = false, path = "/tools/visidata/bin/vd", version = "3.3" },
      }
    end,
  })
  health.check()
  expect(has(reports, "error", "VisiData 3.3"), "mismatched VisiData version was hidden")
  expect(has(reports, "error", "PyArrow 24.0.0"), "mismatched PyArrow version was hidden")
end

do
  local health, reports = fixture({
    probe = function()
      return { errors = { "managed PyArrow 25.0.0 is required" }, ok = false }
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "failed health probe raised: " .. tostring(detail))
  expect(has(reports, "error", "PyArrow 25.0.0"), "missing dependency error")
  expect(has(reports, "error", "dotfiles bootstrap"), "missing remediation")
end

do
  local health, reports = fixture({
    autocmd_registered = function()
      return false
    end,
  })
  health.check()
  expect(has(reports, "error", "BufReadCmd"), "missing autocmd was accepted")
end

do
  local calls = 0
  local health, reports = fixture({
    probe = function(options)
      calls = calls + 1
      expect(options.refresh == true, "malformed probe did not refresh")
      return {
        errors = {
          "first actionable dependency error",
          "second actionable dependency error",
          "first actionable dependency error",
        },
        ok = true,
        pyarrow = { ok = true, path = false, version = "25.0.0" },
        uv = 42,
        viewer = { ok = true, path = {}, version = "3.4" },
      }
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "malformed component state raised: " .. tostring(detail))
  expect(calls == 1, "malformed probe refreshed more than once")
  expect(has(reports, "error", "uv"), "malformed uv state was hidden")
  expect(has(reports, "error", "VisiData"), "malformed VisiData state was hidden")
  expect(has(reports, "error", "PyArrow"), "malformed PyArrow state was hidden")
  expect(
    count(reports, "error", "first actionable dependency error") == 1,
    "duplicate dependency error was reported"
  )
  expect(has(reports, "error", "second actionable dependency error"), "dependency error was lost")
  expect(not has(reports, "ok", "ready"), "malformed tool state was reported ready")
end

do
  local health, reports = fixture({
    probe = function()
      return {
        errors = {
          [1] = "first sparse dependency error",
          [3] = "last sparse dependency error",
        },
        ok = false,
        pyarrow = {
          ok = true,
          path = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
          version = "25.0.0",
        },
        uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
        viewer = { ok = true, path = "/tools/visidata/bin/vd", version = "3.4" },
      }
    end,
  })
  health.check()
  expect(has(reports, "error", "first sparse dependency error"), "first sparse error was lost")
  expect(has(reports, "error", "last sparse dependency error"), "last sparse error was lost")
end

do
  local calls = 0
  local health, reports = fixture({
    probe = function(options)
      calls = calls + 1
      expect(options.refresh == true, "exceptional probe did not refresh")
      error("probe exploded")
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "probe exception escaped: " .. tostring(detail))
  expect(calls == 1, "exceptional probe refreshed more than once")
  expect(has(reports, "error", "probe exploded"), "probe exception detail was hidden")
  expect(has(reports, "error", "dotfiles bootstrap"), "probe exception lacked remediation")
  expect(not has(reports, "error", "malformed diagnostics"), "probe exception was misclassified")
  expect(not has(reports, "ok", "ready"), "exceptional probe was reported ready")
end

do
  local health, reports = fixture({
    probe = function()
      return "not a report"
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "non-table probe result raised: " .. tostring(detail))
  expect(has(reports, "error", "invalid report"), "non-table probe result was hidden")
  expect(not has(reports, "error", "malformed diagnostics"), "non-table probe was misclassified")
  expect(not has(reports, "ok", "ready"), "non-table probe result was reported ready")
end

do
  local health, reports = fixture({
    probe = function()
      return {
        errors = "not an error list",
        ok = true,
        pyarrow = {
          ok = true,
          path = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
          version = "25.0.0",
        },
        uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
        viewer = { ok = true, path = "/tools/visidata/bin/vd", version = "3.4" },
      }
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "malformed error list raised: " .. tostring(detail))
  expect(has(reports, "error", "diagnostics"), "malformed error list was hidden")
  expect(not has(reports, "ok", "ready"), "malformed error list was reported ready")
end

do
  local health, reports = fixture({
    probe = function()
      return {
        errors = { "" },
        ok = true,
        pyarrow = {
          ok = true,
          path = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
          version = "25.0.0",
        },
        uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
        viewer = { ok = true, path = "/tools/visidata/bin/vd", version = "3.4" },
      }
    end,
  })
  health.check()
  expect(has(reports, "error", "diagnostics"), "empty dependency diagnostic was accepted")
  expect(not has(reports, "ok", "ready"), "empty dependency diagnostic was reported ready")
end

do
  local health, reports = fixture({
    probe = function()
      return {
        ok = true,
        pyarrow = {
          ok = true,
          path = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
          version = "25.0.0",
        },
        uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
        viewer = { ok = true, path = "/tools/visidata/bin/vd", version = "3.4" },
      }
    end,
  })
  health.check()
  expect(has(reports, "error", "diagnostics"), "missing dependency diagnostics were accepted")
  expect(not has(reports, "ok", "ready"), "missing dependency diagnostics were reported ready")
end

do
  local health, reports = fixture({
    autocmd_registered = function()
      error("autocmd lookup exploded")
    end,
  })
  local ok, detail = pcall(health.check)
  expect(ok, "autocmd adapter exception escaped: " .. tostring(detail))
  expect(has(reports, "error", "autocmd lookup exploded"), "autocmd lookup detail was hidden")
  expect(not has(reports, "ok", "ready"), "failed autocmd lookup was reported ready")
end

do
  local health, reports = fixture({
    autocmd_registered = function()
      return "registered"
    end,
  })
  health.check()
  expect(has(reports, "error", "BufReadCmd"), "non-boolean autocmd state was accepted")
  expect(not has(reports, "ok", "ready"), "non-boolean autocmd state was reported ready")
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
  local health, _, commands, probe_calls = fixture()
  health.setup()
  health.setup()
  expect(#commands == 1, "health setup was not idempotent")
  expect(commands[1].name == "ParquetHealth", "wrong command name")
  expect(commands[1].options.desc == "Check the Neovim Parquet viewer", "wrong description")
  expect(probe_calls() == 0, "setup probed or downloaded dependencies")
  commands[1].callback()
  expect(commands.checkhealth == 1, "command did not run checkhealth parquet")
end

do
  local existence_calls = 0
  local create_calls = 0
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
  local first_ok, first_detail = pcall(health.setup)
  expect(first_ok, "command lookup exception escaped: " .. tostring(first_detail))
  expect(create_calls == 0, "setup created a command after an uncertain existence check")
  local second_ok, second_detail = pcall(health.setup)
  expect(second_ok, "setup did not retry after a command lookup error: " .. tostring(second_detail))
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
  local first_ok, first_detail = pcall(health.setup)
  expect(first_ok, "command creation exception escaped: " .. tostring(first_detail))
  local second_ok, second_detail = pcall(health.setup)
  expect(
    second_ok,
    "setup did not retry after a command creation error: " .. tostring(second_detail)
  )
  expect(create_calls == 2, "failed command creation was not retried exactly once")
end

do
  local exists = false
  local create_calls = 0
  local health = fixture({
    command_exists = function()
      return exists
    end,
    create_user_command = function()
      create_calls = create_calls + 1
      exists = true
      error("command appeared during creation")
    end,
  })
  local first_ok, first_detail = pcall(health.setup)
  expect(first_ok, "command creation race escaped: " .. tostring(first_detail))
  local second_ok, second_detail = pcall(health.setup)
  expect(second_ok, "command creation race retry escaped: " .. tostring(second_detail))
  expect(create_calls == 1, "setup tried to replace a command that appeared during creation")
end

do
  local create_calls = 0
  local health = fixture({
    command_exists = function()
      return true
    end,
    create_user_command = function()
      create_calls = create_calls + 1
    end,
  })
  health.setup()
  health.setup()
  expect(create_calls == 0, "setup replaced an existing user command")
end

do
  local existence_calls = 0
  local create_calls = 0
  local health = fixture({
    command_exists = function()
      existence_calls = existence_calls + 1
      if existence_calls == 1 then
        return nil
      end
      return false
    end,
    create_user_command = function()
      create_calls = create_calls + 1
    end,
  })
  health.setup()
  expect(create_calls == 0, "setup created a command after a malformed existence result")
  health.setup()
  expect(create_calls == 1, "setup did not retry after a malformed existence result")
end

do
  local previous_tool = package.loaded["parquet.tool"]
  package.loaded["parquet.tool"] = {
    probe = function(options)
      expect(options.refresh == true, "production health adapter did not refresh")
      return {
        errors = {},
        ok = true,
        pyarrow = {
          ok = true,
          path = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
          version = "25.0.0",
        },
        uv = { ok = true, path = "/usr/bin/uv", version = "0.11.6" },
        viewer = { ok = true, path = "/tools/visidata/bin/vd", version = "3.4" },
      }
    end,
  }
  pcall(vim.api.nvim_del_augroup_by_name, "dotfiles-parquet-viewer")
  local ok, detail = pcall(health_module.check)
  package.loaded["parquet.tool"] = previous_tool
  expect(ok, "deleted runtime autocmd group raised: " .. tostring(detail))
end

print("parquet health assertions: ok")
