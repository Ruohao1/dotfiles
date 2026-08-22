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

package.loaded["data_query.workflow"] = nil
local workflow_module = require("data_query.workflow")

do
  if vim.uv.os_uname().sysname == "Linux" then
    local boot_id, boot_error = workflow_module._test.read_boot_id()
    expect(
      type(boot_id) == "string" and boot_id:match("^[0-9a-f-]+$") ~= nil,
      "production boot-id adapter failed on procfs: " .. tostring(boot_error)
    )
    local ticks, ticks_error = workflow_module._test.process_start_ticks(vim.uv.os_getpid())
    expect(
      type(ticks) == "number" and ticks > 0,
      "production process-stat adapter failed on procfs: " .. tostring(ticks_error)
    )
  end
end

do
  local winid = vim.api.nvim_get_current_win()
  local original = vim.api.nvim_get_current_buf()
  local group = vim.api.nvim_create_augroup("data-query-production-reopen-test", { clear = true })
  local path = "/tmp/data-query-production-reopen.parquet"
  local terminal
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "*.parquet",
    callback = function(args)
      terminal = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(terminal, "term://data-query-production-reopen")
      vim.api.nvim_open_term(terminal, {})
      vim.b[terminal].dotfiles_parquet_viewer = {
        job = 77,
        path = path,
        readonly = true,
        return_buffer = original,
      }
      vim.api.nvim_win_set_buf(winid, terminal)
      if vim.api.nvim_buf_is_valid(args.buf) then
        vim.api.nvim_buf_delete(args.buf, { force = true })
      end
    end,
  })
  local reopened_ok, reopened = pcall(workflow_module._test.reopen_file, winid, path)
  vim.api.nvim_win_set_buf(winid, original)
  vim.api.nvim_del_augroup_by_id(group)
  if terminal and vim.api.nvim_buf_is_valid(terminal) then
    vim.api.nvim_buf_delete(terminal, { force = true })
  end
  expect(
    reopened_ok and reopened == terminal,
    "production Parquet reopen lost its replacement buffer: "
      .. vim.inspect({ ok = reopened_ok, reopened = reopened, terminal = terminal })
  )
end

do
  local winid = vim.api.nvim_get_current_win()
  local original = vim.api.nvim_get_current_buf()
  local scratch = vim.api.nvim_create_buf(false, true)
  local fallback = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(winid, scratch)
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = scratch,
    once = true,
    callback = function()
      error("production-like scratch leave failure")
    end,
  })
  local switched = pcall(vim.api.nvim_win_set_buf, winid, fallback)
  expect(not switched, "production-like BufLeave failure did not reject the buffer switch")
  expect(
    vim.api.nvim_win_get_buf(winid) == scratch,
    "production-like BufLeave failure moved the scratch window"
  )
  vim.api.nvim_win_set_buf(winid, original)
  vim.api.nvim_buf_delete(scratch, { force = true })
  vim.api.nvim_buf_delete(fallback, { force = true })
end

do
  local fields = { "S" }
  for index = 2, 19 do
    fields[index] = tostring(index)
  end
  fields[20] = "987654"
  expect(
    workflow_module._test.parse_process_stat(
      "4242 (worker name with ) characters) " .. table.concat(fields, " ")
    ) == 987654,
    "process start ticks were not parsed after the final right parenthesis"
  )
  expect(workflow_module._test.parse_process_stat("malformed") == nil, "malformed process stat")
end

do
  local sanitized = workflow_module._test.sanitize_diagnostic(
    "tab\tline\ncarriage\rzero\0other\1" .. string.rep("x", 5000)
  )
  expect(#sanitized == 4096, "diagnostic cap is not exactly 4096 bytes")
  expect(sanitized:find("tab\tline\n", 1, true) == 1, "diagnostic lost tab or newline")
  for index = 1, #sanitized do
    local byte = sanitized:byte(index)
    expect(
      byte >= 32 or byte == 9 or byte == 10,
      "diagnostic retained a control byte at " .. tostring(index)
    )
  end
end

local source_metadata = {
  dev = 2050,
  ino = 12345,
  mode = 33188,
  mtime = { nsec = 456789000, sec = 1787414400 },
  size = 2048,
  type = "file",
  uid = 1000,
}

local function bytes(value)
  return string.rep(string.char(value), 16)
end

local function fixture(options)
  options = options or {}
  local source = options.source or "/data/sales.parquet"
  local source_buffer = 1
  local state = {
    autocmds = {},
    buffers = {
      [source_buffer] = {
        lines = { "source" },
        name = source,
        options = {
          bufhidden = "",
          buflisted = true,
          buftype = "",
          filetype = options.filetype or "",
          modified = options.modified == true,
          swapfile = true,
          undofile = true,
        },
        valid = true,
        vars = {},
      },
    },
    cache = "/cache",
    commands = {},
    current_window = 101,
    deferred = {},
    deleted_buffers = {},
    fds = {},
    files = {
      ["/cache"] = { mode = 16832, type = "directory", uid = 1000 },
      [source] = vim.deepcopy(source_metadata),
    },
    focused = {},
    fs_mutations = {},
    groups = {},
    next_buffer = 10,
    notifications = {},
    leave_callbacks = {},
    open_calls = {},
    processes = {},
    random_values = {
      bytes(0x11),
      bytes(0x22),
      bytes(0x33),
      bytes(0x44),
      bytes(0x55),
      bytes(0x66),
    },
    readable = { [source] = true },
    realpaths = { [source] = source },
    scheduled = {},
    setup_calls = { cache = 0, command = 0, filesystem = 0, runtime = 0 },
    timers = {},
    tool_calls = {},
    uid = 1000,
    windows = {
      [101] = { buffer = source_buffer, cursor = { 1, 0 }, valid = true },
      [202] = { buffer = source_buffer, cursor = { 1, 0 }, valid = true },
    },
    wipe_callbacks = {},
    wait_calls = {},
  }

  for path, value in pairs(options.files or {}) do
    state.files[path] = value == false and nil or vim.deepcopy(value)
  end
  for path, value in pairs(options.realpaths or {}) do
    state.realpaths[path] = value
  end
  for path, value in pairs(options.readable or {}) do
    state.readable[path] = value
  end
  if options.buffer then
    state.buffers[source_buffer] =
      vim.tbl_deep_extend("force", state.buffers[source_buffer], vim.deepcopy(options.buffer))
  end

  local function parent(path)
    local value = path:match("^(.*)/[^/]+$")
    return value == "" and "/" or value
  end

  local function basename(path)
    return path:match("([^/]+)$")
  end

  local function canonical(path)
    if state.realpaths[path] ~= nil then
      return state.realpaths[path]
    end
    local entry = state.files[path]
    if entry and entry.type ~= "link" then
      return path
    end
    return nil
  end

  local function stat(path)
    local target = canonical(path)
    return target and state.files[target] and vim.deepcopy(state.files[target]) or nil
  end

  local function create_buffer(listed, scratch)
    local bufnr = state.next_buffer
    state.next_buffer = state.next_buffer + 1
    state.buffers[bufnr] = {
      lines = { "" },
      name = "",
      options = {
        bufhidden = "",
        buflisted = listed,
        buftype = scratch and "nofile" or "",
        filetype = "",
        modified = false,
        swapfile = true,
        undofile = true,
      },
      valid = true,
      vars = {},
    }
    return bufnr
  end

  local deps = {
    abspath = function(path)
      if options.abspath_error then
        error(options.abspath_error)
      end
      return path
    end,
    basename = basename,
    boot_id = function()
      if options.boot_id_error then
        return nil, options.boot_id_error
      end
      return "linux-boot-id"
    end,
    buffer_create = create_buffer,
    buffer_delete = function(bufnr)
      state.deleted_buffers[#state.deleted_buffers + 1] = bufnr
      if state.buffers[bufnr] then
        state.buffers[bufnr].valid = false
      end
    end,
    buffer_get_lines = function(bufnr)
      return vim.deepcopy(state.buffers[bufnr].lines)
    end,
    buffer_get_name = function(bufnr)
      return state.buffers[bufnr].name
    end,
    buffer_get_option = function(bufnr, name)
      if options.buffer_option_exception == name then
        error(name .. " inspection exploded")
      end
      return state.buffers[bufnr].options[name]
    end,
    buffer_get_var = function(bufnr, name)
      return state.buffers[bufnr].vars[name]
    end,
    buffer_is_valid = function(bufnr)
      return state.buffers[bufnr] ~= nil and state.buffers[bufnr].valid == true
    end,
    buffer_set_lines = function(bufnr, lines)
      state.buffers[bufnr].lines = vim.deepcopy(lines)
    end,
    buffer_set_name = function(bufnr, name)
      state.buffers[bufnr].name = name
    end,
    buffer_set_option = function(bufnr, name, value)
      if
        options.placeholder_option_exception == name
        and state.buffers[bufnr].name == ""
        and state.buffers[bufnr].options.buflisted == false
      then
        error(name .. " placeholder option exploded")
      end
      state.buffers[bufnr].options[name] = value
    end,
    buffer_set_var = function(bufnr, name, value)
      state.buffers[bufnr].vars[name] = vim.deepcopy(value)
    end,
    buffer_windows = function(bufnr)
      local windows = {}
      for winid, window in pairs(state.windows) do
        if window.valid and window.buffer == bufnr then
          windows[#windows + 1] = winid
        end
      end
      table.sort(windows)
      return windows
    end,
    cache_path = function()
      state.setup_calls.cache = state.setup_calls.cache + 1
      return state.cache
    end,
    command_create = function(name, callback, command_options)
      state.setup_calls.command = state.setup_calls.command + 1
      state.commands[name] = { callback = callback, options = vim.deepcopy(command_options) }
    end,
    create_augroup = function(name, group_options)
      state.groups[#state.groups + 1] = { name = name, options = vim.deepcopy(group_options) }
      return #state.groups
    end,
    create_autocmd = function(event, autocmd_options)
      state.autocmds[#state.autocmds + 1] = {
        event = vim.deepcopy(event),
        options = vim.deepcopy(autocmd_options),
      }
    end,
    defer = function(milliseconds, callback)
      state.deferred[#state.deferred + 1] = {
        callback = callback,
        milliseconds = milliseconds,
      }
    end,
    deepcopy = vim.deepcopy,
    dirname = parent,
    file_readable = function(path)
      return state.readable[path] == true
    end,
    focus_window = function(winid)
      state.current_window = winid
      state.focused[#state.focused + 1] = winid
    end,
    fs_close = function(fd)
      state.fds[fd] = nil
      return true
    end,
    fs_fsync = function(fd)
      expect(state.fds[fd] ~= nil, "fsync used an unknown descriptor")
      return true
    end,
    fs_lstat = function(path)
      if options.lstat_hook then
        options.lstat_hook(path, state)
      end
      if options.lstat_exceptions and options.lstat_exceptions[path] then
        error(options.lstat_exceptions[path])
      end
      if options.lstat_errors and options.lstat_errors[path] then
        return nil, options.lstat_errors[path]
      end
      return state.files[path] and vim.deepcopy(state.files[path]) or nil, "ENOENT"
    end,
    fs_mkdir = function(path, mode)
      state.setup_calls.filesystem = state.setup_calls.filesystem + 1
      state.fs_mutations[#state.fs_mutations + 1] = { "mkdir", path, mode }
      if options.mkdir_errors and options.mkdir_errors[path] then
        return nil, options.mkdir_errors[path]
      end
      if state.files[path] then
        return nil, "EEXIST"
      end
      if not state.files[parent(path)] then
        return nil, "ENOENT"
      end
      state.files[path] = { mode = 16384 + mode, type = "directory", uid = state.uid }
      state.realpaths[path] = path
      return true
    end,
    fs_open = function(path, flags, mode)
      state.setup_calls.filesystem = state.setup_calls.filesystem + 1
      state.fs_mutations[#state.fs_mutations + 1] = { "open", path, flags, mode }
      if options.open_errors and options.open_errors[path] then
        return nil, options.open_errors[path]
      end
      if state.files[path] then
        return nil, "EEXIST"
      end
      state.files[path] = {
        content = "",
        mode = 32768 + mode,
        size = 0,
        type = "file",
        uid = state.uid,
      }
      state.realpaths[path] = path
      state.fds[path] = path
      return path
    end,
    fs_read_file = function(path)
      if options.read_errors and options.read_errors[path] then
        return nil, options.read_errors[path]
      end
      local entry = state.files[path]
      if not entry or entry.type ~= "file" then
        return nil, "ENOENT"
      end
      return entry.content or ""
    end,
    fs_realpath = function(path)
      local value = canonical(path)
      return value, value and nil or "ENOENT"
    end,
    fs_rmdir = function(path)
      state.setup_calls.filesystem = state.setup_calls.filesystem + 1
      state.fs_mutations[#state.fs_mutations + 1] = { "rmdir", path }
      if options.rmdir_errors and options.rmdir_errors[path] then
        return nil, options.rmdir_errors[path]
      end
      for candidate in pairs(state.files) do
        if candidate:sub(1, #path + 1) == path .. "/" then
          return nil, "ENOTEMPTY"
        end
      end
      state.files[path] = nil
      state.realpaths[path] = nil
      return true
    end,
    fs_scandir = function(path)
      if options.scandir_errors and options.scandir_errors[path] then
        return nil, options.scandir_errors[path]
      end
      local names = {}
      for candidate in pairs(state.files) do
        if parent(candidate) == path then
          names[#names + 1] = basename(candidate)
        end
      end
      table.sort(names)
      return names
    end,
    fs_stat = stat,
    fs_unlink = function(path)
      state.setup_calls.filesystem = state.setup_calls.filesystem + 1
      state.fs_mutations[#state.fs_mutations + 1] = { "unlink", path }
      if options.unlink_errors and options.unlink_errors[path] then
        return nil, options.unlink_errors[path]
      end
      if not state.files[path] then
        return nil, "ENOENT"
      end
      state.files[path] = nil
      state.realpaths[path] = nil
      return true
    end,
    fs_write = function(fd, data, offset)
      local path = state.fds[fd]
      if not path then
        return nil, "EBADF"
      end
      if options.write_error then
        return nil, options.write_error
      end
      local entry = state.files[path]
      local prefix = entry.content:sub(1, offset)
      entry.content = prefix .. data
      entry.size = #entry.content
      return #data
    end,
    getpid = function()
      return 4242
    end,
    getuid = function()
      return state.uid
    end,
    json_decode = vim.json.decode,
    json_encode = vim.json.encode,
    keymap_set = function(mode, lhs, callback, map_options)
      local bufnr = map_options.buffer
      state.buffers[bufnr].maps = state.buffers[bufnr].maps or {}
      state.buffers[bufnr].maps[mode .. ":" .. lhs] = {
        callback = callback,
        desc = map_options.desc,
      }
    end,
    levels = vim.log.levels,
    normalize = function(path)
      return vim.fs.normalize(path, { expand_env = false })
    end,
    notify = function(message, level)
      if options.notify_exception then
        error(options.notify_exception)
      end
      state.notifications[#state.notifications + 1] = { level = level, message = message }
    end,
    now = function()
      return 1787414400
    end,
    on_buffer_wipe = function(bufnr, callback)
      state.wipe_callbacks[bufnr] = callback
    end,
    on_buffer_leave = function(bufnr, callback)
      state.leave_callbacks[bufnr] = callback
    end,
    open_file = function(path)
      if options.open_file_error then
        error(options.open_file_error)
      end
      if not state.files[path] then
        return nil, "could not reopen"
      end
      local bufnr = create_buffer(true, false)
      state.buffers[bufnr].name = options.open_file_path or path
      return bufnr
    end,
    open_parquet = function(placeholder, path, viewer_options)
      local call = {
        options = viewer_options,
        path = path,
        placeholder = placeholder,
        window = state.current_window,
      }
      state.open_calls[#state.open_calls + 1] = call
      if options.viewer_exception then
        error(options.viewer_exception)
      end
      if options.viewer_move_to then
        state.windows[state.current_window].buffer = options.viewer_move_to
      end
      if options.viewer_failure then
        viewer_options.on_complete({ reason = "startup-failure" })
        return false
      end
      local terminal = create_buffer(false, true)
      call.terminal = terminal
      if options.viewer_replace then
        state.buffers[terminal].name = "term://query-result"
        state.buffers[terminal].options.buftype = "terminal"
        state.windows[state.current_window].buffer = terminal
      end
      return true, terminal
    end,
    process_start_ticks = function(pid)
      if options.process_errors and options.process_errors[pid] then
        return nil, options.process_errors[pid]
      end
      if options.process_ticks and options.process_ticks[pid] ~= nil then
        return options.process_ticks[pid]
      end
      return pid == 4242 and 987654 or nil, "ENOENT"
    end,
    random = function(length)
      expect(length == 16, "random byte contract changed")
      local value = table.remove(state.random_values, 1)
      if not value then
        error("random fixture exhausted")
      end
      return value
    end,
    schedule = function(callback)
      if options.schedule_exception then
        error(options.schedule_exception)
      end
      state.scheduled[#state.scheduled + 1] = callback
      callback()
    end,
    sha256 = function(path)
      state.hashed = path
      return string.rep("a", 64)
    end,
    spawn = function(command, process_options, on_exit)
      if options.spawn_exception then
        error(options.spawn_exception)
      end
      local process = {
        command = vim.deepcopy(command),
        exited = false,
        kill_signals = {},
        on_exit = on_exit,
        options = process_options,
      }
      function process:kill(signal)
        if options.kill_exception then
          error(options.kill_exception)
        end
        self.kill_signals[#self.kill_signals + 1] = signal
      end
      function process:wait()
        state.wait_calls[#state.wait_calls + 1] = { kind = "system-wait" }
        return self.wait_result
      end
      state.processes[#state.processes + 1] = process
      if options.exit_during_spawn_set or options.exit_during_spawn then
        on_exit(vim.deepcopy(options.exit_during_spawn))
      end
      if options.invalid_handle then
        return {}
      end
      return process
    end,
    timer_start = function(milliseconds, callback)
      if options.timer_exception then
        error(options.timer_exception)
      end
      local timer = { callback = callback, milliseconds = milliseconds, stopped = false }
      function timer:stop()
        self.stopped = true
      end
      state.timers[#state.timers + 1] = timer
      return timer
    end,
    wait_until = function(milliseconds, predicate)
      state.wait_calls[#state.wait_calls + 1] = { kind = "batch", milliseconds = milliseconds }
      local index = #state.wait_calls
      if options.wait_exception_at == index then
        error("batch wait exploded")
      end
      if options.wait_hooks and options.wait_hooks[index] then
        options.wait_hooks[index](state, predicate)
      end
      if options.wait_results and options.wait_results[index] ~= nil then
        return options.wait_results[index]
      end
      return predicate()
    end,
    window_call = function(winid, callback)
      local previous = state.current_window
      state.current_window = winid
      local ok, first, second = pcall(callback)
      state.current_window = previous
      if not ok then
        error(first)
      end
      return first, second
    end,
    window_current = function()
      return state.current_window
    end,
    window_get_buffer = function(winid)
      return state.windows[winid] and state.windows[winid].buffer
    end,
    window_get_cursor = function(winid)
      return vim.deepcopy(state.windows[winid].cursor)
    end,
    window_is_valid = function(winid)
      return state.windows[winid] ~= nil and state.windows[winid].valid == true
    end,
    window_set_buffer = function(winid, bufnr)
      if
        options.fallback_switch_exception
        and state.buffers[bufnr]
        and state.buffers[bufnr].name == ""
        and state.buffers[bufnr].options.buflisted == true
      then
        if options.fallback_switch_after_exception then
          state.windows[winid].buffer = bufnr
        end
        error(options.fallback_switch_exception)
      end
      state.windows[winid].buffer = bufnr
    end,
    window_set_cursor = function(winid, cursor)
      state.windows[winid].cursor = vim.deepcopy(cursor)
    end,
  }

  deps.tool_runtime = function()
    state.setup_calls.runtime = state.setup_calls.runtime + 1
    if options.runtime_exception then
      error(options.runtime_exception)
    end
    if options.runtime_error then
      return nil, options.runtime_error
    end
    return { ok = true, python = "/managed/bin/python" }
  end

  deps.tool_command = function(request)
    state.tool_calls[#state.tool_calls + 1] = vim.deepcopy(request)
    if options.command_exception then
      error(options.command_exception)
    end
    if options.command_error then
      return nil, nil, options.command_error
    end
    return { "/usr/bin/bwrap", "--sandboxed" },
      "/tmp/dotfiles-data-query-source/" .. request.visible_name
  end

  local workflow = workflow_module._test.new(deps)

  local function trigger_exit(process, result)
    process.exited = true
    process.on_exit(vim.deepcopy(result or { code = 0, signal = 0 }))
  end

  local function add_result(process, payload, result_options)
    result_options = result_options or {}
    local request = state.tool_calls[#state.tool_calls]
    local path = request.result
    state.files[path] = {
      mode = result_options.mode or 33152,
      size = result_options.size or 128,
      type = result_options.type or "file",
      uid = result_options.uid or state.uid,
    }
    state.realpaths[path] = result_options.realpath or path
    process.options.stdout(nil, vim.json.encode(payload or {
      ok = true,
      result = path,
      rows = 2,
      truncated = false,
      version = 1,
    }) .. "\n")
    return path
  end

  return workflow,
    state,
    {
      add_result = add_result,
      source = source,
      source_buffer = source_buffer,
      trigger_exit = trigger_exit,
    }
end

local function latest_message(state)
  local item = state.notifications[#state.notifications]
  return item and item.message or ""
end

local function stale_fixture(case)
  case = case or {}
  local suffix = case.suffix or string.rep("99", 16)
  local name = case.name or ("instance-v1-" .. suffix)
  local workspace = "/cache/dotfiles-data-query/" .. name
  local marker_path = workspace .. "/owner-v1.json"
  local marker = vim.tbl_extend("force", {
    boot_id = "linux-boot-id",
    created_at = 1787000000,
    pid = 9,
    process_start_ticks = 123,
    schema = 1,
    uid = 1000,
  }, case.marker or {})
  local files = {
    ["/cache/dotfiles-data-query"] = { mode = 16832, type = "directory", uid = 1000 },
    [workspace] = { mode = 16832, type = "directory", uid = 1000 },
    [marker_path] = {
      content = case.raw_marker or vim.json.encode(marker),
      mode = 33152,
      size = case.marker_size or 128,
      type = case.marker_type or "file",
      uid = case.marker_owner or 1000,
    },
  }
  for path, value in pairs(case.files or {}) do
    files[path:gsub("^<workspace>", workspace)] = vim.deepcopy(value)
  end
  local scandir_errors = {}
  for path, value in pairs(case.scandir_errors or {}) do
    scandir_errors[path:gsub("^<workspace>", workspace)] = value
  end
  local workflow, state = fixture({
    files = files,
    process_errors = case.process_errors,
    process_ticks = case.process_ticks,
    realpaths = case.realpaths,
    scandir_errors = scandir_errors,
  })
  return workflow, state, workspace, marker_path
end

local function start_two_queries(workflow, state)
  expect(workflow.enter() == true and workflow.run() == true, "first concurrent query failed")
  local second_source = "/data/second.csv"
  state.files[second_source] = vim.tbl_deep_extend("force", vim.deepcopy(source_metadata), {
    ino = 54321,
  })
  state.realpaths[second_source] = second_source
  state.readable[second_source] = true
  state.buffers[2] = {
    lines = { "second" },
    name = second_source,
    options = {
      bufhidden = "",
      buflisted = true,
      buftype = "",
      filetype = "csv",
      modified = false,
      swapfile = true,
      undofile = true,
    },
    valid = true,
    vars = {},
  }
  state.windows[202].buffer = 2
  state.current_window = 202
  expect(workflow.enter() == true and workflow.run() == true, "second concurrent query failed")
  return state.processes[1], state.processes[2], state.tool_calls[1], state.tool_calls[2]
end

do
  local invalid_cases = {
    { label = "unnamed", buffer = { name = "" } },
    { label = "URI", buffer = { name = "https://example.test/sales.csv" } },
    { label = "uppercase", buffer = { name = "/data/sales.CSV" } },
    {
      label = "directory",
      files = { ["/data/sales.parquet"] = { mode = 16832, type = "directory", uid = 1000 } },
    },
    {
      label = "FIFO",
      files = { ["/data/sales.parquet"] = { mode = 4516, type = "fifo", uid = 1000 } },
    },
    {
      label = "device",
      files = { ["/data/sales.parquet"] = { mode = 8576, type = "char", uid = 1000 } },
    },
    { label = "unreadable", readable = { ["/data/sales.parquet"] = false } },
    { label = "control", source = "/data/bad\nname.csv" },
    { label = "modified CSV", source = "/data/sales.csv", modified = true },
    { label = "modified TSV", source = "/data/sales.tsv", modified = true },
    {
      label = "ambiguous modified state",
      source = "/data/sales.csv",
      buffer_option_exception = "modified",
    },
    { label = "ordinary terminal", buffer = { options = { buftype = "terminal" } } },
  }
  for _, case in ipairs(invalid_cases) do
    local workflow, state = fixture(case)
    local before = vim.deepcopy(state.windows)
    expect(workflow.enter() == false, case.label .. " source unexpectedly entered")
    eq(state.windows, before, case.label .. " source changed a window")
    expect(state.setup_calls.runtime == 0, case.label .. " source called the resolver")
    expect(state.setup_calls.filesystem == 0, case.label .. " source mutated the cache")
  end
end

for _, extension in ipairs({ "parquet", "csv", "tsv" }) do
  local workflow, state = fixture({ source = "/data/sales." .. extension })
  expect(workflow.enter() == true, extension .. " source did not enter")
  expect(state.setup_calls.runtime == 1, extension .. " source skipped runtime readiness")
  local scratch = state.windows[101].buffer
  expect(scratch ~= 1, extension .. " source did not open a scratch")
end

do
  local workflow, state, ids = fixture({
    buffer = {
      name = "term://viewer",
      options = { buftype = "terminal" },
      vars = {
        dotfiles_parquet_viewer = {
          job = 42,
          path = "/data/sales.parquet",
          readonly = true,
          return_buffer = 9,
        },
      },
    },
  })
  expect(workflow.enter() == true, "Parquet viewer metadata was not recognized")
  local scratch = state.windows[101].buffer
  expect(scratch ~= ids.source_buffer, "terminal source did not open a scratch")
  expect(workflow.back() == true, "hidden Parquet terminal was not restored")
  expect(
    state.windows[101].buffer == ids.source_buffer,
    "back replaced the retained Parquet terminal"
  )
  expect(
    state.buffers[ids.source_buffer].vars.dotfiles_parquet_viewer.job == 42,
    "terminal metadata changed"
  )

  local malformed, malformed_state = fixture({
    buffer = {
      name = "term://viewer",
      options = { buftype = "terminal" },
      vars = { dotfiles_parquet_viewer = { path = "/data/sales.parquet" } },
    },
  })
  expect(malformed.enter() == false, "malformed Parquet metadata was accepted")
  expect(malformed_state.setup_calls.runtime == 0, "malformed metadata called the resolver")
end

do
  local workflow, state = fixture()
  workflow.setup()
  workflow.setup()
  expect(state.setup_calls.runtime == 0, "setup probed the runtime")
  expect(state.setup_calls.cache == 0, "setup probed the query cache")
  expect(state.setup_calls.filesystem == 0, "setup mutated the filesystem")
  expect(state.setup_calls.command == 1, "DataQuery command was not idempotent")
  expect(state.commands.DataQuery ~= nil, "DataQuery command is missing")
  expect(
    type(state.commands.DataQuery.options.desc) == "string",
    "DataQuery description is missing"
  )
  expect(
    #state.groups == 1 and state.groups[1].name == "dotfiles-data-query",
    "augroup contract changed"
  )

  local events = {}
  for _, item in ipairs(state.autocmds) do
    local event = type(item.event) == "table" and table.concat(item.event, ",") or item.event
    events[event] = item.options
  end
  expect(events["BufReadPost,BufNewFile"] ~= nil, "source attachment autocmd is missing")
  eq(events["BufReadPost,BufNewFile"].pattern, { "*.csv", "*.tsv", "*.parquet" }, "source patterns")
  expect(events.TermOpen ~= nil, "scheduled terminal inspection is missing")
  expect(events.User ~= nil, "Parquet metadata-ready listener is missing")
  expect(
    events.User.pattern == "DotfilesParquetViewerReady",
    "Parquet metadata-ready pattern changed"
  )
  expect(
    events.User.group == events.TermOpen.group
      and events.User.group == events["BufReadPost,BufNewFile"].group,
    "User listener did not reuse the data-query group"
  )
  expect(events.VimLeavePre ~= nil, "shutdown autocmd is missing")

  local user_listeners = 0
  local function emit_user(pattern, data)
    for _, item in ipairs(state.autocmds) do
      if item.event == "User" and item.options.pattern == pattern then
        item.options.callback({ data = vim.deepcopy(data), match = pattern })
      end
    end
  end
  for _, item in ipairs(state.autocmds) do
    if item.event == "User" then
      user_listeners = user_listeners + 1
    end
  end
  expect(user_listeners == 1, "setup did not register exactly one metadata-ready listener")

  events.User.callback(nil)
  for _, args in ipairs({
    {},
    { data = false },
    { data = {} },
    { data = { buffer = false } },
    { data = { buffer = "1" } },
    { data = { buffer = 0 } },
    { data = { buffer = -1 } },
    { data = { buffer = 1.5 } },
    { data = { buffer = math.huge } },
  }) do
    events.User.callback(args)
  end
  events.User.callback({ data = { buffer = 999 } })
  state.buffers[8] = {
    lines = { "" },
    name = "term://malformed-metadata",
    options = { buftype = "terminal", filetype = "terminal", modified = false },
    valid = true,
    vars = { dotfiles_parquet_viewer = { path = "/data/sales.parquet" } },
  }
  events.User.callback({ data = { buffer = 8 } })
  expect(state.buffers[8].maps == nil, "incomplete Parquet metadata received a query mapping")
  expect(state.setup_calls.runtime == 0, "malformed or stale metadata-ready event probed runtime")
  expect(state.setup_calls.cache == 0, "malformed or stale metadata-ready event probed cache")
  expect(
    state.setup_calls.filesystem == 0,
    "malformed or stale metadata-ready event mutated the cache"
  )

  state.buffers[7] = {
    lines = { "" },
    name = "term://metadata-race",
    options = { buftype = "terminal", filetype = "terminal", modified = false },
    valid = true,
    vars = {},
  }
  local scheduled_before = #state.scheduled
  events.TermOpen.callback({ buf = 7 })
  expect(
    #state.scheduled == scheduled_before + 1,
    "TermOpen did not perform exactly one initial scheduled inspection"
  )
  expect(#state.deferred == 1, "metadata-absent Parquet terminal did not defer inspection")
  state.buffers[7].vars.dotfiles_parquet_viewer = {
    job = 77,
    path = "/data/sales.parquet",
    readonly = true,
    return_buffer = 1,
  }
  table.remove(state.deferred, 1).callback()
  expect(
    state.buffers[7].maps["n:<leader>dq"].desc == "Data: query current file",
    "deferred terminal inspection missed late Parquet metadata"
  )

  state.buffers[6] = {
    lines = { "unsupported" },
    name = "term://ordinary",
    options = { buftype = "terminal", filetype = "terminal", modified = false },
    valid = true,
    vars = {},
  }
  scheduled_before = #state.scheduled
  events.TermOpen.callback({ buf = 6 })
  expect(
    #state.scheduled == scheduled_before + 1,
    "ordinary TermOpen did not use one initial scheduled inspection"
  )
  local retries = 0
  while #state.deferred > 0 do
    retries = retries + 1
    expect(retries <= 8, "ordinary terminal metadata retries were not bounded")
    table.remove(state.deferred, 1).callback()
  end
  expect(retries == 4, "ordinary terminal metadata retry bound changed")
  expect(state.buffers[6].maps == nil, "ordinary terminal received a data-query mapping")
  expect(state.setup_calls.runtime == 0, "terminal metadata inspection probed the runtime")
  expect(state.setup_calls.cache == 0, "terminal metadata inspection probed the cache")
  expect(state.setup_calls.filesystem == 0, "terminal metadata inspection mutated the cache")

  emit_user("DotfilesParquetViewerReady", { buffer = 6 })
  expect(state.buffers[6].maps == nil, "metadata-ready event attached without viewer metadata")

  state.buffers[6].vars.dotfiles_parquet_viewer = {
    job = 66,
    path = "/data/sales.parquet",
    readonly = true,
    return_buffer = 1,
  }
  emit_user("SomeOtherUserEvent", { buffer = 6 })
  expect(state.buffers[6].maps == nil, "unrelated User event attached a data-query mapping")
  emit_user("DotfilesParquetViewerReady", { buffer = 6 })
  expect(
    state.buffers[6].maps["n:<leader>dq"].desc == "Data: query current file",
    "metadata-ready event did not attach after TermOpen retries expired"
  )
  expect(state.setup_calls.runtime == 0, "metadata-ready event probed runtime")
  expect(state.setup_calls.cache == 0, "metadata-ready event probed cache")
  expect(state.setup_calls.filesystem == 0, "metadata-ready event mutated the cache")

  events["BufReadPost,BufNewFile"].callback({ buf = 1 })
  expect(state.buffers[1].maps["n:<leader>dq"].desc == "Data: query current file", "source map")

  state.buffers[2] = {
    lines = { "# markdown" },
    name = "/data/notes.md",
    options = { buftype = "", filetype = "markdown", modified = false },
    valid = true,
    vars = {},
  }
  workflow.attach(2)
  expect(state.buffers[2].maps == nil, "Markdown received a data-query mapping")

  for bufnr, definition in pairs({
    [3] = { filetype = "python", name = "/data/script.py" },
    [4] = { filetype = "markdown", name = "/data/notebook.ipynb" },
    [5] = { filetype = "sql", name = "/data/query.sql" },
    [6] = { buftype = "terminal", filetype = "terminal", name = "term://ordinary" },
  }) do
    state.buffers[bufnr] = {
      lines = { "unsupported" },
      name = definition.name,
      options = {
        buftype = definition.buftype or "",
        filetype = definition.filetype,
        modified = false,
      },
      valid = true,
      vars = {},
    }
    expect(workflow.attach(bufnr) == false, definition.filetype .. " unexpectedly attached")
    expect(state.buffers[bufnr].maps == nil, definition.filetype .. " received a source mapping")
  end
end

do
  local workflow, state = fixture({ source = "/data/team's data.csv" })
  expect(workflow.enter() == true, "quoted source did not enter")
  local scratch = state.windows[101].buffer
  eq(state.buffers[scratch].options, {
    bufhidden = "hide",
    buflisted = false,
    buftype = "nofile",
    filetype = "sql",
    modified = false,
    swapfile = false,
    undofile = false,
  }, "scratch option contract")
  eq(state.buffers[scratch].lines, {
    "SELECT *",
    "FROM 'team''s data.csv'",
    "LIMIT 1000;",
  }, "starter SQL quoting")
  expect(state.buffers[scratch].name == "data-query://" .. string.rep("a", 64), "scratch URI")
  eq(state.hashed, "/data/team's data.csv", "scratch identity must hash the canonical path")
  for _, lhs in ipairs({ "<leader>dr", "<leader>dx", "<leader>db" }) do
    local mapping = state.buffers[scratch].maps["n:" .. lhs]
    expect(mapping and type(mapping.desc) == "string", "missing scratch mapping " .. lhs)
  end

  state.buffers[scratch].lines = { "SELECT 42;" }
  state.windows[101].cursor = { 1, 7 }
  expect(workflow.back() == true, "back did not restore the source")
  expect(state.windows[101].buffer == 1, "back restored the wrong source")
  expect(workflow.enter() == true, "scratch re-entry failed")
  expect(state.windows[101].buffer == scratch, "scratch was not retained")
  eq(state.buffers[scratch].lines, { "SELECT 42;" }, "scratch text was not retained")
  eq(state.windows[101].cursor, { 1, 7 }, "scratch cursor was not retained")

  state.windows[202].buffer = 1
  state.current_window = 202
  expect(workflow.enter() == true, "visible scratch focus failed")
  expect(state.current_window == 101, "owning scratch window was not focused")
  expect(state.windows[202].buffer == 1, "invoking window was changed during focus")

  state.windows[101].valid = false
  state.current_window = 202
  expect(workflow.enter() == true, "hidden scratch adoption failed")
  expect(state.windows[202].buffer == scratch, "invoking window did not adopt scratch")

  state.windows[101] = { buffer = scratch, cursor = { 1, 0 }, valid = true }
  state.current_window = 101
  expect(workflow.run() == false, "manually duplicated scratch was allowed to run")
  expect(workflow.cancel() == false, "manually duplicated scratch was allowed to cancel")
  expect(workflow.back() == false, "manually duplicated scratch was allowed to navigate")
end

do
  local workflow, state = fixture()
  expect(workflow.enter() == true, "canonical source did not enter")
  local scratch = state.windows[101].buffer
  state.buffers[scratch].lines = { "SELECT 7;" }
  expect(workflow.back() == true, "canonical source did not restore")

  local alias = "/data/sales-alias.parquet"
  state.files[alias] = { mode = 41471, type = "link", uid = 1000 }
  state.realpaths[alias] = "/data/sales.parquet"
  state.readable[alias] = true
  state.buffers[2] = {
    lines = { "alias" },
    name = alias,
    options = {
      bufhidden = "",
      buflisted = true,
      buftype = "",
      filetype = "",
      modified = false,
      swapfile = true,
      undofile = true,
    },
    valid = true,
    vars = {},
  }
  state.windows[202].buffer = 2
  state.current_window = 202
  expect(workflow.enter() == true, "canonical alias did not adopt the retained scratch")
  expect(state.windows[202].buffer == scratch, "canonical alias created another scratch")
  eq(state.buffers[scratch].lines, { "SELECT 7;" }, "canonical alias rewrote retained SQL")
  expect(workflow.run() == true, "retained scratch did not run after alias entry")
  eq(
    state.tool_calls[1].visible_name,
    "sales.parquet",
    "canonical alias changed the virtual filename"
  )
  eq(state.tool_calls[1].source, "/data/sales.parquet", "canonical alias changed the source target")
end

do
  local other = "/data/other.csv"
  local workflow, state = fixture({
    files = {
      [other] = vim.tbl_deep_extend("force", vim.deepcopy(source_metadata), { ino = 54321 }),
    },
    readable = { [other] = true },
    realpaths = { [other] = other },
  })
  workflow.enter()
  local first = state.windows[101].buffer
  workflow.back()
  state.buffers[2] = {
    lines = { "id,value" },
    name = other,
    options = {
      bufhidden = "",
      buflisted = true,
      buftype = "",
      filetype = "csv",
      modified = false,
      swapfile = true,
      undofile = true,
    },
    valid = true,
    vars = {},
  }
  state.windows[101].buffer = 2
  workflow.enter()
  local second = state.windows[101].buffer
  expect(first ~= second, "distinct canonical sources shared one SQL scratch")
  for _, mutation in ipairs(state.fs_mutations) do
    local path = mutation[2]
    expect(
      path:sub(1, #"/cache/dotfiles-data-query") == "/cache/dotfiles-data-query",
      "scratch creation wrote a source-adjacent sidecar: " .. tostring(path)
    )
  end
  for path in pairs(state.files) do
    expect(not path:match("^/data/.*%.sql$"), "scratch creation left a SQL sidecar")
  end
end

do
  local workflow, state = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  state.windows[101].cursor = { 3, 4 }
  expect(type(state.leave_callbacks[scratch]) == "function", "scratch cursor leave hook is missing")
  state.leave_callbacks[scratch]()
  state.windows[101].valid = false
  state.current_window = 202
  expect(workflow.enter() == true, "scratch adoption after owner close failed")
  eq(state.windows[202].cursor, { 3, 4 }, "owner loss reset the retained scratch cursor")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  state.buffers[helpers.source_buffer].valid = false
  expect(workflow.back() == true, "wiped source did not reopen")
  local reopened = state.windows[101].buffer
  expect(
    reopened ~= scratch and state.buffers[reopened].name == helpers.source,
    "wrong reopened source"
  )
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  state.buffers[helpers.source_buffer].valid = false
  state.realpaths[helpers.source] = "/data/replacement.parquet"
  state.files["/data/replacement.parquet"] = vim.deepcopy(source_metadata)
  expect(workflow.back() == true, "unsafe restoration did not install an empty fallback")
  local fallback = state.windows[101].buffer
  expect(state.buffers[fallback].name == "", "unsafe restoration did not use an empty buffer")
  expect(
    latest_message(state):find("different file", 1, true) ~= nil,
    "retarget warning is missing"
  )
end

do
  local workflow, state, helpers = fixture({ open_file_error = "reopen exploded" })
  workflow.enter()
  state.buffers[helpers.source_buffer].valid = false
  expect(workflow.back() == true, "failed reopen did not install an empty fallback")
  expect(state.buffers[state.windows[101].buffer].name == "", "failed reopen fallback is not empty")
end

do
  local workflow, state, helpers = fixture({
    fallback_switch_exception = "BufLeave callback failed",
  })
  workflow.enter()
  local scratch = state.windows[101].buffer
  state.buffers[helpers.source_buffer].valid = false
  state.realpaths[helpers.source] = "/data/replacement.parquet"
  state.files["/data/replacement.parquet"] = vim.deepcopy(source_metadata)
  local fallback = state.next_buffer
  expect(workflow.back() == false, "failed fallback switch reported successful restoration")
  expect(state.windows[101].buffer == scratch, "failed fallback switch moved the scratch")
  expect(
    state.buffers[fallback] and state.buffers[fallback].valid == false,
    "failed fallback switch retained its hidden fallback buffer"
  )
  expect(
    latest_message(state):find("could not safely restore", 1, true) ~= nil,
    "failed fallback switch did not notify"
  )
end

do
  local workflow, state, helpers = fixture({
    fallback_switch_after_exception = true,
    fallback_switch_exception = "buffer switch failed after replacement",
  })
  workflow.enter()
  local scratch = state.windows[101].buffer
  state.buffers[helpers.source_buffer].valid = false
  state.realpaths[helpers.source] = "/data/replacement.parquet"
  state.files["/data/replacement.parquet"] = vim.deepcopy(source_metadata)
  local fallback = state.next_buffer
  expect(workflow.back() == false, "partial fallback switch reported successful restoration")
  expect(state.windows[101].buffer == scratch, "partial fallback switch did not restore scratch")
  expect(
    state.buffers[fallback] and state.buffers[fallback].valid == false,
    "partial fallback switch retained its hidden buffer"
  )
end

do
  local workflow, state, helpers = fixture({
    files = {
      ["/data/other.csv"] = vim.deepcopy(source_metadata),
    },
    open_file_path = "/data/other.csv",
    readable = { ["/data/other.csv"] = true },
    realpaths = { ["/data/other.csv"] = "/data/other.csv" },
  })
  workflow.enter()
  state.buffers[helpers.source_buffer].valid = false
  expect(workflow.back() == true, "mismatched reopen did not fall back safely")
  expect(state.buffers[state.windows[101].buffer].name == "", "mismatched reopen was accepted")
end

do
  local workflow, state = fixture()
  expect(workflow.enter() == true, "cache-owning entry failed")
  local parent = "/cache/dotfiles-data-query"
  local instance = parent .. "/instance-v1-" .. string.rep("11", 16)
  local marker = instance .. "/owner-v1.json"
  expect(state.files[parent].mode % 512 == 448, "cache parent mode is not 0700")
  expect(state.files[instance].mode % 512 == 448, "instance mode is not 0700")
  expect(state.files[marker].mode % 512 == 384, "owner marker mode is not 0600")
  eq(vim.json.decode(state.files[marker].content), {
    boot_id = "linux-boot-id",
    created_at = 1787414400,
    pid = 4242,
    process_start_ticks = 987654,
    schema = 1,
    uid = 1000,
  }, "owner marker schema")
end

for _, case in ipairs({
  {
    label = "symlink",
    files = {
      ["/cache/dotfiles-data-query"] = { mode = 41471, type = "link", uid = 1000 },
    },
    realpaths = { ["/cache/dotfiles-data-query"] = "/outside" },
  },
  {
    label = "wrong mode",
    files = {
      ["/cache/dotfiles-data-query"] = { mode = 16877, type = "directory", uid = 1000 },
    },
  },
  {
    label = "foreign owner",
    files = {
      ["/cache/dotfiles-data-query"] = { mode = 16832, type = "directory", uid = 2000 },
    },
  },
}) do
  local workflow, state = fixture(case)
  local before = vim.deepcopy(state.windows)
  expect(workflow.enter() == false, "unsafe cache " .. case.label .. " was accepted")
  eq(state.windows, before, "unsafe cache " .. case.label .. " changed a window")
end

do
  local workflow, state = fixture({ exit_during_spawn_set = true })
  workflow.enter()
  expect(workflow.run() == true, "synchronous nil exit callback broke spawn completion")
  expect(
    state.files[state.tool_calls[1].workspace] == nil,
    "synchronous nil exit callback was lost"
  )
  expect(
    latest_message(state):find("invalid exit result", 1, true) ~= nil,
    "nil exit was not diagnosed"
  )
end

do
  local workflow, state = fixture({
    exit_during_spawn = { malformed = true },
    exit_during_spawn_set = true,
  })
  workflow.enter()
  expect(workflow.run() == true, "synchronous malformed exit callback broke spawn completion")
  expect(state.files[state.tool_calls[1].workspace] == nil, "malformed exit callback leaked a run")
end

do
  local workflow, state = fixture({ write_error = "EIO" })
  expect(workflow.enter() == false, "partial owner-marker write was accepted")
  for path in pairs(state.files) do
    expect(not path:find("/instance%-v1%-"), "partial instance workspace survived marker failure")
  end
end

do
  local collision = "/cache/dotfiles-data-query/instance-v1-" .. string.rep("11", 16)
  local workflow, state = fixture({
    files = {
      ["/cache/dotfiles-data-query"] = { mode = 16832, type = "directory", uid = 1000 },
      [collision] = { mode = 16832, type = "directory", uid = 1000 },
    },
  })
  expect(workflow.enter() == true, "random collision prevented cache allocation")
  local replacement = "/cache/dotfiles-data-query/instance-v1-" .. string.rep("22", 16)
  expect(state.files[replacement] ~= nil, "collision did not consume a new random suffix")
end

do
  local stale_name = "instance-v1-" .. string.rep("77", 16)
  local stale = "/cache/dotfiles-data-query/" .. stale_name
  local stale_marker = stale .. "/owner-v1.json"
  local workflow, state = fixture({
    files = {
      ["/cache/dotfiles-data-query"] = { mode = 16832, type = "directory", uid = 1000 },
      [stale] = { mode = 16832, type = "directory", uid = 1000 },
      [stale_marker] = {
        content = vim.json.encode({
          boot_id = "old-boot",
          created_at = 1787000000,
          pid = 9,
          process_start_ticks = 123,
          schema = 1,
          uid = 1000,
        }),
        mode = 33152,
        size = 128,
        type = "file",
        uid = 1000,
      },
    },
  })
  expect(workflow.enter() == true, "entry with stale cleanup failed")
  expect(state.files[stale] == nil and state.files[stale_marker] == nil, "stale workspace survived")
end

do
  local live = "/cache/dotfiles-data-query/instance-v1-" .. string.rep("88", 16)
  local marker = live .. "/owner-v1.json"
  local workflow, state = fixture({
    files = {
      ["/cache/dotfiles-data-query"] = { mode = 16832, type = "directory", uid = 1000 },
      [live] = { mode = 16832, type = "directory", uid = 1000 },
      [marker] = {
        content = vim.json.encode({
          boot_id = "linux-boot-id",
          created_at = 1787000000,
          pid = 4242,
          process_start_ticks = 987654,
          schema = 1,
          uid = 1000,
        }),
        mode = 33152,
        size = 128,
        type = "file",
        uid = 1000,
      },
    },
  })
  expect(workflow.enter() == true, "entry beside a live workspace failed")
  expect(state.files[live] ~= nil and state.files[marker] ~= nil, "live workspace was removed")
end

do
  local workflow, state, workspace = stale_fixture({ marker = { created_at = 1787414399 } })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "recent workspace was removed")
end

do
  local workflow, state, workspace = stale_fixture({
    marker = { created_at = 1787414399 },
    process_ticks = { [9] = 999 },
  })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "recent reused-PID workspace was removed")
end

do
  local workflow, state, workspace = stale_fixture({ process_ticks = { [9] = 999 } })
  workflow.enter()
  expect(state.files[workspace] == nil, "old reused-PID workspace survived")
end

do
  local workflow, state, workspace = stale_fixture({ raw_marker = "not json" })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "malformed-marker workspace was removed")
end

do
  local workflow, state, workspace = stale_fixture({ marker = { uid = 2000 } })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "foreign-marker workspace was removed")
end

do
  local workflow, state, workspace = stale_fixture({ name = "instance-v1-not-hex" })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "unknown cache child was removed")
end

do
  local workflow, state, workspace = stale_fixture({
    files = {
      ["<workspace>/aaaa-data"] = {
        content = "ordinary",
        mode = 33152,
        size = 8,
        type = "file",
        uid = 1000,
      },
      ["<workspace>/zzzz-link"] = { mode = 41471, type = "link", uid = 1000 },
    },
  })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "stale workspace containing a symlink was removed")
  expect(state.files[workspace .. "/owner-v1.json"] ~= nil, "stale preflight removed its marker")
  expect(state.files[workspace .. "/aaaa-data"] ~= nil, "stale preflight removed an early entry")
  expect(state.files[workspace .. "/zzzz-link"] ~= nil, "stale cleanup unlinked a late symlink")
end

do
  local workflow, state, workspace = stale_fixture({ process_errors = { [9] = "EACCES" } })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "ambiguous process identity was removed")
end

do
  local workflow, state, workspace = stale_fixture({
    scandir_errors = { ["<workspace>"] = "EACCES" },
  })
  workflow.enter()
  expect(state.files[workspace] ~= nil, "permission failure removed an ambiguous workspace")
end

do
  local workflow, state = fixture()
  expect(workflow.enter() == true, "query entry failed")
  local scratch = state.windows[101].buffer
  state.buffers[scratch].lines = { "SELECT * FROM 'sales.parquet';" }
  expect(workflow.run() == true, "query did not spawn")
  expect(#state.processes == 1, "query process is missing")
  local process = state.processes[1]
  local request = state.tool_calls[1]
  eq(request.source, "/data/sales.parquet", "tool source")
  eq(request.visible_name, "sales.parquet", "tool visible name")
  expect(request.workspace:match("/run%-v1%-%x+$") ~= nil, "run workspace name")
  expect(request.result:match("/result%-v1%-%x+%.parquet$") ~= nil, "result name")
  expect(state.files[request.workspace].mode % 512 == 448, "run mode is not 0700")
  expect(state.files[request.workspace .. "/spill"].mode % 512 == 448, "spill mode is not 0700")
  expect(state.files[request.result] == nil, "result existed before the runner")
  eq(process.options.stdin, "SELECT * FROM 'sales.parquet';", "SQL stdin")
  expect(
    process.options.clear_env == true and process.options.text == false,
    "process isolation options"
  )
  eq(process.options.env, {}, "process environment")
  expect(
    process.command[1] == "/managed/bin/python"
      and process.command[2] == "-I"
      and process.command[3] == "-B"
      and process.command[4] == "-c",
    "query did not use the trusted managed-Python supervisor"
  )
  local separator = vim.fn.index(process.command, "--") + 1
  expect(separator > 0, "supervised query command omitted its argument separator")
  eq(
    vim.list_slice(process.command, separator + 1),
    { "/usr/bin/bwrap", "--sandboxed" },
    "supervised Bubblewrap command"
  )
  expect(state.timers[1].milliseconds == 30000, "wall-clock timeout")
  expect(workflow.run() == false, "duplicate query was accepted")

  expect(workflow.cancel() == true, "manual cancellation failed")
  eq(process.kill_signals, { 15 }, "manual cancellation signal")
  expect(workflow.run() == false, "run was accepted during cancellation grace")
  local grace = state.timers[#state.timers]
  expect(grace.milliseconds == 500, "cancellation grace timeout")
  grace.callback()
  eq(process.kill_signals, { 15, 9 }, "forced cancellation signal")
end

do
  local workflow, state = fixture()
  workflow.enter()
  local instance = "/cache/dotfiles-data-query/instance-v1-" .. string.rep("11", 16)
  local collision = instance .. "/run-v1-" .. string.rep("22", 16)
  state.files[collision] = { mode = 16832, type = "directory", uid = 1000 }
  state.realpaths[collision] = collision
  expect(workflow.run() == true, "run-directory collision prevented a query")
  expect(
    state.tool_calls[1].workspace == instance .. "/run-v1-" .. string.rep("33", 16),
    "run-directory collision did not consume fresh randomness"
  )
end

do
  local injected = false
  local workflow, state = fixture({
    lstat_hook = function(path, current)
      if not injected and path:match("/result%-v1%-" .. string.rep("33", 16) .. "%.parquet$") then
        injected = true
        current.files[path] = { mode = 33152, size = 16, type = "file", uid = 1000 }
        current.realpaths[path] = path
      end
    end,
  })
  workflow.enter()
  expect(workflow.run() == true, "result collision prevented a query")
  expect(
    state.tool_calls[1].result:match("/result%-v1%-" .. string.rep("44", 16) .. "%.parquet$") ~= nil,
    "result collision did not consume fresh randomness"
  )
end

do
  local workflow, state = fixture()
  workflow.enter()
  local instance = "/cache/dotfiles-data-query/instance-v1-" .. string.rep("11", 16)
  state.realpaths[instance] = "/outside/instance"
  expect(workflow.run() == false, "escaped instance containment was accepted")
  expect(#state.processes == 0 and #state.tool_calls == 0, "escaped instance reached process setup")
end

do
  local workflow, state = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  state.buffers[scratch].lines = { string.rep("x", 1048577) }
  expect(workflow.run() == false, "oversized SQL was accepted")
  expect(#state.processes == 0, "oversized SQL started a process")
  state.buffers[scratch].lines = { "", "   " }
  expect(workflow.run() == false, "empty SQL was accepted")
end

do
  local workflow, state = fixture({ spawn_exception = "spawn exploded" })
  workflow.enter()
  expect(workflow.run() == false, "spawn exception was accepted")
  local request = state.tool_calls[1]
  expect(
    request and state.files[request.workspace] == nil,
    "spawn exception leaked a run directory"
  )
end

do
  local options = { invalid_handle = true }
  local workflow, state, helpers = fixture(options)
  workflow.enter()
  expect(workflow.run() == false, "invalid post-spawn handle was accepted")
  local process = state.processes[1]
  local request = state.tool_calls[1]
  expect(state.files[request.workspace] ~= nil, "ambiguous live child lost its run workspace")
  expect(workflow.run() == false, "ambiguous live child did not gate duplicate execution")
  local notifications = #state.notifications
  helpers.trigger_exit(process, { code = 125, signal = 0 })
  expect(state.files[request.workspace] == nil, "late invalid-handle exit did not clean its run")
  options.invalid_handle = false
  expect(workflow.run() == true, "late invalid-handle reap did not release its scratch")
  local mutations = #state.fs_mutations
  helpers.trigger_exit(process, { code = 125, signal = 0 })
  expect(#state.fs_mutations == mutations, "duplicate invalid-handle exit cleaned twice")
  expect(#state.notifications == notifications, "late invalid-handle exit notified twice")
end

do
  local workflow, state = fixture({ invalid_handle = true })
  workflow.enter()
  expect(workflow.run() == false, "invalid-handle shutdown setup unexpectedly succeeded")
  local request = state.tool_calls[1]
  local instance = request.workspace:match("^(.*)/run%-v1%-%x+$")
  workflow.shutdown()
  expect(state.files[request.workspace] ~= nil, "shutdown deleted an unreaped ambiguous run")
  expect(state.files[instance] ~= nil, "shutdown deleted an ambiguous child instance")
end

do
  local workflow, state = fixture({
    exit_during_spawn_set = true,
    exit_during_spawn = { code = 125, signal = 0 },
    invalid_handle = true,
  })
  workflow.enter()
  expect(workflow.run() == false, "synchronously reaped invalid handle was accepted")
  expect(
    state.files[state.tool_calls[1].workspace] == nil,
    "synchronously reaped invalid handle leaked its run"
  )
end

do
  local workflow, state, helpers = fixture({ timer_exception = "timer exploded" })
  workflow.enter()
  expect(workflow.run() == false, "timer failure reported a successful launch")
  local process = state.processes[1]
  eq(process.kill_signals, { 15, 9 }, "timer failure did not bound process termination")
  helpers.trigger_exit(process, { code = 143, signal = 15 })
  expect(state.files[state.tool_calls[1].workspace] == nil, "timer failure leaked a run directory")
end

do
  local workflow, state, helpers = fixture({ kill_exception = "kill exploded" })
  workflow.enter()
  workflow.run()
  expect(workflow.cancel() == true, "kill exception escaped manual cancellation")
  helpers.trigger_exit(state.processes[1], { code = 143, signal = 15 })
  expect(state.files[state.tool_calls[1].workspace] == nil, "kill exception leaked a run directory")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  expect(workflow.run() == true, "successful query did not spawn")
  local process = state.processes[1]
  local result = helpers.add_result(process, nil)
  helpers.trigger_exit(process)
  expect(#state.open_calls == 1, "successful result did not open VisiData")
  local opened = state.open_calls[1]
  expect(opened.path == result, "VisiData received the wrong result")
  expect(opened.options.return_buffer == scratch, "viewer return buffer is not the SQL scratch")
  expect(opened.options.return_buffer ~= opened.placeholder, "placeholder used as return buffer")
  expect(state.files[result] ~= nil, "result was removed before viewer completion")
  helpers.trigger_exit(process, { code = 9, signal = 9 })
  expect(#state.open_calls == 1, "duplicate exit callback opened another viewer")
  opened.options.on_complete({ reason = "exit", code = 0 })
  expect(state.files[result] == nil, "result survived viewer completion")
  opened.options.on_complete({ reason = "wipe" })
end

do
  local workflow, state, helpers = fixture({ viewer_replace = true })
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  local result = helpers.add_result(process)
  helpers.trigger_exit(process)
  local opened = state.open_calls[1]
  expect(opened.terminal ~= opened.placeholder, "viewer reused the private placeholder as terminal")
  expect(opened.terminal ~= scratch, "viewer replaced the SQL scratch buffer itself")
  expect(state.windows[101].buffer == opened.terminal, "viewer success did not replace the handoff")
  state.windows[101].buffer = scratch
  opened.options.on_complete({ reason = "exit", code = 0 })
  expect(state.windows[101].buffer == scratch, "viewer success did not restore the SQL scratch")
  expect(state.files[result] == nil, "restored viewer retained its private result")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  process.options.stdout(nil, string.rep("x", 65536))
  process.options.stdout(nil, "y")
  eq(process.kill_signals, { 15 }, "stdout overflow did not terminate the child")
  helpers.trigger_exit(process, { code = 143, signal = 15 })
  expect(#state.open_calls == 0, "overflow output opened a result")
  expect(latest_message(state):find("65,536", 1, true) ~= nil, "overflow reason was lost")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  process.options.stderr(nil, string.rep("e", 65536))
  process.options.stderr(nil, "overflow")
  process.options.stderr(nil, "MUST-NOT-APPEND")
  eq(process.kill_signals, { 15 }, "stderr overflow did not terminate the child")
  helpers.trigger_exit(process, { code = 143, signal = 15 })
  local message = latest_message(state)
  expect(message:find("standard error", 1, true) ~= nil, "stderr overflow reason was lost")
  expect(message:find("MUST-NOT-APPEND", 1, true) == nil, "stderr appended after overflow")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  local request = state.tool_calls[1]
  local unrelated = { kill_signals = {} }
  state.buffers[scratch].valid = false
  state.wipe_callbacks[scratch]()
  eq(process.kill_signals, { 15 }, "scratch wipe did not cancel its query")
  eq(unrelated.kill_signals, {}, "scratch wipe signalled an unrelated job")
  helpers.trigger_exit(process, { code = 143, signal = 15 })
  expect(state.files[request.workspace] == nil, "scratch wipe leaked its run workspace")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  state.timers[1].callback()
  eq(process.kill_signals, { 15 }, "timeout did not terminate the child")
  helpers.trigger_exit(process, { code = 143, signal = 15 })
  expect(latest_message(state):lower():find("timed out", 1, true) ~= nil, "timeout notification")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  process.options.stderr(nil, "failure\r\1\nLINE 2: bad input\tkept" .. string.rep("x", 5000))
  helpers.trigger_exit(process, { code = 2, signal = 0 })
  eq(state.windows[101].cursor, { 2, 0 }, "DuckDB LINE diagnostic did not move the scratch cursor")
  local message = latest_message(state)
  expect(message:find("\r", 1, true) == nil, "notification retained a carriage return")
  expect(message:find("\1", 1, true) == nil, "notification retained a control byte")
  expect(state.buffers[scratch].valid, "diagnostic failure deleted the SQL scratch")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  expect(workflow.back() == true, "back during query failed")
  expect(state.windows[101].buffer == helpers.source_buffer, "back did not restore immediately")
  helpers.add_result(process, nil)
  helpers.trigger_exit(process)
  expect(
    state.windows[101].buffer == helpers.source_buffer,
    "late callback stole the source window"
  )
  expect(#state.open_calls == 0, "late cancelled result opened")
  expect(state.buffers[scratch].valid, "back discarded the retained scratch")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  local result = helpers.add_result(process, {
    ok = true,
    result = state.tool_calls[1].result,
    rows = 100000,
    truncated = true,
    version = 1,
  })
  helpers.trigger_exit(process)
  expect(state.notifications[1].message:find("100,000%-row cap") ~= nil, "truncation notice")
  state.open_calls[1].options.on_complete({ reason = "exit", code = 0 })
  expect(state.files[result] == nil, "truncated result cleanup")
end

local invalid_successes = {
  {
    label = "extra key",
    payload = { extra = true, ok = true, rows = 1, truncated = false, version = 1 },
  },
  { label = "negative rows", payload = { ok = true, rows = -1, truncated = false, version = 1 } },
  {
    label = "fractional rows",
    payload = { ok = true, rows = 1.5, truncated = false, version = 1 },
  },
  {
    label = "rows above cap",
    payload = { ok = true, rows = 100001, truncated = false, version = 1 },
  },
  { label = "nonboolean success", payload = { ok = 1, rows = 1, truncated = false, version = 1 } },
  {
    label = "nonboolean truncation",
    payload = { ok = true, rows = 1, truncated = 1, version = 1 },
  },
  { label = "bad truncation", payload = { ok = true, rows = 2, truncated = true, version = 1 } },
}
for _, case in ipairs(invalid_successes) do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  local request = state.tool_calls[1]
  case.payload.result = request.result
  helpers.add_result(process, case.payload)
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, case.label .. " success record opened a viewer")
  expect(state.files[request.result] == nil, case.label .. " result survived rejection")
end

for _, case in ipairs({
  { label = "empty stdout", stdout = "" },
  { label = "multiple records", stdout = "{}\n{}\n" },
  { label = "invalid JSON", stdout = "{invalid}\n" },
  { label = "missing keys", stdout = vim.json.encode({ ok = true, version = 1 }) .. "\n" },
  {
    label = "wrong result path",
    payload = {
      ok = true,
      result = "/outside/result.parquet",
      rows = 1,
      truncated = false,
      version = 1,
    },
  },
  {
    label = "wrong version",
    payload = { ok = true, rows = 1, truncated = false, version = 2 },
  },
  {
    label = "false success",
    payload = { ok = false, rows = 1, truncated = false, version = 1 },
  },
}) do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  local request = state.tool_calls[1]
  if case.payload then
    if case.payload.result == nil then
      case.payload.result = request.result
    end
    process.options.stdout(nil, vim.json.encode(case.payload) .. "\n")
  elseif case.stdout ~= "" then
    process.options.stdout(nil, case.stdout)
  end
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, case.label .. " opened a viewer")
  expect(state.files[request.workspace] == nil, case.label .. " leaked a run workspace")
end

for _, exit_result in ipairs({
  { code = 2, signal = 0 },
  { code = 0, signal = 15 },
  { code = 0, signal = false },
  { code = false, signal = 0 },
  { code = 0, signal = -1 },
}) do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  helpers.add_result(process)
  helpers.trigger_exit(process, exit_result)
  expect(#state.open_calls == 0, "non-success process status opened a viewer")
end

for _, case in ipairs({
  { label = "symlink", result = { type = "link" } },
  { label = "foreign owner", result = { uid = 2000 } },
  { label = "wrong mode", result = { mode = 33188 } },
  { label = "empty file", result = { size = 0 } },
  { label = "oversized file", result = { size = 1073741825 } },
  { label = "canonical escape", result = { realpath = "/outside/result.parquet" } },
}) do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  local request = state.tool_calls[1]
  helpers.add_result(process, nil, case.result)
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, case.label .. " result opened a viewer")
  expect(
    state.files[request.workspace] == nil,
    case.label .. " result workspace survived rejection"
  )
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  helpers.add_result(process)
  process.options.stderr(nil, "unexpected diagnostic")
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, "success output with stderr opened a viewer")
end

do
  local workflow, state, helpers = fixture({ viewer_failure = true })
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  local result = helpers.add_result(process)
  helpers.trigger_exit(process)
  expect(state.files[result] == nil, "viewer startup failure retained its result")
  expect(state.windows[101].buffer == scratch, "viewer startup failure did not restore the scratch")
end

do
  local workflow =
    fixture({ notify_exception = "notify exploded", source = "/data/unsupported.json" })
  local call_ok, entered = pcall(workflow.enter)
  expect(call_ok and entered == false, "notification exception escaped source rejection")
end

do
  local workflow, state, helpers = fixture({ schedule_exception = "schedule exploded" })
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  helpers.add_result(process)
  helpers.trigger_exit(process)
  expect(#state.open_calls == 1, "scheduler exception lost a reaped result callback")
  state.open_calls[1].options.on_complete({ reason = "exit", code = 0 })
end

do
  local workflow, state, helpers = fixture({ viewer_exception = "viewer exploded" })
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  local result = helpers.add_result(process)
  helpers.trigger_exit(process)
  expect(state.files[result] == nil, "viewer callback exception retained the result")
  expect(state.windows[101].buffer == scratch, "viewer callback exception did not restore scratch")
end

do
  local workflow, state, helpers = fixture({ placeholder_option_exception = "bufhidden" })
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  local result = helpers.add_result(process)
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, "invalid placeholder options reached the viewer")
  expect(state.files[result] == nil, "placeholder option failure retained the result")
  expect(state.windows[101].buffer == scratch, "placeholder option failure moved the scratch")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  local result = helpers.add_result(process)
  state.buffers[2] = {
    lines = { "newer" },
    name = "/data/newer.txt",
    options = { buftype = "", filetype = "text", modified = false },
    valid = true,
    vars = {},
  }
  state.windows[101].buffer = 2
  helpers.trigger_exit(process)
  expect(state.windows[101].buffer == 2, "completed query stole a moved owner window")
  expect(#state.open_calls == 0, "completed query opened after owner movement")
  expect(state.files[result] == nil, "moved owner retained an unviewed result")
end

do
  local workflow, state, helpers = fixture({ viewer_failure = true, viewer_move_to = 2 })
  state.buffers[2] = {
    lines = { "newer" },
    name = "/data/newer.txt",
    options = { buftype = "", filetype = "text", modified = false },
    valid = true,
    vars = {},
  }
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  helpers.add_result(process)
  helpers.trigger_exit(process)
  expect(state.windows[101].buffer == 2, "viewer failure stole a moved handoff window")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  local scratch = state.windows[101].buffer
  workflow.run()
  local process = state.processes[1]
  local result = helpers.add_result(process)
  helpers.trigger_exit(process)
  state.buffers[scratch].valid = false
  state.wipe_callbacks[scratch]()
  expect(state.files[result] ~= nil, "scratch wipe removed a result still owned by the viewer")
  state.open_calls[1].options.on_complete({ reason = "wipe" })
  expect(state.files[result] == nil, "viewer wipe did not clean a deleted scratch's result")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  helpers.add_result(process)
  state.realpaths[helpers.source] = "/data/replacement.parquet"
  state.files["/data/replacement.parquet"] = vim.deepcopy(source_metadata)
  state.readable[helpers.source] = true
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, "retargeted displayed path opened a stale result")
end

do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  helpers.add_result(process)
  state.files[helpers.source].mtime.nsec = 456789001
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, "changed source opened a stale result")
end

for _, mutation in ipairs({
  function(metadata)
    metadata.dev = metadata.dev + 1
  end,
  function(metadata)
    metadata.ino = metadata.ino + 1
  end,
  function(metadata)
    metadata.mode = metadata.mode + 1
  end,
  function(metadata)
    metadata.size = metadata.size + 1
  end,
  function(metadata)
    metadata.mtime.sec = metadata.mtime.sec + 1
  end,
  function(metadata)
    metadata.mtime.nsec = metadata.mtime.nsec + 1
  end,
}) do
  local workflow, state, helpers = fixture()
  workflow.enter()
  workflow.run()
  local process = state.processes[1]
  helpers.add_result(process)
  mutation(state.files[helpers.source])
  helpers.trigger_exit(process)
  expect(#state.open_calls == 0, "changed fingerprint field opened a stale result")
end

do
  local options = {}
  local workflow, state, helpers = fixture(options)
  local first, second, first_request, second_request = start_two_queries(workflow, state)
  options.wait_hooks = {
    [1] = function()
      helpers.trigger_exit(first, { code = 143, signal = 15 })
      helpers.trigger_exit(second, { code = 143, signal = 15 })
    end,
  }
  workflow.shutdown()
  eq(first.kill_signals, { 15 }, "TERM batch signalled the first process incorrectly")
  eq(second.kill_signals, { 15 }, "TERM batch signalled the second process incorrectly")
  eq(state.wait_calls, { { kind = "batch", milliseconds = 500 } }, "TERM batch wait contract")
  expect(state.files[first_request.workspace] == nil, "reaped first run survived shutdown")
  expect(state.files[second_request.workspace] == nil, "reaped second run survived shutdown")
  expect(
    state.files["/cache/dotfiles-data-query/instance-v1-" .. string.rep("11", 16)] == nil,
    "fully reaped shutdown left its instance workspace"
  )
end

do
  local options = {}
  local workflow, state, helpers = fixture(options)
  local first, second, first_request, second_request = start_two_queries(workflow, state)
  options.wait_hooks = {
    [1] = function()
      helpers.trigger_exit(first, { code = 143, signal = 15 })
    end,
  }
  workflow.shutdown()
  eq(first.kill_signals, { 15 }, "reaped TERM child received SIGKILL")
  eq(second.kill_signals, { 15, 9 }, "TERM survivor did not receive explicit SIGKILL")
  eq(state.wait_calls, {
    { kind = "batch", milliseconds = 500 },
    { kind = "batch", milliseconds = 500 },
  }, "shutdown waited sequentially instead of in two batches")
  expect(state.files[first_request.workspace] == nil, "proven-reaped run survived")
  expect(state.files[second_request.workspace] ~= nil, "unreaped survivor workspace was deleted")
  expect(
    state.files["/cache/dotfiles-data-query/instance-v1-" .. string.rep("11", 16)] ~= nil,
    "instance containing an ambiguous survivor was deleted"
  )
end

do
  local options = {}
  local workflow, state, helpers = fixture(options)
  local first, second, first_request, second_request = start_two_queries(workflow, state)
  options.wait_hooks = {
    [2] = function()
      helpers.trigger_exit(first, { code = 137, signal = 9 })
      helpers.trigger_exit(second, { code = 137, signal = 9 })
    end,
  }
  workflow.shutdown()
  eq(first.kill_signals, { 15, 9 }, "first KILL-phase signal contract")
  eq(second.kill_signals, { 15, 9 }, "second KILL-phase signal contract")
  expect(state.files[first_request.workspace] == nil, "KILL-reaped first run survived")
  expect(state.files[second_request.workspace] == nil, "KILL-reaped second run survived")
  expect(
    state.files["/cache/dotfiles-data-query/instance-v1-" .. string.rep("11", 16)] == nil,
    "KILL-reaped instance survived"
  )
end

do
  local options = { wait_exception_at = 1 }
  local workflow, state = fixture(options)
  local first, second, first_request, second_request = start_two_queries(workflow, state)
  workflow.shutdown()
  eq(first.kill_signals, { 15, 9 }, "wait exception skipped first forced signal")
  eq(second.kill_signals, { 15, 9 }, "wait exception skipped second forced signal")
  expect(state.files[first_request.workspace] ~= nil, "wait failure fabricated first reap")
  expect(state.files[second_request.workspace] ~= nil, "wait failure fabricated second reap")
  expect(
    state.files["/cache/dotfiles-data-query/instance-v1-" .. string.rep("11", 16)] ~= nil,
    "wait failure deleted the ambiguous instance"
  )
end

do
  local adapters = workflow_module._test
  expect(
    type(adapters.supervised_command) == "function",
    "query supervisor command adapter is missing"
  )
  expect(type(adapters.spawn) == "function", "query supervisor spawn adapter is missing")
  if vim.uv.os_uname().sysname == "Linux" then
    local python = vim.fn.exepath("python3")
    expect(python ~= "", "production supervisor regression requires python3")
    local directory = vim.fn.tempname()
    expect(vim.fn.mkdir(directory, "p", 448) == 1, "could not create supervisor regression root")
    local helper = vim.fs.joinpath(directory, "fake-bwrap")
    local identities = vim.fs.joinpath(directory, "identities")
    local script = {
      "#!" .. python,
      "import os, signal, sys, time",
      "def ticks(pid):",
      "    value = open('/proc/%d/stat' % pid, encoding='ascii').read()",
      "    return value[value.rfind(')') + 1:].split()[19]",
      "def record():",
      "    pid = os.getpid()",
      "    with open(sys.argv[sys.argv.index('--pid-file') + 1], 'a', encoding='ascii') as stream:",
      "        stream.write('%d:%s\\n' % (pid, ticks(pid)))",
      "monitor = os.fork()",
      "if monitor == 0:",
      "    worker = os.fork()",
      "    if worker == 0:",
      "        record()",
      "        while True: time.sleep(1)",
      "    record()",
      "    while True: time.sleep(1)",
      "record()",
      "time.sleep(1)",
      "if '--never-ready' not in sys.argv:",
      "    fd = int(sys.argv[sys.argv.index('--json-status-fd') + 1])",
      "    os.write(fd, ('{\"child-pid\":%d}\\n' % monitor).encode('ascii'))",
      "while True: time.sleep(1)",
    }
    expect(vim.fn.writefile(script, helper, "b") == 0, "could not write fake Bubblewrap")
    expect(vim.uv.fs_chmod(helper, 448), "could not make fake Bubblewrap executable")

    local command = adapters.supervised_command(python, {
      helper,
      "--pid-file",
      identities,
      "--never-ready",
    })
    local stdout = ""
    local stderr = ""
    local result
    local handle = adapters.spawn(command, {
      clear_env = true,
      env = {},
      stdin = "SELECT 1;",
      stdout = function(err, data)
        expect(err == nil, "supervisor stdout callback failed")
        stdout = stdout .. (data or "")
      end,
      stderr = function(err, data)
        expect(err == nil, "supervisor stderr callback failed")
        stderr = stderr .. (data or "")
      end,
      text = false,
    }, function(value)
      result = value
    end)
    handle:kill(15)
    expect(
      vim.wait(5000, function()
        if result then
          return true
        end
        local ok, recorded = pcall(vim.fn.readfile, identities)
        return ok and #recorded == 3
      end, 10),
      "supervisor regression did not create its complete process tree"
    )
    expect(result == nil, "pre-readiness TERM exited before escalation")
    handle:kill(9)
    expect(
      vim.wait(5000, function()
        return result ~= nil
      end, 10),
      "immediate cancellation did not reap the supervised sandbox tree"
    )
    expect(stdout == "", "supervisor readiness marker leaked into query stdout")
    expect(stderr == "", "supervisor wrote an unexpected diagnostic: " .. stderr)
    local recorded = vim.fn.readfile(identities)
    expect(#recorded == 3, "supervisor regression did not create its complete process tree")
    for _, identity in ipairs(recorded) do
      local pid, ticks = identity:match("^(%d+):(%d+)$")
      local current = adapters.process_start_ticks(tonumber(pid))
      expect(
        current == nil or current ~= tonumber(ticks),
        "supervisor left an owned sandbox process alive: " .. identity
      )
    end
    expect(vim.uv.fs_unlink(identities), "could not remove supervisor identity fixture")
    expect(vim.uv.fs_unlink(helper), "could not remove fake Bubblewrap")
    expect(vim.uv.fs_rmdir(directory), "could not remove supervisor regression root")
  end
end

print("data query workflow assertions: ok")
