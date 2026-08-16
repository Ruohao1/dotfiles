local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local function eq(actual, expected, message)
  expect(
    vim.deep_equal(actual, expected),
    string.format(
      "%s\nexpected: %s\nactual: %s",
      message,
      vim.inspect(expected),
      vim.inspect(actual)
    )
  )
end

local function exact_keys(value, expected, message)
  local actual = vim.tbl_keys(value)
  table.sort(actual)
  expected = vim.deepcopy(expected)
  table.sort(expected)
  eq(actual, expected, message)
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

package.loaded["notebook.python"] = nil
local python = require("notebook.python")

exact_keys(
  python,
  { "_test", "bootstrap", "paths", "python3_host_prog", "setup" },
  "module exports"
)

local function stdpath(kind)
  return ({
    cache = "/cache/nvim",
    config = "/cfg/nvim",
    data = "/data/nvim",
  })[kind]
end

local calls = {
  commands = {},
  notifications = {},
  system = {},
  user_commands = {},
}
local environment = { JUPYTER_PATH = "/existing/jupyter" }
local provider
local command_exists = false

local runtime = python._test.new({
  stdpath = stdpath,
  executable = function(command)
    return command == "uv" and 1 or 0
  end,
  system = function(command, options)
    calls.system[#calls.system + 1] = {
      command = vim.deepcopy(command),
      options = vim.deepcopy(options),
    }
    return {
      wait = function()
        return { code = 0, signal = 0, stdout = "", stderr = "" }
      end,
    }
  end,
  command = function(command)
    calls.commands[#calls.commands + 1] = command
  end,
  notify = function(message, level)
    calls.notifications[#calls.notifications + 1] = { message = message, level = level }
  end,
  env = environment,
  set_python3_host_prog = function(path)
    provider = path
  end,
  command_exists = function(name)
    expect(name == "NotebookBootstrap", "setup checked an unexpected user command")
    return command_exists
  end,
  create_user_command = function(name, callback, options)
    calls.user_commands[#calls.user_commands + 1] = {
      callback = callback,
      name = name,
      options = vim.deepcopy(options),
    }
    command_exists = true
  end,
  levels = { ERROR = 1, INFO = 2 },
})

local paths = runtime.paths()
eq(paths, {
  environment = "/data/nvim/notebook-python",
  jupyter = "/data/nvim/notebook-python/bin/jupyter",
  jupyter_root = "/cache/nvim/jupyter",
  jupytext = "/data/nvim/notebook-python/bin/jupytext",
  project = "/cfg/nvim/python",
  python = "/data/nvim/notebook-python/bin/python",
}, "editor runtime paths")
expect(runtime.python3_host_prog() == paths.python, "Python provider path is wrong")

runtime.setup()
expect(provider == paths.python, "Python provider was not configured")
expect(
  environment.JUPYTER_PATH == "/cache/nvim/jupyter:/existing/jupyter",
  "private Jupyter root was not prepended"
)
expect(#calls.system == 0, "setup must not download or synchronize dependencies")
eq(#calls.user_commands, 1, "setup creates the bootstrap command")
eq(calls.user_commands[1].name, "NotebookBootstrap", "bootstrap command name")
eq(calls.user_commands[1].options, {
  desc = "Install the Neovim notebook Python environment",
  nargs = 0,
}, "bootstrap command options")

runtime.setup()
expect(
  environment.JUPYTER_PATH == "/cache/nvim/jupyter:/existing/jupyter",
  "repeated setup duplicated the private Jupyter root"
)
eq(#calls.user_commands, 1, "bootstrap command registration is idempotent")

local callback_results = {}
local succeeded = runtime.bootstrap(function(ok)
  callback_results[#callback_results + 1] = ok
end)
expect(succeeded, "successful bootstrap returned false")
eq(callback_results, { true }, "successful bootstrap callback")
eq(#calls.system, 1, "bootstrap runs uv exactly once")
eq(calls.system[1], {
  command = {
    "uv",
    "sync",
    "--frozen",
    "--no-dev",
    "--no-install-project",
    "--project",
    "/cfg/nvim/python",
  },
  options = {
    env = { UV_PROJECT_ENVIRONMENT = "/data/nvim/notebook-python" },
    text = true,
  },
}, "bootstrap uv invocation")
eq(calls.commands, { "UpdateRemotePlugins" }, "remote-plugin manifest refresh")
eq(calls.notifications, {
  { message = "Notebook Python environment is ready", level = 2 },
}, "successful bootstrap diagnostic")

calls.user_commands[1].callback()
eq(#calls.system, 2, "NotebookBootstrap invokes the explicit bootstrap")

local missing_notifications = {}
local missing_system_calls = 0
local missing = python._test.new({
  stdpath = stdpath,
  executable = function()
    return 0
  end,
  system = function()
    missing_system_calls = missing_system_calls + 1
  end,
  command = function()
    error("missing-uv bootstrap must not refresh remote plugins")
  end,
  notify = function(message, level)
    missing_notifications[#missing_notifications + 1] = { message = message, level = level }
  end,
  env = {},
  set_python3_host_prog = function() end,
  command_exists = function()
    return true
  end,
  create_user_command = function() end,
  levels = { ERROR = 1, INFO = 2 },
})

local missing_callback
expect(not missing.bootstrap(function(ok)
  missing_callback = ok
end), "missing uv bootstrap returned true")
expect(missing_callback == false, "missing uv callback did not report failure")
expect(missing_system_calls == 0, "missing uv bootstrap tried to run a process")
eq(#missing_notifications, 1, "missing uv diagnostic count")
expect(
  missing_notifications[1].message:find("uv 0.11.6", 1, true),
  "missing uv diagnostic lacks the version floor"
)

local failed_commands = {}
local failed_notifications = {}
local failed = python._test.new({
  stdpath = stdpath,
  executable = function()
    return 1
  end,
  system = function()
    return {
      wait = function()
        return { code = 2, signal = 0, stdout = "", stderr = "resolution failed\n" }
      end,
    }
  end,
  command = function(command)
    failed_commands[#failed_commands + 1] = command
  end,
  notify = function(message, level)
    failed_notifications[#failed_notifications + 1] = { message = message, level = level }
  end,
  env = {},
  set_python3_host_prog = function() end,
  command_exists = function()
    return true
  end,
  create_user_command = function() end,
  levels = { ERROR = 1, INFO = 2 },
})

local failed_callback
expect(not failed.bootstrap(function(ok)
  failed_callback = ok
end), "failed uv bootstrap returned true")
expect(failed_callback == false, "failed uv callback did not report failure")
eq(failed_commands, {}, "failed uv bootstrap refreshed remote plugins")
eq(failed_notifications, {
  { message = "Notebook bootstrap failed: resolution failed", level = 1 },
}, "failed uv diagnostic")

print("notebook Python assertions: ok")
