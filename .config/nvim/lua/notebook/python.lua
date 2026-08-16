local M = {}

local function nonempty(value)
  if type(value) ~= "string" then
    return nil
  end

  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function prepend_path(current, entry)
  if not current or current == "" then
    return entry
  end

  for component in current:gmatch("[^:]+") do
    if component == entry then
      return current
    end
  end

  return entry .. ":" .. current
end

local function new(dependencies)
  local function paths()
    local environment = dependencies.stdpath("data") .. "/notebook-python"

    return {
      project = dependencies.stdpath("config") .. "/python",
      environment = environment,
      python = environment .. "/bin/python",
      jupytext = environment .. "/bin/jupytext",
      jupyter = environment .. "/bin/jupyter",
      jupyter_root = dependencies.stdpath("cache") .. "/jupyter",
    }
  end

  local function python3_host_prog()
    return paths().python
  end

  local function bootstrap(callback)
    callback = callback or function() end

    local function finish(ok)
      callback(ok)
      return ok
    end

    if dependencies.executable("uv") ~= 1 then
      dependencies.notify(
        "Notebook bootstrap requires uv 0.11.6 or newer; run the dotfiles bootstrap first",
        dependencies.levels.ERROR
      )
      return finish(false)
    end

    local runtime_paths = paths()
    local process_ok, process = pcall(dependencies.system, {
      "uv",
      "sync",
      "--frozen",
      "--no-dev",
      "--no-install-project",
      "--project",
      runtime_paths.project,
    }, {
      text = true,
      env = { UV_PROJECT_ENVIRONMENT = runtime_paths.environment },
    })

    if not process_ok then
      dependencies.notify(
        "Notebook bootstrap failed: " .. tostring(process),
        dependencies.levels.ERROR
      )
      return finish(false)
    end

    local wait_ok, result = pcall(function()
      return process:wait()
    end)

    if not wait_ok then
      dependencies.notify(
        "Notebook bootstrap failed: " .. tostring(result),
        dependencies.levels.ERROR
      )
      return finish(false)
    end

    if result.code ~= 0 or (result.signal and result.signal ~= 0) then
      local detail = nonempty(result.stderr) or nonempty(result.stdout) or "unknown uv error"
      dependencies.notify("Notebook bootstrap failed: " .. detail, dependencies.levels.ERROR)
      return finish(false)
    end

    local refresh_ok, refresh_error = pcall(dependencies.command, "UpdateRemotePlugins")
    if not refresh_ok then
      dependencies.notify(
        "Notebook bootstrap failed while refreshing remote plugins: " .. tostring(refresh_error),
        dependencies.levels.ERROR
      )
      return finish(false)
    end

    dependencies.notify("Notebook Python environment is ready", dependencies.levels.INFO)
    return finish(true)
  end

  local function setup()
    local runtime_paths = paths()
    dependencies.set_python3_host_prog(runtime_paths.python)
    dependencies.env.JUPYTER_PATH =
      prepend_path(dependencies.env.JUPYTER_PATH, runtime_paths.jupyter_root)

    if not dependencies.command_exists("NotebookBootstrap") then
      dependencies.create_user_command("NotebookBootstrap", function()
        bootstrap()
      end, {
        nargs = 0,
        desc = "Install the Neovim notebook Python environment",
      })
    end
  end

  return {
    paths = paths,
    python3_host_prog = python3_host_prog,
    setup = setup,
    bootstrap = bootstrap,
  }
end

local runtime = new({
  stdpath = function(kind)
    return vim.fn.stdpath(kind)
  end,
  executable = function(command)
    return vim.fn.executable(command)
  end,
  system = function(command, options)
    return vim.system(command, options)
  end,
  command = function(command)
    vim.cmd(command)
  end,
  notify = function(message, level)
    vim.notify(message, level)
  end,
  env = vim.env,
  set_python3_host_prog = function(path)
    vim.g.python3_host_prog = path
  end,
  command_exists = function(name)
    return vim.fn.exists(":" .. name) == 2
  end,
  create_user_command = function(name, callback, options)
    vim.api.nvim_create_user_command(name, callback, options)
  end,
  levels = vim.log.levels,
})

M.paths = runtime.paths
M.python3_host_prog = runtime.python3_host_prog
M.setup = runtime.setup
M.bootstrap = runtime.bootstrap
M._test = { new = new }

return M
