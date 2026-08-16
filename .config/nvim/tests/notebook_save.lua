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

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

package.loaded["notebook.save"] = nil
local save_module = require("notebook.save")

local notebook_buffer = 17
local original_notebook =
  '{"cells":[],"metadata":{"source":true},"nbformat":4,"nbformat_minor":5}\n'
local exported_notebook =
  '{"cells":[],"metadata":{"exported":true},"nbformat":4,"nbformat_minor":5}\n'
local target = "/real/project space|percent%/notebook.ipynb"
local link = "/project alias/notebook.ipynb"
local target_mode = tonumber("0640", 8)
local regular_type = tonumber("100000", 8)

local function new_fixture(options)
  options = options or {}

  local fixture = {
    buffer = notebook_buffer,
    current_buffer = 999,
    cursor = { 9, 4 },
    descriptors = {},
    directories = {
      ["/real"] = true,
      ["/real/project space|percent%"] = true,
    },
    exported = false,
    files = {
      [link] = "symlink:" .. target,
      [target] = original_notebook,
    },
    jupytext_mtime = { nsec = 21, sec = 300 },
    modified = not options.initially_unmodified,
    metadata = {
      [target] = {
        dev = 8,
        ino = 410,
        mode = regular_type + target_mode,
        mtime = { nsec = 21, sec = 300 },
        size = #original_notebook,
        type = "file",
      },
    },
    modes = {
      [target] = target_mode,
    },
    molten_arguments = {},
    next_descriptor = 30,
    next_inode = 900,
    notifications = {},
    operations = {},
    prompt_calls = 0,
    random_calls = 0,
    remaining_collisions = options.entropy_collisions or 0,
    running = vim.deepcopy(options.running or { "kernel-id" }),
    scheduled = {},
    target_reads = 0,
    target_stats = 0,
    timers = {},
    validation_timeout = nil,
  }

  local function copy(value)
    return value and vim.deepcopy(value) or nil
  end

  if options.target_type then
    fixture.metadata[target].type = options.target_type
  end

  local function add_descriptor(path, role)
    local descriptor = fixture.next_descriptor
    fixture.next_descriptor = descriptor + 1
    fixture.descriptors[descriptor] = {
      path = path,
      role = role,
    }
    return descriptor
  end

  local function raw_stat(path)
    if fixture.directories[path] then
      return {
        dev = 8,
        ino = path == vim.fs.dirname(target) and 80 or 70,
        mode = tonumber("040700", 8),
        mtime = { nsec = 0, sec = 1 },
        size = 0,
        type = "directory",
      }
    end
    return copy(fixture.metadata[path])
  end

  local function is_temp(path)
    local prefix = vim.pesc(vim.fs.dirname(target) .. "/.notebook.ipynb.nvim-molten.")
    local entropy = path:match("^" .. prefix .. "(%x+)%.ipynb$")
    return entropy ~= nil and #entropy == 32
  end

  local function write_export(path)
    fixture.files[path] = exported_notebook
    fixture.metadata[path].size = #exported_notebook
    fixture.metadata[path].mtime = { nsec = 5, sec = 401 }
    fixture.exported = true
    if options.replace_temp_after_export then
      fixture.files[path] = "symlink:/attacker/valuable.ipynb"
      fixture.metadata[path] = nil
    end
  end

  local uv = {}

  function uv.fs_realpath(path)
    fixture.operations[#fixture.operations + 1] = "realpath"
    if options.fail_at == "realpath" then
      return nil, "injected realpath failure"
    end
    if path == link then
      return target
    end
    if fixture.files[path] or fixture.directories[path] then
      return path
    end
    return nil, "ENOENT"
  end

  function uv.fs_stat(path)
    if path == target then
      fixture.target_stats = fixture.target_stats + 1
      fixture.operations[#fixture.operations + 1] = fixture.target_stats == 1 and "snapshot-stat"
        or "target-recheck-stat"
      if fixture.target_stats > 1 and options.fail_at == "target-recheck-stat" then
        return nil, "injected target recheck stat failure"
      end
      if fixture.target_stats > 1 and options.fail_at == "target-stat-throw" then
        error("injected target stat exception")
      end
    end
    local stat = raw_stat(path)
    if path == target and fixture.target_stats > 1 and options.recheck_field then
      if options.recheck_field == "mtime-nsec" then
        stat.mtime.nsec = stat.mtime.nsec + 1
      elseif options.recheck_field == "mtime-sec" then
        stat.mtime.sec = stat.mtime.sec + 1
      else
        stat[options.recheck_field] = stat[options.recheck_field] + 1
      end
    end
    return stat
  end

  function uv.fs_lstat(path)
    if options.fail_at == "temp-lstat-throw" and is_temp(path) then
      error("injected temporary lstat exception")
    end
    local bytes = fixture.files[path]
    if type(bytes) == "string" and bytes:sub(1, 8) == "symlink:" then
      return {
        dev = 8,
        ino = 999,
        mode = tonumber("120777", 8),
        mtime = { nsec = 0, sec = 1 },
        size = #bytes - 8,
        type = "link",
      }
    end
    return raw_stat(path)
  end

  function uv.fs_open(path, flags, mode)
    if flags == "wx" then
      expect(is_temp(path), "temporary filename contract changed: " .. path)
      expect(mode == tonumber("0600", 8), "temporary file was not created with mode 0600")
      if fixture.remaining_collisions > 0 then
        fixture.remaining_collisions = fixture.remaining_collisions - 1
        return nil, "EEXIST: injected entropy collision"
      end
      if options.fail_at == "temp-exclusive-create" then
        return nil, "injected exclusive-create failure"
      end
      fixture.operations[#fixture.operations + 1] = "temp-exclusive-create"
      fixture.files[path] = ""
      fixture.modes[path] = mode
      fixture.next_inode = fixture.next_inode + 1
      fixture.metadata[path] = {
        dev = 8,
        ino = fixture.next_inode,
        mode = regular_type + mode,
        mtime = { nsec = 0, sec = 400 },
        size = 0,
        type = "file",
      }
      fixture.temp = path
      return add_descriptor(path, "temp-copy")
    end

    if fixture.directories[path] then
      return add_descriptor(path, "directory")
    end
    if fixture.files[path] ~= nil then
      local role = is_temp(path) and "temp-flush" or "target-read"
      return add_descriptor(path, role)
    end
    return nil, "ENOENT"
  end

  function uv.fs_fstat(descriptor)
    local handle = fixture.descriptors[descriptor]
    if not handle then
      return nil, "EBADF"
    end
    return raw_stat(handle.path)
  end

  function uv.fs_read(descriptor, length, offset)
    local handle = fixture.descriptors[descriptor]
    if not handle then
      return nil, "EBADF"
    end
    if handle.role == "target-read" and not handle.read_recorded then
      handle.read_recorded = true
      fixture.target_reads = fixture.target_reads + 1
      fixture.operations[#fixture.operations + 1] = fixture.target_reads == 1 and "snapshot-read"
        or "target-recheck-read"
      if fixture.target_reads > 1 and options.fail_at == "target-recheck-read" then
        return nil, "injected target recheck read failure"
      end
    end
    local bytes = fixture.files[handle.path]
    if bytes == nil then
      return nil, "ENOENT"
    end
    if handle.role == "target-read" and fixture.target_reads > 1 and options.recheck_bytes then
      bytes = options.recheck_bytes
    end
    if options.partial_read and length > options.partial_read then
      length = options.partial_read
    end
    return bytes:sub(offset + 1, offset + length)
  end

  function uv.fs_write(descriptor, bytes, offset)
    local handle = fixture.descriptors[descriptor]
    if not handle then
      return nil, "EBADF"
    end
    if not handle.write_recorded then
      handle.write_recorded = true
      fixture.operations[#fixture.operations + 1] = "temp-copy"
    end
    if options.fail_at == "temp-copy" then
      return nil, "injected copy failure"
    end
    if options.partial_write and #bytes > options.partial_write then
      bytes = bytes:sub(1, options.partial_write)
    end
    local current = fixture.files[handle.path] or ""
    fixture.files[handle.path] = current:sub(1, offset) .. bytes .. current:sub(offset + #bytes + 1)
    fixture.metadata[handle.path].size = #fixture.files[handle.path]
    return #bytes
  end

  function uv.fs_fsync(descriptor)
    local handle = fixture.descriptors[descriptor]
    if not handle then
      return nil, "EBADF"
    end
    local operation = ({
      ["directory"] = "parent-fsync",
      ["temp-copy"] = "temp-fsync",
      ["temp-flush"] = "temp-fsync-after-export",
    })[handle.role]
    fixture.operations[#fixture.operations + 1] = operation
    if options.fail_at == operation then
      return nil, "injected " .. operation .. " failure"
    end
    return true
  end

  function uv.fs_close(descriptor)
    local handle = fixture.descriptors[descriptor]
    if not handle then
      return nil, "EBADF"
    end
    if handle.role == "temp-copy" then
      fixture.operations[#fixture.operations + 1] = "temp-close"
      if options.fail_at == "temp-close" and not fixture.close_failed then
        fixture.close_failed = true
        return nil, "injected close failure"
      end
    end
    if options.fail_at == handle.role .. "-close" then
      fixture.descriptors[descriptor] = nil
      return nil, "injected " .. handle.role .. " close failure"
    end
    fixture.descriptors[descriptor] = nil
    return true
  end

  function uv.fs_chmod(path, mode)
    fixture.operations[#fixture.operations + 1] = "temp-chmod"
    if options.fail_at == "temp-chmod" then
      return nil, "injected chmod failure"
    end
    if options.fail_at == "temp-chmod-throw" then
      error("injected chmod exception")
    end
    if not fixture.metadata[path] then
      return nil, "ENOENT"
    end
    fixture.modes[path] = mode
    fixture.metadata[path].mode = regular_type + mode
    return true
  end

  function uv.fs_rename(source, destination)
    fixture.operations[#fixture.operations + 1] = "atomic-rename"
    expect(vim.fs.dirname(source) == vim.fs.dirname(destination), "rename crossed filesystems")
    if options.fail_at == "atomic-rename" then
      return nil, "injected rename failure"
    end
    fixture.files[destination] = fixture.files[source]
    fixture.modes[destination] = fixture.modes[source]
    fixture.metadata[destination] = fixture.metadata[source]
    fixture.files[source] = nil
    fixture.modes[source] = nil
    fixture.metadata[source] = nil
    fixture.temp = nil
    return true
  end

  function uv.fs_unlink(path)
    if options.fail_at == "cleanup-unlink" then
      return nil, "injected unlink failure"
    end
    fixture.files[path] = nil
    fixture.modes[path] = nil
    fixture.metadata[path] = nil
    if fixture.temp == path then
      fixture.temp = nil
    end
    return true
  end

  function uv.random(length)
    fixture.random_calls = fixture.random_calls + 1
    expect(length == 16, "temporary name must use 128 bits of entropy")
    if options.fail_at == "entropy-throw" then
      error("injected entropy exception")
    end
    if options.fail_at == "entropy-short" then
      return "short"
    end
    return string.rep(string.char(64 + fixture.random_calls), length)
  end

  local dependencies = {
    buf_call = function(bufnr, callback)
      expect(bufnr == notebook_buffer, "save targeted the wrong buffer")
      local previous = fixture.current_buffer
      fixture.current_buffer = bufnr
      local ok, result = pcall(callback)
      fixture.current_buffer = previous
      if not ok then
        error(result)
      end
      return result
    end,
    buf_name = function(bufnr)
      expect(bufnr == notebook_buffer, "save requested the wrong buffer name")
      return link
    end,
    buf_modified = function(bufnr)
      expect(bufnr == notebook_buffer, "save checked modified state for the wrong buffer")
      return fixture.modified
    end,
    fs = {
      basename = vim.fs.basename,
      dirname = vim.fs.dirname,
      normalize = vim.fs.normalize,
    },
    notify = function(message, level)
      fixture.notifications[#fixture.notifications + 1] = {
        level = level,
        message = tostring(message),
      }
    end,
    nvim_cmd = function(command)
      if command.cmd == "write" then
        if command.bang then
          local installed_mtime = fixture.metadata[target].mtime
          if
            type(fixture.jupytext_mtime) ~= "table"
            or fixture.jupytext_mtime.sec ~= installed_mtime.sec
          then
            fixture.prompt_calls = fixture.prompt_calls + 1
            error("interactive changed-file prompt would open")
          end
          fixture.operations[#fixture.operations + 1] = "buffer-write-force"
          if options.fail_at == "buffer-write-force" then
            error("injected timestamp sync failure")
          end
        else
          fixture.operations[#fixture.operations + 1] = "buffer-write"
          if options.fail_at == "buffer-write" then
            error("injected source write failure")
          end
          if options.fail_at == "buffer-write-noop" then
            return
          end
          fixture.modified = false
        end
        return
      end
      expect(command.cmd == "MoltenExportOutput", "unexpected save command: " .. command.cmd)
      expect(
        fixture.current_buffer == notebook_buffer,
        "Molten export did not run in the originating notebook buffer"
      )
      if #command.args == 2 then
        fixture.selected_command = vim.deepcopy(command)
        expect(command.args[1] == fixture.temp, "selected export lost the raw temporary path")
        expect(
          vim.tbl_contains(fixture.running, command.args[2]),
          "Molten selected an unknown kernel"
        )
        if options.fail_at == "selected-export" then
          error("injected selected export failure")
        end
        write_export(command.args[1])
        return
      end
      fixture.operations[#fixture.operations + 1] = "molten-export-bang"
      fixture.molten_arguments = vim.deepcopy(command)
      if options.fail_at == "molten-export-bang" then
        error("injected Molten export failure")
      end
      fixture.initial_molten_argument = command.args[1]
      local expected_initial = vim.fn.fnameescape(fixture.temp)
      expect(command.args[1] == expected_initial, "initial Molten path was not fnameescaped")
      expect(#command.args == 1, "initial Molten export received an explicit kernel")
      if #fixture.running > 1 then
        local generated_path = expected_initial:gsub("%%k", function()
          return "\\%k"
        end)
        fixture.select_and_run(
          vim.deepcopy(fixture.running),
          "Please select a kernel:",
          options.tamper_generated_command and "MoltenExportOutput! /attacker/notebook.ipynb %k"
            or "MoltenExportOutput! " .. generated_path .. " %k"
        )
        return
      end
      write_export(fixture.temp)
    end,
    python_paths = function()
      return { python = "/editor/notebook-python/bin/python" }
    end,
    sha256 = function(bytes)
      if options.fail_at == "sha256-throw" then
        error("injected hash failure")
      end
      return vim.fn.sha256(bytes)
    end,
    fnameescape = vim.fn.fnameescape,
    get_select_and_run = function()
      return fixture.select_and_run
    end,
    running_kernels = function(local_only)
      expect(local_only == true, "save kernel lookup must remain buffer-local")
      expect(
        fixture.current_buffer == notebook_buffer,
        "save inspected kernels outside the originating notebook buffer"
      )
      return vim.deepcopy(fixture.running)
    end,
    schedule = function(callback)
      fixture.scheduled[#fixture.scheduled + 1] = callback
    end,
    select = function(items, select_options, callback)
      fixture.selection = {
        callback = callback,
        items = vim.deepcopy(items),
        options = vim.deepcopy(select_options),
      }
    end,
    set_select_and_run = function(callback)
      if options.fail_restore_once and callback == fixture.original_select_and_run then
        options.fail_restore_once = false
        error("injected picker restore failure")
      end
      fixture.select_and_run = callback
    end,
    set_jupytext_mtime = function(bufnr, mtime)
      expect(bufnr == notebook_buffer, "Jupytext mtime targeted the wrong buffer")
      expect(
        fixture.current_buffer == notebook_buffer,
        "Jupytext mtime was prepared outside the originating notebook buffer"
      )
      expect(
        vim.deep_equal(mtime, fixture.metadata[target].mtime),
        "Jupytext mtime did not match the installed notebook"
      )
      fixture.operations[#fixture.operations + 1] = "jupytext-mtime"
      fixture.jupytext_mtime = vim.deepcopy(mtime)
    end,
    start_timer = function(delay, callback)
      if options.fail_at == "picker-timer" then
        error("injected picker timer failure")
      end
      local timer = {
        active = true,
        callback = callback,
        closed = false,
        delay = delay,
      }
      function timer:stop()
        self.active = false
      end
      function timer:close()
        self.closed = true
      end
      fixture.timers[#fixture.timers + 1] = timer
      return timer
    end,
    system = function(command, system_options)
      fixture.operations[#fixture.operations + 1] = "nbformat-validate"
      eq(command, {
        "/editor/notebook-python/bin/python",
        "-c",
        "import nbformat,sys; notebook=nbformat.read(sys.argv[1],as_version=4); nbformat.validate(notebook)",
        fixture.temp,
      }, "nbformat validation command changed")
      expect(system_options.text == true, "nbformat validation must capture text diagnostics")
      if options.fail_at == "validation-spawn" then
        error("injected validation spawn failure")
      end
      return {
        wait = function(_, timeout)
          fixture.validation_timeout = timeout
          if options.fail_at == "validation-timeout" then
            error("injected validation timeout")
          end
          if options.fail_at == "nbformat-validate" then
            return {
              code = 1,
              signal = 0,
              stderr = "injected invalid notebook",
              stdout = "",
            }
          end
          return { code = 0, signal = 0, stderr = "", stdout = "" }
        end,
      }
    end,
    uv = uv,
  }

  fixture.saver = save_module._test.new(dependencies)

  fixture.original_select_and_run = function(kernels, prompt, command)
    dependencies.schedule(function()
      dependencies.select(kernels, { prompt = prompt }, function(choice)
        if choice ~= nil then
          dependencies.schedule(function()
            dependencies.nvim_cmd({
              args = { fixture.temp, choice },
              bang = true,
              cmd = "MoltenExportOutput",
            }, {})
          end)
        end
      end)
    end)
  end
  fixture.select_and_run = fixture.original_select_and_run

  function fixture:cursor_position()
    return vim.deepcopy(self.cursor)
  end

  function fixture:last_notification()
    local notification = self.notifications[#self.notifications]
    return notification and notification.message or ""
  end

  function fixture:has_notification(needle)
    for _, notification in ipairs(self.notifications) do
      if notification.message:lower():find(needle:lower(), 1, true) then
        return true
      end
    end
    return false
  end

  function fixture:open_descriptor_count()
    return vim.tbl_count(self.descriptors)
  end

  function fixture:run_scheduled()
    while #self.scheduled > 0 do
      local callback = table.remove(self.scheduled, 1)
      callback()
    end
  end

  function fixture:fire_picker_timeout()
    local timer = self.timers[#self.timers]
    expect(timer ~= nil, "Molten picker timeout was not created")
    expect(timer.delay == 300000, "Molten picker timeout bound changed")
    expect(timer.active, "Molten picker timeout was not active")
    timer.callback()
  end

  function fixture:no_temp_files()
    for path in pairs(self.files) do
      if is_temp(path) then
        return false
      end
    end
    return true
  end

  function fixture:target_bytes()
    return self.files[target]
  end

  function fixture:target_mode()
    return self.modes[target]
  end

  return fixture
end

local expected_order = {
  "buffer-write",
  "realpath",
  "snapshot-stat",
  "snapshot-read",
  "temp-exclusive-create",
  "temp-copy",
  "temp-fsync",
  "temp-close",
  "molten-export-bang",
  "nbformat-validate",
  "target-recheck-stat",
  "target-recheck-read",
  "temp-chmod",
  "temp-fsync-after-export",
  "atomic-rename",
  "parent-fsync",
  "jupytext-mtime",
  "buffer-write-force",
}

local fixture = new_fixture()
local original_cursor = fixture:cursor_position()
local callback_calls = 0
fixture.saver.export(notebook_buffer, function(ok)
  callback_calls = callback_calls + 1
  expect(ok == true, "successful transaction callback must be true")
end)
eq(
  fixture.operations,
  expected_order,
  "output transaction order changed: " .. vim.inspect(fixture.notifications)
)
expect(fixture.files[target] == exported_notebook, "exported notebook was not installed")
expect(fixture.files[link] == "symlink:" .. target, "notebook symlink was replaced")
expect(fixture.modes[target] == target_mode, "target mode was not preserved")
eq(fixture:cursor_position(), original_cursor, "output save moved the notebook cursor")
expect(fixture.molten_arguments.bang == true, "Molten export must use bang")
expect(#fixture.molten_arguments.args == 1, "Molten export received a kernel argument")
expect(
  fixture.molten_arguments.kernel == nil,
  "multiple-kernel selection must remain Molten's responsibility"
)
expect(
  fixture.initial_molten_argument:find("\\ ", 1, true)
    and fixture.initial_molten_argument:find("\\|", 1, true)
    and fixture.initial_molten_argument:find("\\%", 1, true),
  "initial Molten path did not escape spaces and Ex metacharacters"
)
expect(fixture.validation_timeout == 10000, "nbformat validation is not bounded to 10 seconds")
expect(fixture.prompt_calls == 0, "successful transaction opened Jupytext's changed-file prompt")
expect(callback_calls == 1, "successful transaction callback did not run exactly once")
expect(fixture:no_temp_files(), "successful export left a temporary file")

do
  local multiple = new_fixture({ running = { "kernel-one", "kernel-two" } })
  local calls = 0
  local result
  multiple.saver.export(multiple.buffer, function(ok)
    calls = calls + 1
    result = ok
  end)
  expect(calls == 0, "multi-kernel export continued before Molten's picker completed")
  expect(
    multiple:target_bytes() == original_notebook,
    "multi-kernel export replaced the target before selection"
  )
  expect(
    multiple.select_and_run == multiple.original_select_and_run,
    "Molten selection callback was not restored immediately"
  )

  multiple:run_scheduled()
  expect(multiple.selection ~= nil, "Molten's multi-kernel picker did not open")
  eq(multiple.selection.items, { "kernel-one", "kernel-two" }, "Molten's kernel choices changed")
  expect(
    multiple.selection.options.prompt == "Please select a kernel:",
    "Molten's kernel picker prompt changed"
  )
  expect(calls == 0, "multi-kernel export continued before the user selected a kernel")

  multiple.current_buffer = 23
  multiple.selection.callback("kernel-two")
  multiple:run_scheduled()
  expect(calls == 1 and result == true, "selected multi-kernel export did not complete once")
  expect(multiple.current_buffer == 23, "selected export did not restore the user's current buffer")
  expect(multiple:target_bytes() == exported_notebook, "selected kernel output was not saved")
  expect(multiple.selected_command.args[2] == "kernel-two", "Molten's selected kernel was not used")
  expect(#multiple.molten_arguments.args == 1, "initial Molten export received a kernel argument")
  expect(multiple:no_temp_files(), "selected multi-kernel export leaked its temporary file")
  expect(
    not multiple.timers[1].active and multiple.timers[1].closed,
    "completed Molten selection left its timeout open"
  )
end

do
  local cancelled = new_fixture({ running = { "kernel-one", "kernel-two" } })
  local calls = 0
  local result
  cancelled.saver.export(cancelled.buffer, function(ok)
    calls = calls + 1
    result = ok
  end)
  cancelled:run_scheduled()
  cancelled.selection.callback(nil)
  cancelled:run_scheduled()
  expect(calls == 1 and result == false, "cancelled Molten selection did not fail once")
  expect(cancelled:target_bytes() == original_notebook, "cancelled selection changed target")
  expect(cancelled:no_temp_files(), "cancelled selection leaked its temporary file")
  expect(cancelled:has_notification("cancelled"), "cancelled Molten selection lacks feedback")
end

do
  local abandoned = new_fixture({ running = { "kernel-one", "kernel-two" } })
  local calls = 0
  local result
  abandoned.saver.export(abandoned.buffer, function(ok)
    calls = calls + 1
    result = ok
  end)
  abandoned:run_scheduled()
  expect(abandoned.selection ~= nil, "abandoned picker did not open")
  abandoned:fire_picker_timeout()
  expect(calls == 1 and result == false, "abandoned picker did not complete exactly once")
  expect(abandoned:target_bytes() == original_notebook, "abandoned picker changed target")
  expect(abandoned:no_temp_files(), "abandoned picker leaked a temporary file")
  expect(abandoned:has_notification("within 5 minutes"), "abandoned picker timeout is unclear")
  abandoned.selection.callback("kernel-one")
  abandoned:run_scheduled()
  expect(calls == 1, "late picker callback completed the transaction twice")
  expect(abandoned:target_bytes() == original_notebook, "late picker callback changed target")
end

do
  local restore_failure = new_fixture({
    fail_restore_once = true,
    running = { "kernel-one", "kernel-two" },
  })
  local calls = 0
  restore_failure.saver.export(restore_failure.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, "picker restore failure reported success")
  end)
  expect(calls == 1, "picker restore failure callback did not run once")
  expect(restore_failure:target_bytes() == original_notebook, "restore failure changed target")
  expect(restore_failure:no_temp_files(), "picker restore failure leaked a temporary file")
  expect(
    restore_failure.select_and_run == restore_failure.original_select_and_run,
    "restore failure permanently left Molten's picker wrapped"
  )
  expect(
    restore_failure:has_notification("restore Molten's kernel picker"),
    "restore failure is unclear"
  )
end

do
  local timer_failure = new_fixture({
    fail_at = "picker-timer",
    running = { "kernel-one", "kernel-two" },
  })
  local calls = 0
  timer_failure.saver.export(timer_failure.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, "picker timer failure reported success")
  end)
  expect(calls == 1, "picker timer failure callback did not run once")
  expect(timer_failure:target_bytes() == original_notebook, "picker timer failure changed target")
  expect(timer_failure:no_temp_files(), "picker timer failure leaked a temporary file")
  expect(timer_failure:has_notification("kernel-picker timeout"), "picker timer failure is unclear")
end

do
  local mismatched = new_fixture({
    running = { "kernel-one", "kernel-two" },
    tamper_generated_command = true,
  })
  local calls = 0
  mismatched.saver.export(mismatched.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, "foreign generated command reported success")
  end)
  expect(calls == 1, "foreign generated command callback did not run once")
  expect(mismatched:target_bytes() == original_notebook, "foreign command changed target")
  expect(mismatched:no_temp_files(), "foreign command leaked a temporary file")
  expect(
    mismatched:has_notification("unexpected output-export command"),
    "foreign generated command was not rejected"
  )
  expect(
    mismatched.select_and_run == mismatched.original_select_and_run,
    "foreign generated command left Molten's picker wrapped"
  )
end

do
  local selected_failure = new_fixture({
    fail_at = "selected-export",
    running = { "kernel-one", "kernel-two" },
  })
  local calls = 0
  selected_failure.saver.export(selected_failure.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, "selected export exception reported success")
  end)
  selected_failure:run_scheduled()
  selected_failure.selection.callback("kernel-one")
  selected_failure:run_scheduled()
  expect(calls == 1, "selected export exception callback did not run once")
  expect(selected_failure:target_bytes() == original_notebook, "selected failure changed target")
  expect(selected_failure:no_temp_files(), "selected export exception leaked a temporary file")
  expect(
    selected_failure:has_notification("selected export failure"),
    "selected failure is unclear"
  )
end

local failures = {
  { at = "buffer-write", message = "source write failed" },
  { at = "buffer-write-noop", message = "left the notebook buffer modified" },
  { at = "temp-exclusive-create", message = "could not create" },
  { at = "temp-copy", message = "could not copy" },
  { at = "molten-export-bang", message = "Molten export failed" },
  { at = "nbformat-validate", message = "not valid nbformat" },
  { at = "target-recheck-stat", message = "changed during output export" },
  { at = "target-recheck-read", message = "changed during output export" },
  { at = "temp-chmod", message = "could not preserve mode" },
  { at = "atomic-rename", message = "could not replace" },
}

for _, failure in ipairs(failures) do
  local failed = new_fixture({ fail_at = failure.at })
  local calls = 0
  failed.saver.export(failed.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, failure.at .. " must report failure")
  end)
  expect(failed:target_bytes() == original_notebook, failure.at .. " changed the target")
  expect(failed:target_mode() == target_mode, failure.at .. " changed target mode")
  expect(failed:no_temp_files(), failure.at .. " leaked a temporary file")
  expect(
    failed:last_notification():lower():find(failure.message:lower(), 1, true),
    failure.at .. " diagnostic is imprecise: " .. failed:last_notification()
  )
  expect(calls == 1, failure.at .. " callback did not run exactly once")
end

do
  local clean_noop = new_fixture({
    fail_at = "buffer-write-noop",
    initially_unmodified = true,
  })
  local calls = 0
  clean_noop.saver.export(clean_noop.buffer, function(ok)
    calls = calls + 1
    expect(ok == true, "already-clean source no-op blocked output persistence")
  end)
  expect(calls == 1, "already-clean no-op callback did not run once")
  expect(clean_noop:target_bytes() == exported_notebook, "already-clean no-op lost outputs")
  expect(clean_noop.prompt_calls == 0, "already-clean no-op opened Jupytext's prompt")
end

local resync = new_fixture({ fail_at = "buffer-write-force" })
local resync_calls = 0
resync.saver.export(resync.buffer, function(ok)
  resync_calls = resync_calls + 1
  expect(ok == true, "post-rename resync failure must report saved outputs")
end)
expect(
  resync:target_bytes() == exported_notebook,
  "post-rename resync failure lost exported outputs"
)
expect(
  resync:last_notification():find("outputs were saved", 1, true),
  "post-rename warning must state durable outcome"
)
expect(
  resync:last_notification():find("timestamp sync failed", 1, true),
  "post-rename warning must explain remaining issue"
)
expect(resync_calls == 1, "post-rename resync callback did not run exactly once")

do
  local short_io = new_fixture({
    entropy_collisions = 2,
    partial_read = 7,
    partial_write = 5,
  })
  local calls = 0
  short_io.saver.export(short_io.buffer, function(ok)
    calls = calls + 1
    expect(ok == true, "short I/O transaction failed")
  end)
  expect(short_io:target_bytes() == exported_notebook, "short I/O lost exported output")
  expect(short_io.random_calls == 3, "exclusive-create collisions were not retried")
  expect(short_io:no_temp_files(), "short I/O transaction leaked its temporary file")
  expect(short_io:open_descriptor_count() == 0, "short I/O transaction leaked a descriptor")
  expect(calls == 1, "short I/O callback did not run exactly once")
end

do
  local collisions = new_fixture({ entropy_collisions = 32 })
  local calls = 0
  collisions.saver.export(collisions.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, "exhausted entropy collisions reported success")
  end)
  expect(collisions.random_calls == 32, "exclusive-create retry bound changed")
  expect(collisions:target_bytes() == original_notebook, "entropy collisions changed target")
  expect(collisions:no_temp_files(), "entropy collisions leaked a temporary file")
  expect(collisions:has_notification("could not create"), "entropy collision failure is unclear")
  expect(calls == 1, "entropy collision callback did not run exactly once")
end

for _, failure in ipairs({
  "temp-fsync",
  "temp-close",
  "target-read-close",
  "validation-spawn",
  "validation-timeout",
  "temp-fsync-after-export",
  "temp-flush-close",
  "target-stat-throw",
  "temp-chmod-throw",
  "sha256-throw",
}) do
  local hardened = new_fixture({ fail_at = failure })
  local calls = 0
  local escaped, export_error = pcall(hardened.saver.export, hardened.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, failure .. " reported success")
  end)
  expect(escaped, failure .. " escaped the transaction: " .. tostring(export_error))
  expect(hardened:target_bytes() == original_notebook, failure .. " changed target bytes")
  expect(hardened:target_mode() == target_mode, failure .. " changed target mode")
  expect(hardened:no_temp_files(), failure .. " leaked a temporary file")
  expect(hardened:open_descriptor_count() == 0, failure .. " leaked a descriptor")
  expect(calls == 1, failure .. " callback did not run exactly once")
end

for _, field in ipairs({ "dev", "ino", "mode", "size", "mtime-sec", "mtime-nsec" }) do
  local changed = new_fixture({ recheck_field = field })
  changed.saver.export(changed.buffer)
  expect(changed:target_bytes() == original_notebook, field .. " recheck changed the target")
  expect(changed:no_temp_files(), field .. " recheck leaked a temporary file")
  expect(
    changed:has_notification("changed during output export"),
    field .. " was omitted from the TOCTOU recheck"
  )
end

do
  local changed_bytes = original_notebook:gsub("source", "tamper")
  expect(#changed_bytes == #original_notebook, "hash fixture changed notebook size")
  local changed = new_fixture({ recheck_bytes = changed_bytes })
  changed.saver.export(changed.buffer)
  expect(changed:target_bytes() == original_notebook, "hash recheck changed the target")
  expect(changed:no_temp_files(), "hash recheck leaked a temporary file")
  expect(
    changed:has_notification("changed during output export"),
    "target content hash was omitted from the TOCTOU recheck"
  )
end

do
  local nonregular = new_fixture({ target_type = "directory" })
  nonregular.saver.export(nonregular.buffer)
  expect(nonregular:target_bytes() == original_notebook, "non-regular target was changed")
  expect(nonregular:has_notification("not a regular file"), "non-regular target was not rejected")
end

for _, failure in ipairs({ "parent-fsync", "directory-close" }) do
  local durability = new_fixture({ fail_at = failure })
  local calls = 0
  durability.saver.export(durability.buffer, function(ok)
    calls = calls + 1
    expect(ok == true, failure .. " discarded a successful replacement")
  end)
  expect(durability:target_bytes() == exported_notebook, failure .. " lost output")
  expect(durability:has_notification("durability sync failed"), failure .. " warning is missing")
  expect(durability:no_temp_files(), failure .. " leaked a temporary file")
  expect(durability:open_descriptor_count() == 0, failure .. " leaked a descriptor")
  expect(calls == 1, failure .. " callback did not run exactly once")
end

do
  local attacked = new_fixture({ replace_temp_after_export = true })
  local calls = 0
  attacked.saver.export(attacked.buffer, function(ok)
    calls = calls + 1
    expect(ok == false, "hostile temporary replacement reported success")
  end)
  expect(
    attacked:target_bytes() == original_notebook,
    "hostile temporary replacement changed target"
  )
  expect(
    attacked.files[attacked.temp] == "symlink:/attacker/valuable.ipynb",
    "cleanup unlinked a temporary path replaced by an attacker"
  )
  expect(attacked:has_notification("changed temporary path"), "hostile replacement is unclear")
  expect(attacked:open_descriptor_count() == 0, "hostile replacement leaked a descriptor")
  expect(calls == 1, "hostile replacement callback did not run exactly once")
end

do
  local callback_failure = new_fixture()
  local calls = 0
  local escaped, callback_error = pcall(
    callback_failure.saver.export,
    callback_failure.buffer,
    function()
      calls = calls + 1
      error("injected callback exception")
    end
  )
  expect(escaped, "callback exception escaped export: " .. tostring(callback_error))
  expect(callback_failure:target_bytes() == exported_notebook, "callback exception lost outputs")
  expect(calls == 1, "throwing callback ran more than once")
  expect(callback_failure:has_notification("callback failed"), "callback exception was hidden")
end

print("notebook save assertions: ok")
