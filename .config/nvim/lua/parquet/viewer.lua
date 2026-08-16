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
    if type(bufnr) ~= "number" or bufnr == excluded then
      return false
    end
    local ok, valid = pcall(deps.buffer_valid, bufnr)
    return ok and valid == true
  end

  local function return_buffer(placeholder)
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

  local function fail_open(winid, placeholder, target, target_owned, message)
    local restored = restore(winid, placeholder, target)
    if not restored then
      release_owned_return(target, target_owned)
    end
    delete_if_hidden(placeholder)
    safe_notify("Parquet viewer failed: " .. message, deps.levels.ERROR)
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

  local function finish(terminal, code, startup_placeholder)
    local session = sessions[terminal]
    if not session or not detach(session) then
      return
    end

    local restored = restore(session.window, terminal, session.return_buffer)
    if not restored and startup_placeholder then
      restored = restore(session.window, startup_placeholder, session.return_buffer)
    end
    if restored then
      session.return_buffer_owned = false
    else
      release_owned_return(session.return_buffer, session.return_buffer_owned)
    end
    delete_if_hidden(terminal)
    if startup_placeholder then
      delete_if_hidden(startup_placeholder)
    end
    if code ~= 0 and not safe_exiting() then
      safe_notify("Parquet viewer exited with status " .. tostring(code), deps.levels.WARN)
    end
  end

  local function fail_started(session, placeholder, message)
    detach(session)
    stop_session(session)
    local restored = restore(session.window, session.terminal, session.return_buffer)
    if not restored then
      restored = restore(session.window, placeholder, session.return_buffer)
    end
    if restored then
      session.return_buffer_owned = false
    else
      release_owned_return(session.return_buffer, session.return_buffer_owned)
    end
    delete_if_hidden(session.terminal)
    delete_if_hidden(placeholder)
    safe_notify("Parquet viewer failed: " .. message, deps.levels.ERROR)
    return false
  end

  local function handle_exit(terminal, exit_code)
    local active = sessions[terminal]
    if not active or active.finished then
      return
    end
    if active.starting then
      if not active.exit_pending then
        active.exit_code = exit_code
        active.exit_pending = true
      end
      return
    end
    finish(terminal, exit_code)
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

  local function open(placeholder, requested)
    local window_ok, winid = pcall(deps.current_window)
    if not window_ok or type(winid) ~= "number" or winid <= 0 then
      notify_ownership_failure("could not resolve the current window")
      return false
    end
    if not valid_buffer(placeholder) or not window_owns(winid, placeholder) then
      notify_ownership_failure("current window no longer owns the Parquet placeholder")
      return false
    end

    local target, target_owned, target_error = return_buffer(placeholder)
    if not target then
      notify_ownership_failure(target_error)
      return false
    end
    local path = nonempty(requested)
    if not path or path:match("^%a[%w+.-]*://") then
      return fail_open(winid, placeholder, target, target_owned, "only local files are supported")
    end
    if path:sub(-8) ~= ".parquet" then
      return fail_open(winid, placeholder, target, target_owned, "path must end in .parquet")
    end

    local absolute_ok, absolute = pcall(deps.abspath, path)
    if not absolute_ok or not safe_absolute_parquet(absolute) then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "path must resolve to a safe absolute local .parquet file"
      )
    end
    local normalize_ok, normalized = pcall(deps.normalize, absolute, { expand_env = false })
    if not normalize_ok or not safe_absolute_parquet(normalized) then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "path must normalize to a safe absolute local .parquet file"
      )
    end
    path = normalized
    local stat_ok, stat = pcall(deps.stat, path)
    if not stat_ok then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "could not inspect file: " .. tostring(stat)
      )
    end
    if not stat then
      return fail_open(winid, placeholder, target, target_owned, "file does not exist: " .. path)
    end
    if type(stat) ~= "table" then
      return fail_open(winid, placeholder, target, target_owned, "file metadata is invalid")
    end
    if stat.type ~= "file" then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "path is not a regular file: " .. path
      )
    end
    local readable_ok, readable = pcall(deps.file_readable, path)
    if not readable_ok then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "could not check file readability: " .. tostring(readable)
      )
    end
    if readable ~= true then
      return fail_open(winid, placeholder, target, target_owned, "file is not readable: " .. path)
    end

    local viewer_ok, executable, tool_error = pcall(deps.viewer)
    if not viewer_ok then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "viewer executable resolution failed: " .. tostring(executable)
      )
    end
    if not executable then
      return fail_open(winid, placeholder, target, target_owned, tostring(tool_error))
    end
    if not safe_absolute(executable) then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "viewer executable must be a safe absolute path"
      )
    end
    local executable_ok, executable_state = pcall(deps.executable, executable)
    if not executable_ok or executable_state ~= 1 then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "viewer executable is unavailable or not executable"
      )
    end

    local cwd_ok, cwd = pcall(deps.dirname, path)
    if not cwd_ok or not safe_absolute_directory(cwd) then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "viewer working directory must be a safe absolute path"
      )
    end
    if not window_owns(winid, placeholder) then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "current window no longer owns the Parquet placeholder"
      )
    end

    local terminal_ok, terminal = pcall(deps.create_buffer, false, true)
    if not terminal_ok or terminal == target or not valid_buffer(terminal, placeholder) then
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "could not create a valid terminal buffer"
      )
    end
    if not window_owns(winid, placeholder) then
      delete_if_hidden(terminal)
      return fail_open(
        winid,
        placeholder,
        target,
        target_owned,
        "current window no longer owns the Parquet placeholder after terminal allocation"
      )
    end
    local session = {
      exit_pending = false,
      finished = false,
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
      return true
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
      return true
    end

    local wipe_ok, wipe_error = pcall(deps.on_wipe, terminal, function()
      local active = sessions[terminal]
      if not active or not detach(active) then
        return
      end
      stop_session(active)
      release_owned_return(active.return_buffer, active.return_buffer_owned)
      active.return_buffer_owned = false
    end)
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
      return true
    end

    local delete_ok, delete_error = delete_if_hidden(placeholder)
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
      return true
    end
    if not window_owns(winid, terminal) then
      return fail_started(session, placeholder, "current window no longer owns the terminal")
    end

    session.starting = false
    return true
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
  levels = vim.log.levels,
  normalize = vim.fs.normalize,
  notify = vim.notify,
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
