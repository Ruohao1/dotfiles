local M = {}

local function nonempty(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function safe_absolute(path)
  return type(path) == "string"
    and path ~= ""
    and path ~= "/"
    and path:sub(1, 1) == "/"
    and path:find("%c") == nil
end

local function safe_absolute_parquet(path)
  return safe_absolute(path) and path:sub(-8) == ".parquet"
end

local function safe_absolute_directory(path)
  return type(path) == "string" and path ~= "" and path:sub(1, 1) == "/" and path:find("%c") == nil
end

local function new(deps)
  local configured = false
  local sessions = {}

  local function safe_notify(message, level)
    pcall(deps.notify, message, level)
  end

  local function safe_exiting()
    local ok, exiting = pcall(deps.exiting)
    return ok and exiting == true
  end

  local function notify_ownership_failure(message)
    safe_notify("Parquet viewer failed: " .. message, deps.levels.ERROR)
  end

  local function valid_buffer(bufnr, excluded)
    if type(bufnr) ~= "number" or bufnr <= 0 or bufnr == excluded then
      return false
    end
    local ok, valid = pcall(deps.buffer_valid, bufnr)
    return ok and valid == true
  end

  local function normalize_options(options)
    if options == nil then
      return {}, nil
    end
    if type(options) ~= "table" then
      return nil, "viewer options must be a table"
    end
    if options.on_complete ~= nil and type(options.on_complete) ~= "function" then
      return nil, "on_complete must be a function"
    end
    return options, nil
  end

  local function completion_callback(callback)
    if callback == nil then
      return nil
    end
    local completed = false
    return function(event)
      if completed then
        return
      end
      completed = true
      pcall(callback, event)
    end
  end

  local function return_buffer(placeholder, options)
    if options.return_buffer ~= nil then
      if not valid_buffer(options.return_buffer, placeholder) then
        return nil, false, "return_buffer must be a valid buffer distinct from the placeholder"
      end
      return options.return_buffer, false
    end
    local alternate_ok, alternate = pcall(deps.alternate_buffer)
    if not alternate_ok then
      return nil, false, "could not resolve the alternate buffer: " .. tostring(alternate)
    end
    if valid_buffer(alternate, placeholder) then
      return alternate, false
    end
    local create_ok, created = pcall(deps.create_buffer, false, true)
    if not create_ok then
      return nil, false, "could not create a return scratch: " .. tostring(created)
    end
    if not valid_buffer(created, placeholder) then
      return nil, false, "could not create a valid return scratch"
    end
    return created, true
  end

  local function window_owns(winid, bufnr)
    local window_ok, window_valid = pcall(deps.window_valid, winid)
    if not window_ok or not window_valid then
      return false
    end
    local buffer_ok, current = pcall(deps.window_buffer, winid)
    return buffer_ok and current == bufnr
  end

  local function delete_if_hidden(bufnr)
    if not valid_buffer(bufnr) then
      return true
    end
    local windows_ok, windows = pcall(deps.find_windows, bufnr)
    if not windows_ok or type(windows) ~= "table" then
      return false, tostring(windows)
    end
    if #windows > 0 then
      return true
    end
    local delete_ok, delete_error = pcall(deps.delete_buffer, bufnr, { force = true })
    return delete_ok, delete_error
  end

  local function restore(winid, owned_buffer, target)
    if not window_owns(winid, owned_buffer) then
      return false
    end

    local destination = valid_buffer(target, owned_buffer) and target or nil
    local fallback_owned = false
    if not destination then
      local create_ok, created = pcall(deps.create_buffer, false, true)
      if not create_ok or not valid_buffer(created, owned_buffer) then
        return false
      end
      destination = created
      fallback_owned = true
    end
    local set_ok = pcall(deps.set_window_buffer, winid, destination)
    local restored = set_ok and window_owns(winid, destination)
    if not restored and fallback_owned then
      delete_if_hidden(destination)
    end
    return restored
  end

  local function release_owned_return(target, owned)
    if owned then
      delete_if_hidden(target)
    end
  end

  local function complete(completion, event)
    if completion then
      completion(event)
    end
  end

  local function fail_open(winid, placeholder, target, target_owned, message, completion)
    local restored = restore(winid, placeholder, target)
    if not restored then
      release_owned_return(target, target_owned)
    end
    delete_if_hidden(placeholder)
    safe_notify("Parquet viewer failed: " .. message, deps.levels.ERROR)
    complete(completion, { reason = "startup-failure" })
    return false
  end

  local function stop_session(session)
    if
      session.job_stopped
      or session.exit_pending
      or type(session.job) ~= "number"
      or session.job <= 0
    then
      return
    end
    session.job_stopped = true
    pcall(deps.stop_job, session.job)
  end

  local function detach(session)
    if session.finished then
      return false
    end
    session.finished = true
    if sessions[session.terminal] == session then
      sessions[session.terminal] = nil
    end
    return true
  end

  local function finalize(session, event, startup_placeholder, failure_message)
    if not detach(session) then
      return false
    end
    if event.reason == "startup-failure" then
      stop_session(session)
    end

    local restored = restore(session.window, session.terminal, session.return_buffer)
    if not restored and startup_placeholder then
      restored = restore(session.window, startup_placeholder, session.return_buffer)
    end
    if restored then
      session.return_buffer_owned = false
    else
      release_owned_return(session.return_buffer, session.return_buffer_owned)
    end
    delete_if_hidden(session.terminal)
    if startup_placeholder then
      delete_if_hidden(startup_placeholder)
    end
    if failure_message then
      safe_notify("Parquet viewer failed: " .. failure_message, deps.levels.ERROR)
    elseif event.reason == "exit" and event.code ~= 0 and not safe_exiting() then
      safe_notify("Parquet viewer exited with status " .. tostring(event.code), deps.levels.WARN)
    end
    complete(session.completion, event)
    return true
  end

  local function finish(terminal, code, startup_placeholder)
    local session = sessions[terminal]
    if not session then
      return
    end
    local event = { reason = "exit" }
    if type(code) == "number" then
      event.code = code
    end
    finalize(session, event, startup_placeholder)
  end

  local function fail_started(session, placeholder, message)
    finalize(session, { reason = "startup-failure" }, placeholder, message)
    return false
  end

  local function finish_wipe(session, exit_code)
    local event = { reason = "wipe" }
    if type(exit_code) == "number" then
      event.code = exit_code
    end
    finalize(session, event, session.startup_placeholder, session.startup_failure_message)
  end

  local function defer_startup_wipe(session, placeholder, message)
    if not session.programmatic then
      return fail_started(session, placeholder, message)
    end
    session.starting = false
    session.startup_placeholder = placeholder
    session.startup_failure_message = message
    if session.exit_pending then
      finish_wipe(session, session.exit_code)
    end
    return false
  end

  local function handle_exit(terminal, exit_code)
    local active = sessions[terminal]
    if not active or active.finished then
      return
    end
    if active.shutting_down then
      if not active.exit_pending then
        active.exit_code = exit_code
        active.exit_pending = true
      end
      return
    end
    if active.starting then
      if not active.exit_pending then
        active.exit_code = exit_code
        active.exit_pending = true
      end
      return
    end
    if active.wiped then
      finish_wipe(active, exit_code)
    else
      finish(terminal, exit_code)
    end
  end

  local function schedule_exit(terminal, exit_code)
    local callback = function()
      handle_exit(terminal, exit_code)
    end
    local schedule_ok, schedule_result, schedule_error = pcall(deps.schedule, callback)
    if not schedule_ok or type(schedule_result) == "string" or type(schedule_error) == "string" then
      callback()
    end
  end

  local function open(placeholder, requested, raw_options)
    local options, options_error = normalize_options(raw_options)
    if not options then
      notify_ownership_failure(options_error)
      return false
    end
    local completion = completion_callback(options.on_complete)
    local programmatic = raw_options ~= nil
    local function fail_without_transfer(message)
      notify_ownership_failure(message)
      complete(completion, { reason = "startup-failure" })
      return false
    end

    local window_ok, winid = pcall(deps.current_window)
    if not window_ok or type(winid) ~= "number" or winid <= 0 then
      return fail_without_transfer("could not resolve the current window")
    end
    if not valid_buffer(placeholder) or not window_owns(winid, placeholder) then
      return fail_without_transfer("current window no longer owns the Parquet placeholder")
    end

    local target, target_owned, target_error = return_buffer(placeholder, options)
    if not target then
      return fail_without_transfer(target_error)
    end
    local function fail(message)
      return fail_open(winid, placeholder, target, target_owned, message, completion)
    end
    local path = nonempty(requested)
    if not path or path:match("^%a[%w+.-]*://") then
      return fail("only local files are supported")
    end
    if path:sub(-8) ~= ".parquet" then
      return fail("path must end in .parquet")
    end

    local absolute_ok, absolute = pcall(deps.abspath, path)
    if not absolute_ok or not safe_absolute_parquet(absolute) then
      return fail("path must resolve to a safe absolute local .parquet file")
    end
    local normalize_ok, normalized = pcall(deps.normalize, absolute, { expand_env = false })
    if not normalize_ok or not safe_absolute_parquet(normalized) then
      return fail("path must normalize to a safe absolute local .parquet file")
    end
    path = normalized
    local stat_ok, stat = pcall(deps.stat, path)
    if not stat_ok then
      return fail("could not inspect file: " .. tostring(stat))
    end
    if not stat then
      return fail("file does not exist: " .. path)
    end
    if type(stat) ~= "table" then
      return fail("file metadata is invalid")
    end
    if stat.type ~= "file" then
      return fail("path is not a regular file: " .. path)
    end
    local readable_ok, readable = pcall(deps.file_readable, path)
    if not readable_ok then
      return fail("could not check file readability: " .. tostring(readable))
    end
    if readable ~= true then
      return fail("file is not readable: " .. path)
    end

    local viewer_ok, executable, tool_error = pcall(deps.viewer)
    if not viewer_ok then
      return fail("viewer executable resolution failed: " .. tostring(executable))
    end
    if not executable then
      return fail(tostring(tool_error))
    end
    if not safe_absolute(executable) then
      return fail("viewer executable must be a safe absolute path")
    end
    local executable_ok, executable_state = pcall(deps.executable, executable)
    if not executable_ok or executable_state ~= 1 then
      return fail("viewer executable is unavailable or not executable")
    end

    local cwd_ok, cwd = pcall(deps.dirname, path)
    if not cwd_ok or not safe_absolute_directory(cwd) then
      return fail("viewer working directory must be a safe absolute path")
    end
    if not window_owns(winid, placeholder) then
      return fail("current window no longer owns the Parquet placeholder")
    end

    local terminal_ok, terminal = pcall(deps.create_buffer, false, true)
    if not terminal_ok or terminal == target or not valid_buffer(terminal, placeholder) then
      return fail("could not create a valid terminal buffer")
    end
    if not window_owns(winid, placeholder) then
      delete_if_hidden(terminal)
      return fail("current window no longer owns the Parquet placeholder after terminal allocation")
    end
    local session = {
      completion = completion,
      exit_pending = false,
      finished = false,
      programmatic = programmatic,
      return_buffer = target,
      return_buffer_owned = target_owned,
      starting = true,
      terminal = terminal,
      window = winid,
    }
    sessions[terminal] = session

    local started, job = pcall(
      deps.start_terminal,
      winid,
      terminal,
      { executable, "--readonly", path },
      cwd,
      {
        PYTHONHOME = "",
        PYTHONNOUSERSITE = "1",
        PYTHONPATH = "",
        PYTHONDONTWRITEBYTECODE = "1",
      },
      function(exit_code)
        schedule_exit(terminal, exit_code)
      end
    )
    if not started or type(job) ~= "number" or job <= 0 then
      local detail = started and "could not start VisiData"
        or "could not start VisiData: " .. tostring(job)
      return fail_started(session, placeholder, detail)
    end

    session.job = job
    if not window_owns(winid, terminal) then
      return fail_started(
        session,
        placeholder,
        "terminal did not take ownership of the current window"
      )
    end

    if not valid_buffer(terminal) then
      return fail_started(session, placeholder, "terminal buffer was wiped during startup")
    end
    if session.exit_pending then
      session.starting = false
      finish(terminal, session.exit_code, placeholder)
      return true, terminal
    end

    local metadata_ok, metadata_error = pcall(deps.set_metadata, terminal, {
      job = job,
      path = path,
      readonly = true,
      return_buffer = target,
    })
    if not metadata_ok then
      return fail_started(
        session,
        placeholder,
        "metadata setup failed: " .. tostring(metadata_error)
      )
    end
    if not window_owns(winid, terminal) then
      return fail_started(
        session,
        placeholder,
        "current window no longer owns the terminal after metadata setup"
      )
    end
    if session.exit_pending then
      session.starting = false
      finish(terminal, session.exit_code, placeholder)
      return true, terminal
    end

    local wipe_ok, wipe_error = pcall(deps.on_wipe, terminal, function()
      local active = sessions[terminal]
      if not active or active.finished then
        return
      end
      active.wiped = true
      if active.starting or active.programmatic then
        stop_session(active)
        return
      end
      if not detach(active) then
        return
      end
      stop_session(active)
      release_owned_return(active.return_buffer, active.return_buffer_owned)
      active.return_buffer_owned = false
    end)
    if session.wiped then
      return defer_startup_wipe(
        session,
        placeholder,
        "wipe-hook setup failed: terminal buffer was wiped during startup"
      )
    end
    if not wipe_ok then
      return fail_started(session, placeholder, "wipe-hook setup failed: " .. tostring(wipe_error))
    end
    if sessions[terminal] ~= session or session.finished then
      return fail_started(
        session,
        placeholder,
        "wipe-hook setup failed: terminal buffer was wiped during startup"
      )
    end
    if not window_owns(winid, terminal) then
      return fail_started(
        session,
        placeholder,
        "current window no longer owns the terminal after wipe-hook setup"
      )
    end
    if session.exit_pending then
      session.starting = false
      finish(terminal, session.exit_code, placeholder)
      return true, terminal
    end

    local delete_ok, delete_error = delete_if_hidden(placeholder)
    if session.wiped then
      return defer_startup_wipe(
        session,
        placeholder,
        "placeholder cleanup failed: terminal buffer was wiped during startup"
      )
    end
    if not delete_ok then
      return fail_started(
        session,
        placeholder,
        "placeholder cleanup failed: " .. tostring(delete_error)
      )
    end
    if sessions[terminal] ~= session or session.finished then
      return fail_started(
        session,
        placeholder,
        "placeholder cleanup failed: terminal buffer was wiped during startup"
      )
    end
    if not window_owns(winid, terminal) then
      return fail_started(
        session,
        placeholder,
        "current window no longer owns the terminal after placeholder cleanup"
      )
    end

    local insert_ok, insert_error = pcall(deps.start_insert, winid)
    if session.wiped then
      return defer_startup_wipe(
        session,
        placeholder,
        "insert-mode setup failed: terminal buffer was wiped during startup"
      )
    end
    if not insert_ok then
      return fail_started(
        session,
        placeholder,
        "insert-mode setup failed: " .. tostring(insert_error)
      )
    end
    if not window_owns(winid, terminal) then
      return fail_started(
        session,
        placeholder,
        "current window no longer owns the terminal after insert-mode setup"
      )
    end
    if sessions[terminal] ~= session or session.finished then
      return fail_started(
        session,
        placeholder,
        "insert-mode setup failed: terminal buffer was wiped during startup"
      )
    end
    if session.exit_pending then
      session.starting = false
      finish(terminal, session.exit_code, placeholder)
      return true, terminal
    end
    if not window_owns(winid, terminal) then
      return fail_started(session, placeholder, "current window no longer owns the terminal")
    end

    session.starting = false
    pcall(deps.metadata_ready, terminal)
    return true, terminal
  end

  local function wait_for_job(job, timeout)
    local wait_ok, statuses = pcall(deps.wait_jobs, { job }, timeout)
    if not wait_ok or type(statuses) ~= "table" then
      return nil
    end
    return statuses[1]
  end

  local function shutdown()
    local active = {}
    for _, session in pairs(sessions) do
      if session.programmatic and not session.finished then
        active[#active + 1] = session
      end
    end
    table.sort(active, function(left, right)
      return left.terminal < right.terminal
    end)

    for _, session in ipairs(active) do
      if sessions[session.terminal] == session and not session.finished then
        session.shutting_down = true
        stop_session(session)
        local status = wait_for_job(session.job, 500)
        if status == -1 then
          local pid_ok, pid = pcall(deps.job_pid, session.job)
          if pid_ok and type(pid) == "number" and pid > 0 then
            pcall(deps.kill_pid, pid, 9)
          end
          wait_for_job(session.job, 500)
        end
        finalize(session, { reason = "shutdown" }, session.startup_placeholder)
      end
    end
  end

  local function setup()
    if configured then
      return
    end
    local group = deps.create_augroup("dotfiles-parquet-viewer", { clear = true })
    deps.create_autocmd("BufReadCmd", {
      group = group,
      pattern = "*.parquet",
      desc = "Open Parquet files in read-only VisiData",
      callback = function(args)
        open(args.buf, args.file)
      end,
    })
    deps.create_autocmd("VimLeavePre", {
      group = group,
      desc = "Reap managed Parquet result viewers",
      callback = shutdown,
    })
    configured = true
  end

  return { open = open, setup = setup }
end

local runtime = new({
  abspath = vim.fs.abspath,
  alternate_buffer = function()
    return vim.fn.bufnr("#")
  end,
  buffer_valid = vim.api.nvim_buf_is_valid,
  create_augroup = vim.api.nvim_create_augroup,
  create_autocmd = vim.api.nvim_create_autocmd,
  create_buffer = vim.api.nvim_create_buf,
  current_window = vim.api.nvim_get_current_win,
  delete_buffer = vim.api.nvim_buf_delete,
  dirname = vim.fs.dirname,
  exiting = function()
    return type(vim.v.exiting) == "number"
  end,
  executable = vim.fn.executable,
  file_readable = function(path)
    return vim.fn.filereadable(path) == 1
  end,
  find_windows = vim.fn.win_findbuf,
  job_pid = vim.fn.jobpid,
  kill_pid = function(pid, signal)
    return vim.uv.kill(pid, signal)
  end,
  levels = vim.log.levels,
  normalize = vim.fs.normalize,
  notify = vim.notify,
  metadata_ready = function(bufnr)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "DotfilesParquetViewerReady",
      data = { buffer = bufnr },
    })
  end,
  on_wipe = function(bufnr, callback)
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      callback = callback,
      once = true,
    })
  end,
  schedule = vim.schedule,
  set_metadata = function(bufnr, value)
    vim.b[bufnr].dotfiles_parquet_viewer = value
  end,
  set_window_buffer = vim.api.nvim_win_set_buf,
  start_insert = function(winid)
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_call(winid, function()
        vim.cmd.startinsert()
      end)
    end
  end,
  start_terminal = function(winid, bufnr, command, cwd, environment, on_exit)
    return vim.api.nvim_win_call(winid, function()
      vim.api.nvim_win_set_buf(winid, bufnr)
      if vim.api.nvim_win_get_buf(winid) ~= bufnr then
        error("Parquet terminal lost current-window ownership before job start")
      end
      return vim.fn.jobstart(command, {
        cwd = cwd,
        env = environment,
        on_exit = function(_, code)
          on_exit(code)
        end,
        term = true,
      })
    end)
  end,
  stat = vim.uv.fs_stat,
  stop_job = vim.fn.jobstop,
  wait_jobs = vim.fn.jobwait,
  viewer = function()
    return require("parquet.tool").viewer()
  end,
  window_buffer = vim.api.nvim_win_get_buf,
  window_valid = vim.api.nvim_win_is_valid,
})

M.open = runtime.open
M.setup = runtime.setup
M._test = { new = new }

return M
