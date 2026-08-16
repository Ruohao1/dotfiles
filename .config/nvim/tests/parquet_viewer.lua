local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local function eq(actual, expected, message)
  expect(vim.deep_equal(actual, expected), message .. "\n" .. vim.inspect({ actual, expected }))
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)
local viewer = require("parquet.viewer")

local function fixture(overrides)
  local state = {
    alternate = 1,
    autocmds = {},
    buffers = { [1] = true, [2] = true },
    deleted = {},
    metadata = {},
    next_buffer = 20,
    notifications = {},
    started = {},
    stopped = {},
    windows = { [10] = 2 },
    wipes = {},
  }
  local deps = {
    abspath = function(path)
      return path:sub(1, 1) == "/" and path or "/work/" .. path
    end,
    alternate_buffer = function()
      return state.alternate
    end,
    buffer_valid = function(bufnr)
      return state.buffers[bufnr] == true
    end,
    create_augroup = function(name, options)
      eq({ name, options }, { "dotfiles-parquet-viewer", { clear = true } }, "augroup")
      return 77
    end,
    create_autocmd = function(event, options)
      state.autocmds[#state.autocmds + 1] = { event = event, options = options }
    end,
    create_buffer = function()
      local bufnr = state.next_buffer
      state.next_buffer = state.next_buffer + 1
      state.buffers[bufnr] = true
      return bufnr
    end,
    current_window = function()
      return 10
    end,
    delete_buffer = function(bufnr)
      state.deleted[#state.deleted + 1] = bufnr
      state.buffers[bufnr] = nil
      if state.wipes[bufnr] then
        state.wipes[bufnr]()
      end
    end,
    dirname = vim.fs.dirname,
    exiting = function()
      return false
    end,
    executable = function()
      return 1
    end,
    file_readable = function()
      return true
    end,
    find_windows = function(bufnr)
      local result = {}
      for winid, visible in pairs(state.windows) do
        if visible == bufnr then
          result[#result + 1] = winid
        end
      end
      return result
    end,
    levels = { ERROR = 1, WARN = 2 },
    normalize = vim.fs.normalize,
    notify = function(message, level)
      state.notifications[#state.notifications + 1] = { level = level, message = message }
    end,
    on_wipe = function(bufnr, callback)
      state.wipes[bufnr] = callback
    end,
    schedule = function(callback)
      callback()
    end,
    set_metadata = function(bufnr, value)
      state.metadata[bufnr] = vim.deepcopy(value)
    end,
    set_window_buffer = function(winid, bufnr)
      state.windows[winid] = bufnr
    end,
    start_insert = function(winid)
      state.insert_window = winid
    end,
    start_terminal = function(winid, bufnr, command, cwd, environment, on_exit)
      state.windows[winid] = bufnr
      state.started[#state.started + 1] = {
        bufnr = bufnr,
        command = vim.deepcopy(command),
        cwd = cwd,
        environment = vim.deepcopy(environment),
        on_exit = on_exit,
        winid = winid,
      }
      return 55
    end,
    stat = function()
      return { type = "file" }
    end,
    stop_job = function(job)
      state.stopped[#state.stopped + 1] = job
    end,
    viewer = function()
      return "/tools/visidata/bin/vd"
    end,
    window_buffer = function(winid)
      return state.windows[winid]
    end,
    window_valid = function(winid)
      return state.windows[winid] ~= nil
    end,
  }
  if type(overrides) == "function" then
    overrides = overrides(state)
  end
  for key, value in pairs(overrides or {}) do
    deps[key] = value
  end
  return viewer._test.new(deps), state
end

local function failure_fixture(case)
  return fixture(function(state)
    local overrides = {}
    if case.stat == false then
      overrides.stat = function()
        return nil
      end
    elseif type(case.stat) == "table" then
      overrides.stat = function()
        return vim.deepcopy(case.stat)
      end
    end
    if case.readable == false then
      overrides.file_readable = function()
        return false
      end
    end
    if case.tool_error then
      overrides.viewer = function()
        return nil, case.tool_error .. "; run the dotfiles bootstrap"
      end
    end
    if case.terminal_status then
      overrides.start_terminal = function(winid, bufnr)
        state.windows[winid] = bufnr
        return case.terminal_status
      end
    elseif case.terminal_error then
      overrides.start_terminal = function(winid, bufnr)
        if not case.before_swap then
          state.windows[winid] = bufnr
        end
        error(case.terminal_error)
      end
    end
    return overrides
  end)
end

do
  local runtime, state = fixture()
  expect(runtime.open(2, "/work/data set/-'quoted';$(literal).parquet"), "open failed")
  local terminal = state.started[1].bufnr
  eq(state.started[1].command, {
    "/tools/visidata/bin/vd",
    "--readonly",
    "/work/data set/-'quoted';$(literal).parquet",
  }, "safe argument vector")
  expect(state.started[1].cwd == "/work/data set", "viewer cwd")
  eq(state.started[1].environment, {
    PYTHONHOME = "",
    PYTHONNOUSERSITE = "1",
    PYTHONPATH = "",
    PYTHONDONTWRITEBYTECODE = "1",
  }, "isolated viewer environment")
  eq(state.metadata[terminal], {
    job = 55,
    path = "/work/data set/-'quoted';$(literal).parquet",
    readonly = true,
    return_buffer = 1,
  }, "terminal metadata")
  expect(state.buffers[2] == nil, "Parquet placeholder survived")
  expect(state.windows[10] == terminal, "terminal did not replace current window")
  expect(state.insert_window == 10, "terminal did not enter insert mode")

  state.started[1].on_exit(0)
  expect(state.windows[10] == 1, "previous buffer was not restored")
  expect(state.buffers[terminal] == nil, "exited terminal survived")
  expect(#state.notifications == 0, "normal exit notified")
end

for _, case in ipairs({
  { name = "unnamed", path = "", needle = "local" },
  { name = "URL", path = "https://example.test/data.parquet", needle = "local" },
  { name = "wrong extension", path = "/work/data.PARQUET", needle = ".parquet" },
  { name = "missing", stat = false, needle = "does not exist" },
  { name = "directory", stat = { type = "directory" }, needle = "regular file" },
  { name = "special file", stat = { type = "fifo" }, needle = "regular file" },
  { name = "unreadable", readable = false, needle = "not readable" },
  { name = "missing tool", tool_error = "managed viewer missing", needle = "dotfiles bootstrap" },
  { name = "terminal failure", terminal_status = -1, needle = "could not start" },
  { name = "terminal exception", terminal_error = "spawn exploded", needle = "spawn exploded" },
  {
    name = "terminal exception before window swap",
    before_swap = true,
    terminal_error = "window swap exploded",
    needle = "window swap exploded",
  },
}) do
  local runtime, state = failure_fixture(case)
  local requested = case.path
  if requested == nil then
    requested = "/work/data.parquet"
  end
  expect(not runtime.open(2, requested), case.name .. " passed")
  expect(state.windows[10] == 1, case.name .. " did not restore")
  expect(state.buffers[2] == nil, case.name .. " placeholder survived")
  expect(state.notifications[#state.notifications].message:find(case.needle, 1, true), case.name)
end

do
  local runtime, state = fixture()
  runtime.open(2, "/work/data.parquet")
  local terminal = state.started[1].bufnr
  state.windows[10] = 1
  state.started[1].on_exit(9)
  expect(state.windows[10] == 1, "exit replaced a newer buffer")
  expect(state.buffers[terminal] == nil, "hidden exited terminal survived")
  expect(state.notifications[1].message:find("status 9", 1, true), "nonzero exit was not reported")
end

do
  local runtime, state = fixture({
    exiting = function()
      return true
    end,
  })
  runtime.open(2, "/work/data.parquet")
  state.started[1].on_exit(9)
  expect(#state.notifications == 0, "Neovim shutdown reported a viewer exit")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return {}
  end)
  expect(runtime.open(2, "/work/data.parquet"), "open without an alternate buffer failed")
  local terminal = state.started[1].bufnr
  expect(state.metadata[terminal].return_buffer == 20, "scratch return buffer was not recorded")
  state.started[1].on_exit(0)
  expect(state.windows[10] == 20, "scratch return buffer was not restored")
end

do
  local runtime, state = fixture()
  runtime.open(2, "/work/data.parquet")
  local terminal = state.started[1].bufnr
  state.buffers[1] = nil
  state.started[1].on_exit(0)
  expect(state.windows[10] == 21, "deleted return buffer did not fall back to a scratch buffer")
  expect(state.buffers[21], "fallback scratch buffer is invalid")
  expect(state.buffers[terminal] == nil, "terminal survived fallback restoration")
end

do
  local runtime, state = fixture()
  runtime.open(2, "/work/data.parquet")
  local terminal = state.started[1].bufnr
  state.windows[10] = nil
  state.started[1].on_exit(0)
  expect(state.buffers[terminal] == nil, "closed-window terminal survived")
  expect(#state.notifications == 0, "closed-window cleanup notified")
end

do
  local runtime, state = fixture()
  runtime.open(2, "/work/data.parquet")
  local terminal = state.started[1].bufnr
  state.windows[10] = 1
  state.windows[11] = terminal
  state.started[1].on_exit(0)
  expect(state.buffers[terminal], "moved terminal was deleted")
  expect(state.windows[11] == terminal, "moved terminal window changed")
end

do
  local runtime, state = fixture()
  runtime.open(2, "/work/data.parquet")
  local terminal = state.started[1].bufnr
  state.wipes[terminal]()
  eq(state.stopped, { 55 }, "buffer wipe stopped the wrong job")
  state.started[1].on_exit(143)
  expect(#state.notifications == 0, "wiped viewer exit notified twice")
end

do
  local runtime, state = fixture()
  runtime.setup()
  runtime.setup()
  expect(#state.autocmds == 1, "setup was not idempotent")
  expect(state.autocmds[1].event == "BufReadCmd", "wrong event")
  expect(state.autocmds[1].options.pattern == "*.parquet", "wrong pattern")
end

do
  local literal = "/work/$PARQUET_LITERAL_TEST.parquet"
  local runtime, state = fixture(function(current)
    return {
      normalize = function(path, options)
        current.normalize_options = vim.deepcopy(options)
        if not options or options.expand_env ~= false then
          return path:gsub("%$PARQUET_LITERAL_TEST", "expanded")
        end
        return path
      end,
      stat = function(path)
        current.stat_path = path
        return { type = "file" }
      end,
    }
  end)
  expect(runtime.open(2, literal), "literal environment-like filename failed")
  eq(state.normalize_options, { expand_env = false }, "normalization expanded environment names")
  expect(state.stat_path == literal, "literal environment-like filename changed")
  expect(state.started[1].command[3] == literal, "spawn path expanded an environment name")
end

for _, case in ipairs({
  {
    name = "normalizer exception",
    normalize = function()
      error("normalize exploded")
    end,
  },
  { name = "relative normalized path", normalized = "relative/data.parquet" },
  { name = "control-bearing normalized path", normalized = "/work/data\n.parquet" },
  { name = "non-string normalized path", normalized = {} },
}) do
  local runtime, state = fixture({
    normalize = case.normalize or function()
      return case.normalized
    end,
  })
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped open()")
  expect(not opened, case.name .. " passed")
  expect(#state.started == 0, case.name .. " reached terminal startup")
  expect(#state.notifications == 1, case.name .. " did not notify exactly once")
  expect(
    state.notifications[1].message:find("safe absolute local", 1, true),
    case.name .. " reported the wrong error"
  )
end

for _, case in ipairs({
  { name = "relative viewer", viewer_path = "tools/visidata/bin/vd" },
  { name = "control-bearing viewer", viewer_path = "/tools/visidata/bin/vd\n--option" },
  { name = "root viewer", viewer_path = "/" },
  { name = "non-string viewer", viewer_path = {} },
  {
    name = "non-executable viewer",
    viewer_path = "/tools/visidata/bin/vd",
    executable = function()
      return 0
    end,
  },
  {
    name = "viewer executable check exception",
    viewer_path = "/tools/visidata/bin/vd",
    executable = function()
      error("executable check exploded")
    end,
  },
  {
    name = "viewer resolver exception",
    viewer = function()
      error("viewer resolution exploded")
    end,
  },
}) do
  local runtime, state = fixture({
    executable = case.executable or function()
      return 1
    end,
    viewer = case.viewer or function()
      return case.viewer_path
    end,
  })
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped open()")
  expect(not opened, case.name .. " passed")
  expect(#state.started == 0, case.name .. " reached terminal startup")
  expect(#state.notifications == 1, case.name .. " did not notify exactly once")
  expect(
    state.notifications[1].message:find("viewer executable", 1, true),
    case.name .. " reported the wrong error"
  )
end

for _, before_swap in ipairs({ false, true }) do
  local runtime, state = fixture(function(current)
    return {
      set_metadata = function(bufnr, value)
        if not current.buffers[bufnr] then
          error("metadata received an invalid terminal buffer")
        end
        current.metadata[bufnr] = vim.deepcopy(value)
      end,
      start_terminal = function(winid, bufnr, command, cwd, environment, on_exit)
        current.started[#current.started + 1] = {
          bufnr = bufnr,
          command = vim.deepcopy(command),
          cwd = cwd,
          environment = vim.deepcopy(environment),
          on_exit = on_exit,
          winid = winid,
        }
        if not before_swap then
          current.windows[winid] = bufnr
        end
        on_exit(9)
        on_exit(7)
        if before_swap then
          current.windows[winid] = bufnr
        end
        return 55
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  local position = before_swap and "before" or "after"
  expect(called, "synchronous exit " .. position .. " swap escaped open()")
  expect(opened, "synchronous exit " .. position .. " swap rejected a started job")
  expect(state.windows[10] == 1, "synchronous exit " .. position .. " swap did not restore")
  expect(state.buffers[2] == nil, "synchronous exit " .. position .. " swap kept placeholder")
  expect(state.buffers[20] == nil, "synchronous exit " .. position .. " swap kept terminal")
  expect(#state.notifications == 1, "repeated synchronous exits did not notify exactly once")
  expect(state.notifications[1].message:find("status 9", 1, true), "first exit status was lost")
  expect(#state.stopped == 0, "an already-exited synchronous job was stopped")
end

do
  local runtime, state = fixture()
  expect(runtime.open(2, "/work/data.parquet"), "repeated-exit fixture failed to open")
  state.started[1].on_exit(9)
  state.started[1].on_exit(7)
  expect(#state.notifications == 1, "repeated asynchronous exits notified more than once")
  expect(
    state.notifications[1].message:find("status 9", 1, true),
    "first async exit status was lost"
  )
  expect(state.windows[10] == 1, "repeated asynchronous exit did not restore once")
  expect(state.buffers[state.started[1].bufnr] == nil, "repeated asynchronous exit kept terminal")
end

for _, case in ipairs({
  {
    name = "metadata setup",
    override = {
      set_metadata = function()
        error("metadata setup exploded")
      end,
    },
  },
  {
    name = "wipe-hook setup",
    override = {
      on_wipe = function()
        error("wipe-hook setup exploded")
      end,
    },
  },
  {
    name = "insert-mode setup",
    override = {
      start_insert = function()
        error("insert-mode setup exploded")
      end,
    },
  },
}) do
  local runtime, state = fixture(case.override)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " failure escaped open()")
  expect(not opened, case.name .. " failure returned success")
  expect(state.windows[10] == 1, case.name .. " failure did not restore")
  expect(state.buffers[2] == nil, case.name .. " failure kept placeholder")
  expect(state.buffers[20] == nil, case.name .. " failure kept terminal")
  eq(state.stopped, { 55 }, case.name .. " failure did not stop the live job once")
  expect(#state.notifications == 1, case.name .. " failure did not notify exactly once")
  expect(
    state.notifications[1].message:find(case.name, 1, true),
    case.name .. " failure reported the wrong stage"
  )
end

do
  local runtime, state = fixture(function(current)
    return {
      set_metadata = function()
        current.started[1].on_exit(4)
        error("metadata setup exploded after exit")
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "metadata failure after exit escaped open()")
  expect(not opened, "metadata failure after exit returned success")
  expect(state.windows[10] == 1, "metadata failure after exit did not restore")
  expect(state.buffers[2] == nil, "metadata failure after exit kept placeholder")
  expect(state.buffers[20] == nil, "metadata failure after exit kept terminal")
  expect(#state.stopped == 0, "metadata failure stopped an already-exited job")
  expect(#state.notifications == 1, "metadata failure after exit notified twice")
  expect(
    state.notifications[1].message:find("metadata setup", 1, true),
    "metadata failure after exit lost setup error"
  )
end

do
  local runtime, state = fixture(function(current)
    return {
      set_metadata = function()
        error("metadata setup exploded before stop")
      end,
      stop_job = function(job)
        current.stopped[#current.stopped + 1] = job
        current.started[1].on_exit(143)
        current.started[1].on_exit(143)
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "job-stop exit callback escaped open()")
  expect(not opened, "job-stop exit callback returned success")
  eq(state.stopped, { 55 }, "job-stop exit callback stopped more than once")
  expect(#state.notifications == 1, "job-stop exit callback notified more than once")
  expect(
    state.notifications[1].message:find("metadata setup", 1, true),
    "job-stop exit callback replaced setup error"
  )
end

do
  local runtime, state = fixture(function(current)
    return {
      start_terminal = function(winid, bufnr)
        current.windows[winid] = bufnr
        current.buffers[bufnr] = nil
        return 55
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "terminal wipe before job assignment escaped open()")
  expect(not opened, "terminal wipe before job assignment returned success")
  expect(state.windows[10] == 1, "terminal wipe before job assignment did not restore")
  expect(state.buffers[2] == nil, "terminal wipe before job assignment kept placeholder")
  eq(state.stopped, { 55 }, "terminal wipe before job assignment did not stop once")
  expect(#state.notifications == 1, "terminal wipe before job assignment did not notify once")
end

do
  local runtime, state = fixture(function(current)
    return {
      on_wipe = function(bufnr, callback)
        current.wipes[bufnr] = callback
        current.buffers[bufnr] = nil
        callback()
        callback()
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "terminal wipe during hook setup escaped open()")
  expect(not opened, "terminal wipe during hook setup returned success")
  expect(state.windows[10] == 1, "terminal wipe during hook setup did not restore")
  expect(state.buffers[2] == nil, "terminal wipe during hook setup kept placeholder")
  eq(state.stopped, { 55 }, "terminal wipe during hook setup did not stop once")
  expect(#state.notifications == 1, "terminal wipe during hook setup did not notify once")
end

do
  local attempts = 0
  local runtime, state = fixture({
    create_augroup = function()
      attempts = attempts + 1
      if attempts == 1 then
        error("augroup registration exploded")
      end
      return 77
    end,
  })
  local first_ok = pcall(runtime.setup)
  expect(not first_ok, "failed augroup registration did not throw")
  expect(pcall(runtime.setup), "augroup registration was not retryable")
  expect(pcall(runtime.setup), "configured augroup setup did not stay idempotent")
  expect(attempts == 2, "successful augroup registration was repeated")
  expect(#state.autocmds == 1, "augroup retry did not register exactly one autocmd")
end

do
  local attempts = 0
  local runtime, state = fixture(function(current)
    return {
      create_augroup = function()
        current.autocmds = {}
        return 77
      end,
      create_autocmd = function(event, options)
        attempts = attempts + 1
        if attempts == 1 then
          error("autocmd registration exploded")
        end
        current.autocmds[#current.autocmds + 1] = { event = event, options = options }
      end,
    }
  end)
  local first_ok = pcall(runtime.setup)
  expect(not first_ok, "failed autocmd registration did not throw")
  expect(pcall(runtime.setup), "autocmd registration was not retryable")
  expect(pcall(runtime.setup), "configured autocmd setup did not stay idempotent")
  expect(attempts == 2, "successful autocmd registration was repeated")
  expect(#state.autocmds == 1, "autocmd retry did not register exactly one autocmd")
end

for _, case in ipairs({
  { name = "no terminal window swap", expected_window = 1 },
  { name = "unexpected window swap", unexpected_buffer = 99, expected_window = 99 },
}) do
  local runtime, state = fixture(function(current)
    if case.unexpected_buffer then
      current.buffers[case.unexpected_buffer] = true
    end
    return {
      start_terminal = function(winid)
        if case.unexpected_buffer then
          current.windows[winid] = case.unexpected_buffer
        end
        return 55
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped open()")
  expect(not opened, case.name .. " returned success")
  expect(state.windows[10] == case.expected_window, case.name .. " restored unsafely")
  expect(state.buffers[2] == nil, case.name .. " kept placeholder")
  expect(state.buffers[20] == nil, case.name .. " kept terminal")
  eq(state.stopped, { 55 }, case.name .. " did not stop the live job once")
  expect(#state.notifications == 1, case.name .. " did not notify exactly once")
  expect(
    state.notifications[1].message:find("current window", 1, true),
    case.name .. " reported the wrong failure"
  )
end

for _, case in ipairs({
  { name = "callback then exception before swap", before_swap = true },
  { name = "callback then exception after swap", before_swap = false },
  { name = "callback then invalid job", invalid_job = true },
}) do
  local runtime, state = fixture(function(current)
    return {
      start_terminal = function(winid, bufnr, _, _, _, on_exit)
        if not case.before_swap then
          current.windows[winid] = bufnr
        end
        on_exit(17)
        on_exit(19)
        if case.invalid_job then
          return -1
        end
        error(case.name)
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped open()")
  expect(not opened, case.name .. " returned success")
  expect(state.windows[10] == 1, case.name .. " did not restore")
  expect(state.buffers[2] == nil, case.name .. " kept placeholder")
  expect(state.buffers[20] == nil, case.name .. " kept terminal")
  expect(#state.stopped == 0, case.name .. " stopped an unassigned job")
  expect(#state.notifications == 1, case.name .. " did not notify exactly once")
  expect(
    state.notifications[1].message:find("could not start", 1, true),
    case.name .. " reported an exit instead of startup failure"
  )
end

do
  local alternate_calls = 0
  local viewer_calls = 0
  local runtime, state = fixture(function(current)
    current.buffers[99] = true
    current.windows[10] = 99
    return {
      alternate_buffer = function()
        alternate_calls = alternate_calls + 1
        return 1
      end,
      viewer = function()
        viewer_calls = viewer_calls + 1
        return "/tools/visidata/bin/vd"
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "stale placeholder ownership escaped open()")
  expect(not opened, "stale placeholder ownership returned success")
  expect(state.windows[10] == 99, "stale placeholder ownership replaced the current buffer")
  expect(state.buffers[2], "stale placeholder ownership deleted the supplied placeholder")
  expect(state.next_buffer == 20, "stale placeholder ownership allocated a buffer")
  expect(alternate_calls == 0, "stale placeholder ownership resolved a return buffer")
  expect(viewer_calls == 0, "stale placeholder ownership resolved the viewer")
  expect(#state.started == 0, "stale placeholder ownership started a terminal")
  expect(#state.notifications == 1, "stale placeholder ownership did not notify exactly once")
end

do
  local runtime, state = fixture({
    current_window = function()
      error("current window exploded")
    end,
  })
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "current-window exception escaped open()")
  expect(not opened, "current-window exception returned success")
  expect(state.buffers[2], "current-window exception deleted the supplied placeholder")
  expect(state.next_buffer == 20, "current-window exception allocated a buffer")
  expect(#state.started == 0, "current-window exception started a terminal")
  expect(#state.notifications == 1, "current-window exception did not notify exactly once")
end

for _, stage in ipairs({ "stat", "viewer" }) do
  local runtime, state = fixture(function(current)
    current.buffers[99] = true
    local overrides = {}
    if stage == "stat" then
      overrides.stat = function()
        current.windows[10] = 99
        return { type = "file" }
      end
    else
      overrides.viewer = function()
        current.windows[10] = 99
        return "/tools/visidata/bin/vd"
      end
    end
    return overrides
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, stage .. " ownership change escaped open()")
  expect(not opened, stage .. " ownership change returned success")
  expect(state.windows[10] == 99, stage .. " ownership change replaced the newer buffer")
  expect(state.buffers[2] == nil, stage .. " ownership change kept a hidden placeholder")
  expect(#state.started == 0, stage .. " ownership change started a terminal")
  expect(#state.notifications == 1, stage .. " ownership change did not notify exactly once")
end

for _, stage in ipairs({ "metadata", "wipe hook", "placeholder deletion", "start insert" }) do
  local runtime, state = fixture(function(current)
    current.buffers[99] = true
    local overrides = {}
    if stage == "metadata" then
      overrides.set_metadata = function(bufnr, value)
        current.metadata[bufnr] = vim.deepcopy(value)
        current.windows[10] = 99
      end
    elseif stage == "wipe hook" then
      overrides.on_wipe = function(bufnr, callback)
        current.wipes[bufnr] = callback
        current.windows[10] = 99
      end
    elseif stage == "placeholder deletion" then
      overrides.delete_buffer = function(bufnr)
        current.deleted[#current.deleted + 1] = bufnr
        current.buffers[bufnr] = nil
        if bufnr == 2 then
          current.windows[10] = 99
        end
        if current.wipes[bufnr] then
          current.wipes[bufnr]()
        end
      end
    else
      overrides.start_insert = function()
        current.windows[10] = 99
      end
    end
    return overrides
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, stage .. " ownership loss escaped open()")
  expect(not opened, stage .. " ownership loss returned success")
  expect(state.windows[10] == 99, stage .. " ownership loss replaced the newer buffer")
  expect(state.buffers[2] == nil, stage .. " ownership loss kept the placeholder")
  expect(state.buffers[20] == nil, stage .. " ownership loss kept the terminal")
  eq(state.stopped, { 55 }, stage .. " ownership loss did not stop exactly once")
  expect(#state.notifications == 1, stage .. " ownership loss did not notify exactly once")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return {}
  end)
  expect(runtime.open(2, "/work/data.parquet"), "owned-scratch close fixture failed")
  local terminal = state.started[1].bufnr
  state.windows[10] = nil
  state.started[1].on_exit(0)
  expect(state.buffers[20] == nil, "closed origin leaked the owned return scratch")
  expect(state.buffers[terminal] == nil, "closed origin kept a hidden exited terminal")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    current.buffers[99] = true
    return {}
  end)
  expect(runtime.open(2, "/work/data.parquet"), "owned-scratch wipe fixture failed")
  local terminal = state.started[1].bufnr
  state.windows[10] = 99
  state.buffers[terminal] = nil
  state.wipes[terminal]()
  expect(state.buffers[20] == nil, "user wipe leaked the owned return scratch")
  eq(state.stopped, { 55 }, "user wipe did not stop the viewer once")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    current.buffers[99] = true
    return {}
  end)
  expect(runtime.open(2, "/work/data.parquet"), "owned-scratch move fixture failed")
  local terminal = state.started[1].bufnr
  state.windows[10] = 99
  state.windows[11] = terminal
  state.started[1].on_exit(0)
  expect(state.buffers[20] == nil, "moved terminal exit leaked the owned return scratch")
  expect(state.buffers[terminal], "moved terminal exit deleted the visible terminal")
  expect(state.windows[11] == terminal, "moved terminal exit changed its new window")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return {
      set_window_buffer = function()
        error("restore set exploded")
      end,
    }
  end)
  expect(runtime.open(2, "/work/data.parquet"), "owned-scratch restore fixture failed")
  local terminal = state.started[1].bufnr
  state.started[1].on_exit(0)
  expect(state.buffers[20] == nil, "failed restore leaked the owned return scratch")
  expect(state.buffers[terminal], "failed restore deleted the still-visible terminal")
end

do
  local runtime, state = fixture({
    set_window_buffer = function()
      error("fallback set exploded")
    end,
  })
  expect(runtime.open(2, "/work/data.parquet"), "fallback-scratch restore fixture failed")
  local terminal = state.started[1].bufnr
  state.buffers[1] = nil
  state.started[1].on_exit(0)
  expect(state.buffers[21] == nil, "failed restore leaked its fallback scratch")
  expect(state.buffers[terminal], "failed fallback restore deleted the visible terminal")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    current.buffers[99] = true
    return {
      viewer = function()
        current.windows[10] = 99
        return "/tools/visidata/bin/vd"
      end,
    }
  end)
  expect(not runtime.open(2, "/work/data.parquet"), "validation ownership loss returned success")
  expect(state.windows[10] == 99, "validation ownership loss replaced the newer buffer")
  expect(state.buffers[20] == nil, "validation failure leaked the owned return scratch")
  expect(state.buffers[2] == nil, "validation failure kept the hidden placeholder")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    current.buffers[99] = true
    return {
      start_terminal = function(winid)
        current.windows[winid] = 99
        return 55
      end,
    }
  end)
  expect(not runtime.open(2, "/work/data.parquet"), "startup ownership loss returned success")
  expect(state.windows[10] == 99, "startup ownership loss replaced the newer buffer")
  expect(state.buffers[20] == nil, "startup failure leaked the owned return scratch")
  expect(state.buffers[21] == nil, "startup failure leaked the hidden terminal")
  eq(state.stopped, { 55 }, "startup ownership loss did not stop once")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return {}
  end)
  expect(not runtime.open(2, "/work/data.PARQUET"), "validation transfer returned success")
  expect(state.windows[10] == 20, "validation failure did not transfer the return scratch")
  expect(state.buffers[20], "validation failure deleted the transferred return scratch")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return {
      start_terminal = function(winid, bufnr)
        current.windows[winid] = bufnr
        return -1
      end,
    }
  end)
  expect(not runtime.open(2, "/work/data.parquet"), "startup transfer returned success")
  expect(state.windows[10] == 20, "startup failure did not transfer the return scratch")
  expect(state.buffers[20], "startup failure deleted the transferred return scratch")
  expect(state.buffers[21] == nil, "startup failure kept its hidden terminal")
end

do
  local runtime, state = fixture()
  expect(runtime.open(2, "/work/data.parquet"), "user-owned alternate fixture failed")
  state.windows[10] = nil
  state.started[1].on_exit(0)
  expect(state.buffers[1], "closed origin deleted a user-owned alternate")
end

do
  local runtime, state = fixture({
    alternate_buffer = function()
      error("alternate lookup exploded")
    end,
  })
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "alternate-buffer exception escaped open()")
  expect(not opened, "alternate-buffer exception returned success")
  expect(state.windows[10] == 2, "alternate-buffer exception changed the current buffer")
  expect(state.buffers[2], "alternate-buffer exception deleted the placeholder")
  expect(state.next_buffer == 20, "alternate-buffer exception allocated a buffer")
  expect(#state.started == 0, "alternate-buffer exception started a terminal")
  expect(#state.notifications == 1, "alternate-buffer exception did not notify once")
end

for _, case in ipairs({
  {
    name = "return-scratch create exception",
    create_buffer = function()
      error("return scratch exploded")
    end,
  },
  {
    name = "invalid return scratch",
    create_buffer = function()
      return "not-a-buffer"
    end,
  },
}) do
  local stat_calls = 0
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return {
      create_buffer = case.create_buffer,
      stat = function()
        stat_calls = stat_calls + 1
        return { type = "file" }
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped open()")
  expect(not opened, case.name .. " returned success")
  expect(state.windows[10] == 2, case.name .. " changed the current buffer")
  expect(state.buffers[2], case.name .. " deleted the placeholder")
  expect(stat_calls == 0, case.name .. " continued into file validation")
  expect(#state.started == 0, case.name .. " started a terminal")
  expect(#state.notifications == 1, case.name .. " did not notify once")
end

for _, case in ipairs({
  {
    name = "stat exception",
    override = {
      stat = function()
        error("stat exploded")
      end,
    },
  },
  {
    name = "invalid stat result",
    override = {
      stat = function()
        return 7
      end,
    },
  },
  {
    name = "readability exception",
    override = {
      file_readable = function()
        error("readability exploded")
      end,
    },
  },
  {
    name = "invalid readability result",
    override = {
      file_readable = function()
        return "yes"
      end,
    },
  },
}) do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return case.override
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped open()")
  expect(not opened, case.name .. " returned success")
  expect(state.windows[10] == 20, case.name .. " did not restore the owned scratch")
  expect(state.buffers[20], case.name .. " deleted the transferred scratch")
  expect(state.buffers[2] == nil, case.name .. " kept the placeholder")
  expect(#state.started == 0, case.name .. " started a terminal")
  expect(#state.notifications == 1, case.name .. " did not notify once")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    current.buffers[99] = true
    return {
      stat = function()
        current.windows[10] = 99
        error("stat exploded after ownership loss")
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "stat exception after ownership loss escaped open()")
  expect(not opened, "stat exception after ownership loss returned success")
  expect(state.windows[10] == 99, "stat exception after ownership loss replaced the newer buffer")
  expect(state.buffers[20] == nil, "stat exception after ownership loss leaked its scratch")
  expect(state.buffers[2] == nil, "stat exception after ownership loss kept the placeholder")
  expect(#state.started == 0, "stat exception after ownership loss started a terminal")
  expect(#state.notifications == 1, "stat exception after ownership loss did not notify once")
end

for _, case in ipairs({
  {
    name = "dirname exception",
    dirname = function()
      error("dirname exploded")
    end,
  },
  {
    name = "relative dirname",
    dirname = function()
      return "work"
    end,
  },
  {
    name = "control-bearing dirname",
    dirname = function()
      return "/work\nbad"
    end,
  },
  {
    name = "non-string dirname",
    dirname = function()
      return {}
    end,
  },
}) do
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return { dirname = case.dirname }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped open()")
  expect(not opened, case.name .. " returned success")
  expect(state.windows[10] == 20, case.name .. " did not restore the owned scratch")
  expect(state.buffers[20], case.name .. " deleted the transferred scratch")
  expect(state.next_buffer == 21, case.name .. " allocated a terminal before cwd validation")
  expect(#state.started == 0, case.name .. " started a terminal")
  expect(#state.notifications == 1, case.name .. " did not notify once")
end

for _, case in ipairs({ "exception", "invalid result" }) do
  local creates = 0
  local runtime, state = fixture(function(current)
    current.buffers[1] = nil
    return {
      create_buffer = function()
        creates = creates + 1
        if creates == 1 then
          current.buffers[20] = true
          current.next_buffer = 21
          return 20
        end
        if case == "exception" then
          error("terminal create exploded")
        end
        return "not-a-terminal"
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "terminal create " .. case .. " escaped open()")
  expect(not opened, "terminal create " .. case .. " returned success")
  expect(state.windows[10] == 20, "terminal create " .. case .. " did not restore scratch")
  expect(state.buffers[20], "terminal create " .. case .. " deleted transferred scratch")
  expect(state.buffers[2] == nil, "terminal create " .. case .. " kept placeholder")
  expect(#state.started == 0, "terminal create " .. case .. " started a job")
  expect(#state.notifications == 1, "terminal create " .. case .. " did not notify once")
end

do
  local runtime, state = fixture({
    dirname = function()
      return "/"
    end,
  })
  expect(runtime.open(2, "/data.parquet"), "root viewer cwd was rejected")
  expect(state.started[1].cwd == "/", "root viewer cwd changed")
end

for _, case in ipairs({
  {
    name = "throwing scheduler",
    schedule = function()
      error("scheduler exploded")
    end,
  },
  {
    name = "scheduler error return",
    schedule = function()
      return nil, "scheduler unavailable"
    end,
  },
  {
    name = "scheduler callback plus error",
    schedule = function(callback)
      callback()
      return nil, "scheduler reported after callback"
    end,
  },
}) do
  local runtime, state = fixture(function(current)
    return {
      schedule = case.schedule,
      start_terminal = function(winid, bufnr, command, cwd, environment, on_exit)
        current.windows[winid] = bufnr
        current.started[#current.started + 1] = {
          bufnr = bufnr,
          command = vim.deepcopy(command),
          cwd = cwd,
          environment = vim.deepcopy(environment),
          on_exit = on_exit,
          winid = winid,
        }
        on_exit(9)
        on_exit(7)
        return 55
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, case.name .. " escaped synchronous startup")
  expect(opened, case.name .. " rejected an exited started job")
  expect(state.windows[10] == 1, case.name .. " did not restore synchronously")
  expect(state.buffers[2] == nil, case.name .. " kept the placeholder")
  expect(state.buffers[20] == nil, case.name .. " kept the exited terminal")
  expect(#state.stopped == 0, case.name .. " stopped an already-exited job")
  expect(#state.notifications == 1, case.name .. " notified more than once")
  expect(state.notifications[1].message:find("status 9", 1, true), case.name .. " lost exit")
end

for _, case in ipairs({
  {
    name = "late throwing scheduler",
    schedule = function()
      error("late scheduler exploded")
    end,
  },
  {
    name = "late scheduler error return",
    schedule = function()
      return nil, "late scheduler unavailable"
    end,
  },
}) do
  local runtime, state = fixture({ schedule = case.schedule })
  expect(runtime.open(2, "/work/data.parquet"), case.name .. " fixture failed")
  local terminal = state.started[1].bufnr
  expect(pcall(state.started[1].on_exit, 0), case.name .. " escaped the terminal callback")
  expect(pcall(state.started[1].on_exit, 7), case.name .. " late duplicate escaped")
  expect(state.windows[10] == 1, case.name .. " did not restore")
  expect(state.buffers[terminal] == nil, case.name .. " kept the exited terminal")
  expect(#state.stopped == 0, case.name .. " stopped an already-exited job")
  expect(#state.notifications == 0, case.name .. " processed a late duplicate")
end

do
  local notify_calls = 0
  local runtime, state = fixture({
    notify = function()
      notify_calls = notify_calls + 1
      error("validation notifier exploded")
    end,
  })
  local called, opened = pcall(runtime.open, 2, "/work/data.PARQUET")
  expect(called, "validation notifier exception escaped open()")
  expect(not opened, "validation notifier exception returned success")
  expect(state.windows[10] == 1, "validation notifier exception did not restore")
  expect(state.buffers[2] == nil, "validation notifier exception kept placeholder")
  expect(#state.started == 0, "validation notifier exception started a terminal")
  expect(notify_calls == 1, "validation notifier exception retried notification")
end

do
  local notify_calls = 0
  local runtime, state = fixture(function(current)
    return {
      notify = function()
        notify_calls = notify_calls + 1
        error("startup notifier exploded")
      end,
      start_terminal = function(winid, bufnr)
        current.windows[winid] = bufnr
        return -1
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "startup notifier exception escaped open()")
  expect(not opened, "startup notifier exception returned success")
  expect(state.windows[10] == 1, "startup notifier exception did not restore")
  expect(state.buffers[2] == nil, "startup notifier exception kept placeholder")
  expect(state.buffers[20] == nil, "startup notifier exception kept terminal")
  expect(notify_calls == 1, "startup notifier exception retried notification")
end

do
  local notify_calls = 0
  local runtime, state = fixture(function(current)
    current.buffers[99] = true
    current.windows[10] = 99
    return {
      notify = function()
        notify_calls = notify_calls + 1
        error("stale notifier exploded")
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "stale notifier exception escaped open()")
  expect(not opened, "stale notifier exception returned success")
  expect(state.windows[10] == 99, "stale notifier exception replaced newer buffer")
  expect(state.buffers[2], "stale notifier exception deleted supplied placeholder")
  expect(notify_calls == 1, "stale notifier exception retried notification")
end

do
  local notify_calls = 0
  local runtime, state = fixture({
    notify = function()
      notify_calls = notify_calls + 1
      error("exit notifier exploded")
    end,
  })
  expect(runtime.open(2, "/work/data.parquet"), "exit notifier fixture failed")
  local terminal = state.started[1].bufnr
  expect(pcall(state.started[1].on_exit, 9), "exit notifier exception escaped callback")
  expect(state.windows[10] == 1, "exit notifier exception did not restore")
  expect(state.buffers[terminal] == nil, "exit notifier exception kept terminal")
  expect(#state.stopped == 0, "exit notifier exception stopped an exited job")
  expect(notify_calls == 1, "exit notifier exception retried warning")
end

do
  local runtime, state = fixture({
    exiting = function()
      error("shutdown probe exploded")
    end,
  })
  expect(runtime.open(2, "/work/data.parquet"), "shutdown-probe fixture failed")
  local terminal = state.started[1].bufnr
  expect(pcall(state.started[1].on_exit, 9), "shutdown-probe exception escaped callback")
  expect(state.windows[10] == 1, "shutdown-probe exception did not restore")
  expect(state.buffers[terminal] == nil, "shutdown-probe exception kept terminal")
  expect(#state.notifications == 1, "shutdown-probe exception suppressed or duplicated warning")
  expect(
    state.notifications[1].message:find("status 9", 1, true),
    "shutdown-probe exception lost status warning"
  )
end

do
  local runtime, state = fixture(function(current)
    current.buffers[99] = true
    return {
      create_buffer = function()
        local bufnr = current.next_buffer
        current.next_buffer = current.next_buffer + 1
        current.buffers[bufnr] = true
        current.windows[10] = 99
        return bufnr
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "terminal-allocation ownership loss escaped open()")
  expect(not opened, "terminal-allocation ownership loss returned success")
  expect(state.windows[10] == 99, "terminal allocation replaced the newer buffer")
  expect(state.buffers[2] == nil, "terminal-allocation ownership loss kept placeholder")
  expect(state.buffers[20] == nil, "terminal-allocation ownership loss leaked terminal")
  expect(#state.started == 0, "terminal-allocation ownership loss started a job")
  expect(#state.notifications == 1, "terminal-allocation ownership loss did not notify once")
end

do
  local runtime, state = fixture(function(current)
    return {
      delete_buffer = function(bufnr)
        current.deleted[#current.deleted + 1] = bufnr
        current.buffers[bufnr] = nil
        if bufnr == 2 then
          current.wipes[current.started[1].bufnr]()
        elseif current.wipes[bufnr] then
          current.wipes[bufnr]()
        end
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "placeholder-deletion wipe escaped open()")
  expect(not opened, "placeholder-deletion wipe returned success")
  expect(state.insert_window == nil, "placeholder-deletion wipe entered insert mode")
  expect(state.windows[10] == 1, "placeholder-deletion wipe did not restore")
  expect(state.buffers[2] == nil, "placeholder-deletion wipe kept placeholder")
  expect(state.buffers[20] == nil, "placeholder-deletion wipe kept terminal")
  eq(state.stopped, { 55 }, "placeholder-deletion wipe did not stop once")
  expect(#state.notifications == 1, "placeholder-deletion wipe did not notify once")
end

do
  local runtime, state = fixture(function(current)
    current.buffers[99] = true
    return {
      start_terminal = function(winid, bufnr, _, _, _, on_exit)
        current.windows[winid] = bufnr
        on_exit(0)
        current.windows[winid] = 99
        return 55
      end,
    }
  end)
  local called, opened = pcall(runtime.open, 2, "/work/data.parquet")
  expect(called, "pending-exit ownership loss escaped open()")
  expect(not opened, "pending-exit ownership loss returned success")
  expect(state.windows[10] == 99, "pending-exit ownership loss replaced the newer buffer")
  expect(state.buffers[2] == nil, "pending-exit ownership loss kept placeholder")
  expect(state.buffers[20] == nil, "pending-exit ownership loss kept terminal")
  expect(#state.stopped == 0, "pending-exit ownership loss stopped an exited job")
  expect(#state.notifications == 1, "pending-exit ownership loss did not notify once")
end

do
  local previous_viewer_module = package.loaded["parquet.viewer"]
  local previous_tool_module = package.loaded["parquet.tool"]
  local previous_notify = vim.notify
  local winid = vim.api.nvim_get_current_win()
  local original_buffer = vim.api.nvim_win_get_buf(winid)
  local original_buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    original_buffers[bufnr] = true
  end

  local temp_base = vim.fn.tempname()
  local parquet_path = temp_base .. ".parquet"
  local executable_path = temp_base .. "-viewer"
  local group
  local notifications = {}

  local function cleanup()
    if group then
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end
    package.loaded["parquet.viewer"] = previous_viewer_module
    package.loaded["parquet.tool"] = previous_tool_module
    vim.notify = previous_notify

    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_buf_is_valid(original_buffer) then
      pcall(vim.api.nvim_win_set_buf, winid, original_buffer)
    end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if not original_buffers[bufnr] then
        local job_ok, job = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
        if job_ok and type(job) == "number" and job > 0 then
          pcall(vim.fn.jobstop, job)
        end
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    pcall(vim.uv.fs_unlink, parquet_path)
    pcall(vim.uv.fs_unlink, executable_path)
  end

  local ok, failure = xpcall(function()
    expect(vim.fn.writefile({ "PAR1" }, parquet_path, "b") == 0, "temporary Parquet write failed")
    expect(
      vim.fn.writefile({ "#!/bin/sh", "exec sleep 30" }, executable_path) == 0,
      "temporary viewer write failed"
    )
    local chmod_ok, chmod_error = vim.uv.fs_chmod(executable_path, 493)
    expect(chmod_ok, "temporary viewer chmod failed: " .. tostring(chmod_error))

    vim.notify = function(message, level)
      notifications[#notifications + 1] = { level = level, message = message }
    end
    package.loaded["parquet.tool"] = {
      viewer = function()
        return executable_path
      end,
    }
    package.loaded["parquet.viewer"] = nil
    local real_viewer = require("parquet.viewer")

    local replacement = vim.api.nvim_create_buf(true, false)
    local replacement_lines = { "keep this exact line", "and this second line" }
    vim.api.nvim_buf_set_lines(replacement, 0, -1, false, replacement_lines)
    vim.bo[replacement].modified = false
    local placeholder = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(winid, placeholder)

    local buffers_before_open = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      buffers_before_open[bufnr] = true
    end

    local entered = 0
    local entered_buffer
    group = vim.api.nvim_create_augroup("dotfiles-parquet-viewer-real-adapter-test", {
      clear = true,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      once = true,
      callback = function(args)
        entered = entered + 1
        entered_buffer = args.buf
        vim.api.nvim_win_set_buf(winid, replacement)
      end,
    })

    expect(not real_viewer.open(placeholder, parquet_path), "real adapter race returned success")
    expect(entered == 1, "real adapter race did not trigger exactly one BufEnter")
    expect(
      entered_buffer ~= placeholder and entered_buffer ~= replacement,
      "real adapter race entered the wrong buffer"
    )
    expect(vim.api.nvim_win_get_buf(winid) == replacement, "real adapter replaced the newer buffer")
    expect(vim.api.nvim_buf_is_valid(replacement), "real adapter deleted the replacement buffer")
    eq({
      buftype = vim.bo[replacement].buftype,
      lines = vim.api.nvim_buf_get_lines(replacement, 0, -1, false),
    }, {
      buftype = "",
      lines = replacement_lines,
    }, "real adapter terminalized or corrupted the replacement buffer")
    expect(not vim.api.nvim_buf_is_valid(placeholder), "real adapter kept the hidden placeholder")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      expect(buffers_before_open[bufnr], "real adapter leaked a session-owned buffer")
    end
    expect(#notifications == 1, "real adapter race did not notify exactly once")
    expect(
      notifications[1].message:find("Parquet viewer failed", 1, true),
      "real adapter race reported the wrong notification"
    )
  end, debug.traceback)

  cleanup()
  if not ok then
    error(failure, 0)
  end
end

print("parquet viewer assertions: ok")
