local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

package.loaded["notebook.workflow"] = nil
local workflow_module = require("notebook.workflow")

local markdown_buffer = 1
local python_buffer = 2
local notebook_buffer = 3
local buffers = {
  [markdown_buffer] = {
    filetype = "markdown",
    maps = {},
    name = "/work/notes.md",
    vars = {},
  },
  [python_buffer] = {
    filetype = "python",
    maps = {},
    name = "/work/script.py",
    vars = {},
  },
  [notebook_buffer] = {
    filetype = "markdown",
    maps = {},
    name = "/work/analysis.ipynb",
    vars = {},
  },
}

local quarto_activations = 0
local molten_init_calls = 0
local active_buffer

local workflow = workflow_module._test.new({
  buf_call = function(bufnr, callback)
    local previous = active_buffer
    active_buffer = bufnr
    callback()
    active_buffer = previous
  end,
  buf_name = function(bufnr)
    return buffers[bufnr].name
  end,
  get_buf_var = function(bufnr, name)
    return buffers[bufnr].vars[name]
  end,
  quarto_activate = function()
    expect(active_buffer == notebook_buffer, "Quarto activated outside the notebook buffer")
    quarto_activations = quarto_activations + 1
  end,
  realpath = function(path)
    return path
  end,
  set_buf_var = function(bufnr, name, value)
    buffers[bufnr].vars[name] = value
  end,
  set_keymap = function(mode, lhs, callback, options)
    expect(type(callback) == "function", "notebook mapping has no callback")
    expect(options.buffer == notebook_buffer, "notebook mapping is not buffer-local")
    buffers[options.buffer].maps[mode .. ":" .. lhs] = options.desc
  end,
})

local function map_descriptions(bufnr)
  return buffers[bufnr].maps
end

expect(workflow.attach(markdown_buffer) == false, "ordinary Markdown must not attach")
expect(
  not buffers[markdown_buffer].vars.dotfiles_notebook,
  "ordinary Markdown was marked as a notebook"
)
expect(next(buffers[markdown_buffer].maps) == nil, "ordinary Markdown received notebook mappings")
expect(workflow.attach(python_buffer) == false, "ordinary Python must not attach")
expect(
  not buffers[python_buffer].vars.dotfiles_notebook,
  "ordinary Python was marked as a notebook"
)
expect(next(buffers[python_buffer].maps) == nil, "ordinary Python received notebook mappings")

expect(workflow.attach(notebook_buffer) == true, "ipynb buffer did not attach")
expect(buffers[notebook_buffer].vars.dotfiles_notebook == true, "ipynb flag is missing")
expect(quarto_activations == 1, "Quarto must activate once")
expect(molten_init_calls == 0, "attachment must not initialize Molten")
expect(workflow.attach(notebook_buffer) == true, "repeat attachment must remain successful")
expect(quarto_activations == 1, "repeat attachment must be idempotent")

local expected_maps = {
  ["n:<leader>jc"] = "Notebook: run cell",
  ["x:<leader>jv"] = "Notebook: run selection",
  ["n:<leader>ja"] = "Notebook: run all cells",
  ["n:<leader>jn"] = "Notebook: next cell",
  ["n:<leader>jp"] = "Notebook: previous cell",
  ["n:<leader>jo"] = "Notebook: enter output",
  ["n:<leader>jx"] = "Notebook: interrupt kernel",
  ["n:<leader>jR"] = "Notebook: restart kernel",
  ["n:<leader>js"] = "Notebook: save outputs",
}
expect(
  vim.deep_equal(map_descriptions(notebook_buffer), expected_maps),
  "notebook mapping contract changed"
)

local function new_fixture()
  local fixture = {
    autocmds = {},
    buffers = {
      [markdown_buffer] = {
        filetype = "markdown",
        maps = {},
        name = "/work/notes.md",
        valid = true,
        vars = {},
      },
      [python_buffer] = {
        filetype = "python",
        maps = {},
        name = "/work/script.py",
        valid = true,
        vars = {},
      },
      [notebook_buffer] = {
        filetype = "markdown",
        maps = {},
        modified = true,
        name = "/work/analysis.ipynb",
        valid = true,
        vars = {
          dotfiles_notebook_metadata = { kernelspec = { name = "recorded" } },
        },
      },
    },
    calls = {
      ensure = {},
      fallback = 0,
      groups = 0,
      imports = {},
      init = 0,
      maps = 0,
      quarto = 0,
      resolve = {},
      run_all = 0,
      run_cell = 0,
      run_range = 0,
      save_export = 0,
      save_buffers = {},
      select = 0,
      writes = 0,
    },
    command_errors = {},
    commands = {},
    current_win = 101,
    ensure_name = "dotfiles-project-kernel",
    notifications = {},
    raw_ranges = { { 2, 5 }, { 9, 12 }, { 20, 24 } },
    realpaths = {
      ["/work/notes.md"] = "/work/notes.md",
      ["/work/script.py"] = "/work/script.py",
      ["/work/analysis.ipynb"] = "/work/analysis.ipynb",
    },
    resolve_result = {
      kind = "interpreter",
      interpreter = "/work/.venv/bin/python",
      label = "uv: work",
      root = "/work",
      source = "uv",
    },
    running = {},
    select_choice = 1,
    timers = {},
    windows = {
      [101] = {
        buffer = notebook_buffer,
        cursor = { 1, 0 },
        valid = true,
      },
    },
  }

  local call_buffer

  local function record_run(name)
    if fixture.runner_error == name then
      error(name .. " runner failed")
    end
    fixture.calls[name] = fixture.calls[name] + 1
    local window = fixture.windows[fixture.current_win]
    fixture.last_run = {
      buffer = window and window.buffer,
      cursor = window and vim.deepcopy(window.cursor),
      marks = vim.deepcopy(fixture.buffers[notebook_buffer].marks or {}),
      window = fixture.current_win,
    }
  end

  local dependencies = {
    buf_call = function(bufnr, callback)
      if not fixture.buffers[bufnr] or not fixture.buffers[bufnr].valid then
        error("invalid buffer")
      end
      local previous = call_buffer
      call_buffer = bufnr
      local ok, result = pcall(callback)
      call_buffer = previous
      if not ok then
        error(result)
      end
      return result
    end,
    buf_is_valid = function(bufnr)
      return fixture.buffers[bufnr] ~= nil and fixture.buffers[bufnr].valid
    end,
    buf_name = function(bufnr)
      return fixture.buffers[bufnr] and fixture.buffers[bufnr].name or ""
    end,
    buf_modified = function(bufnr)
      return fixture.buffers[bufnr].modified
    end,
    cell_ranges = function()
      if fixture.cell_error then
        error(fixture.cell_error)
      end
      local ranges = {}
      for _, range in ipairs(fixture.raw_ranges) do
        ranges[#ranges + 1] = { range[1] + 1, range[2] + 1 }
      end
      return ranges
    end,
    command = function(name, arguments, modifiers)
      fixture.commands[#fixture.commands + 1] = {
        arguments = vim.deepcopy(arguments or {}),
        buffer = call_buffer,
        modifiers = vim.deepcopy(modifiers or {}),
        name = name,
      }
      if name == "MoltenInit" then
        fixture.calls.init = fixture.calls.init + 1
      elseif name == "MoltenImportOutput" then
        fixture.calls.imports[#fixture.calls.imports + 1] = arguments[1]
      end
      if fixture.command_errors[name] then
        error(fixture.command_errors[name])
      end
    end,
    create_augroup = function(name, options)
      fixture.calls.groups = fixture.calls.groups + 1
      expect(name == "dotfiles-notebook", "workflow augroup name changed")
      expect(options.clear == true, "workflow augroup must clear stale autocmds")
      return 41
    end,
    create_autocmd = function(events, options)
      if type(events) == "string" then
        events = { events }
      end
      for _, event in ipairs(events) do
        fixture.autocmds[event] = fixture.autocmds[event] or {}
        fixture.autocmds[event][#fixture.autocmds[event] + 1] = options
      end
    end,
    environment_ensure_kernel = function(candidate)
      fixture.calls.ensure[#fixture.calls.ensure + 1] = candidate
      if fixture.ensure_error then
        if fixture.ensure_throws then
          error(fixture.ensure_error)
        end
        return nil, fixture.ensure_error
      end
      return candidate.kind == "registered" and candidate.kernel or fixture.ensure_name
    end,
    environment_fallback = function()
      fixture.calls.fallback = fixture.calls.fallback + 1
      if fixture.fallback_error then
        return nil, fixture.fallback_error
      end
      return fixture.fallback_result
        or {
          kind = "interpreter",
          interpreter = "/editor/bin/python",
          label = "editor fallback",
          root = "/editor",
          source = "editor",
        }
    end,
    environment_resolve = function(path, metadata)
      fixture.calls.resolve[#fixture.calls.resolve + 1] = {
        metadata = metadata,
        path = path,
      }
      if fixture.resolve_error then
        error(fixture.resolve_error)
      end
      return fixture.resolve_result, fixture.resolve_warnings or {}
    end,
    get_buf_mark = function(bufnr, name)
      local marks = fixture.buffers[bufnr].marks or {}
      return vim.deepcopy(marks[name] or { 0, 0 })
    end,
    get_buf_var = function(bufnr, name)
      return fixture.buffers[bufnr].vars[name]
    end,
    get_current_buf = function()
      return fixture.windows[fixture.current_win].buffer
    end,
    get_current_win = function()
      return fixture.current_win
    end,
    get_cursor = function(winid)
      return vim.deepcopy(fixture.windows[winid].cursor)
    end,
    notify = function(message, level)
      fixture.notifications[#fixture.notifications + 1] = {
        level = level,
        message = tostring(message),
      }
    end,
    nvim_cmd = function(command)
      expect(command.cmd == "write", "unexpected raw notebook command")
      expect(not command.bang, "source-only save unexpectedly forced the write")
      expect(call_buffer == notebook_buffer, "source write ran outside the notebook buffer")
      fixture.calls.writes = fixture.calls.writes + 1
      if fixture.write_error then
        error(fixture.write_error)
      end
      if not fixture.write_noop then
        fixture.buffers[notebook_buffer].modified = false
      end
    end,
    quarto_activate = function()
      expect(fixture.buffers[call_buffer] ~= nil, "Quarto activated outside a known buffer")
      fixture.calls.quarto = fixture.calls.quarto + 1
    end,
    quarto_run_all = function()
      record_run("run_all")
    end,
    quarto_run_cell = function()
      record_run("run_cell")
    end,
    quarto_run_range = function()
      record_run("run_range")
    end,
    realpath = function(path)
      return fixture.realpaths[path]
    end,
    running_kernels = function(local_only)
      expect(local_only == true, "kernel lookup must stay buffer-local")
      if fixture.running_error then
        error(fixture.running_error)
      end
      if fixture.clear_realpath_on_kernel_check then
        fixture.realpaths[fixture.buffers[notebook_buffer].name] = nil
      end
      return vim.deepcopy(fixture.running)
    end,
    save = {
      export = function(bufnr)
        fixture.calls.save_export = fixture.calls.save_export + 1
        fixture.calls.save_buffers[#fixture.calls.save_buffers + 1] = bufnr
        expect(bufnr == notebook_buffer, "export targeted the wrong buffer")
        if fixture.save_error then
          error(fixture.save_error)
        end
      end,
    },
    select = function(choices, options, callback)
      fixture.calls.select = fixture.calls.select + 1
      fixture.last_select = { choices = choices, options = options }
      if fixture.defer_select then
        fixture.select_callback = callback
        return
      end
      if fixture.select_choice == false then
        callback(nil)
      else
        callback(choices[fixture.select_choice])
      end
    end,
    set_buf_mark = function(bufnr, name, mark)
      fixture.buffers[bufnr].marks = fixture.buffers[bufnr].marks or {}
      fixture.buffers[bufnr].marks[name] = vim.deepcopy(mark)
    end,
    set_buf_var = function(bufnr, name, value)
      fixture.buffers[bufnr].vars[name] = value
    end,
    set_current_win = function(winid)
      fixture.current_win = winid
    end,
    set_cursor = function(winid, cursor)
      fixture.windows[winid].cursor = vim.deepcopy(cursor)
    end,
    set_keymap = function(mode, lhs, callback, options)
      fixture.calls.maps = fixture.calls.maps + 1
      fixture.buffers[options.buffer].maps[mode .. ":" .. lhs] = {
        callback = callback,
        desc = options.desc,
      }
    end,
    start_timer = function(delay, callback)
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
    win_get_buf = function(winid)
      return fixture.windows[winid] and fixture.windows[winid].buffer
    end,
    win_is_valid = function(winid)
      return fixture.windows[winid] ~= nil and fixture.windows[winid].valid
    end,
  }

  fixture.workflow = workflow_module._test.new(dependencies)

  function fixture:attach()
    expect(self.workflow.attach(notebook_buffer), "fixture notebook did not attach")
  end

  function fixture:emit_ready(kernel_id, generation)
    local registrations = self.autocmds.User or {}
    expect(#registrations == 1, "MoltenKernelReady autocmd is missing or duplicated")
    registrations[1].callback({
      buf = notebook_buffer,
      data = { generation = generation, kernel_id = kernel_id },
      match = "MoltenKernelReady",
    })
  end

  function fixture:last_notification()
    local notification = self.notifications[#self.notifications]
    return notification and notification.message or ""
  end

  function fixture:set_cursor(row, column)
    self.windows[self.current_win].cursor = { row, column or 0 }
  end

  return fixture
end

do
  local fixture = new_fixture()
  fixture.workflow.setup()
  fixture.workflow.setup()
  expect(fixture.calls.groups == 1, "workflow setup must be idempotent")
  expect(#fixture.autocmds.BufReadPost == 1, "BufReadPost attachment autocmd changed")
  expect(#fixture.autocmds.BufEnter == 1, "BufEnter attachment autocmd changed")
  expect(#fixture.autocmds.User == 1, "kernel-ready autocmd changed")
  expect(
    fixture.autocmds.BufReadPost[1].pattern == "*.ipynb",
    "notebook attachment autocmd is too broad"
  )
  fixture.autocmds.BufReadPost[1].callback({ buf = notebook_buffer })
  expect(fixture.calls.quarto == 1, "attachment autocmd did not activate Quarto")
  expect(fixture.calls.init == 0, "setup or attachment initialized Molten eagerly")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.write_noop = true
  expect(
    fixture.workflow.save_outputs(notebook_buffer) == false,
    "silent Jupytext source-write abort reported success"
  )
  expect(fixture.calls.writes == 1, "silent source-write abort skipped the write attempt")
  expect(fixture.calls.save_export == 0, "silent source-write abort attempted output export")
  expect(
    fixture:last_notification():find("left the notebook buffer modified", 1, true),
    "silent source-write abort diagnostic is unclear"
  )

  fixture.buffers[notebook_buffer].modified = false
  expect(
    fixture.workflow.save_outputs(notebook_buffer) == true,
    "already-clean source-write no-op reported failure"
  )
  expect(
    fixture:last_notification():find("Notebook source saved", 1, true),
    "already-clean source-write no-op lost safe feedback"
  )
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.running_error = "remote provider unavailable"
  expect(
    pcall(fixture.workflow.run_cell, notebook_buffer),
    "kernel-provider exception escaped execution mapping"
  )
  expect(fixture.calls.init == 0, "execution continued after kernel-provider failure")
  expect(
    fixture:last_notification():find("remote provider unavailable", 1, true),
    "kernel-provider failure was not reported"
  )
  expect(
    pcall(fixture.workflow.interrupt, notebook_buffer),
    "kernel-provider exception escaped control mapping"
  )
  expect(
    pcall(fixture.workflow.save_outputs, notebook_buffer),
    "kernel-provider exception escaped save mapping"
  )
  expect(
    #fixture.commands == 0 and fixture.calls.writes == 0 and fixture.calls.save_export == 0,
    "kernel-provider failure allowed a guarded action"
  )
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.clear_realpath_on_kernel_check = true
  fixture.workflow.run_cell(notebook_buffer)
  expect(#fixture.calls.resolve == 0, "missing canonical path reached environment resolution")
  expect(
    fixture:last_notification():find("path is no longer available", 1, true),
    "disappearing notebook path was not reported"
  )
end

do
  local fixture = new_fixture()
  expect(fixture.workflow.attach(0), "current-buffer attachment failed")
  expect(
    fixture.buffers[notebook_buffer].vars.dotfiles_notebook == true,
    "current-buffer attachment marked literal buffer zero"
  )
  expect(fixture.calls.maps == 9, "current-buffer attachment did not install notebook mappings")
  fixture.workflow.setup()
  fixture.workflow.run_cell(0)
  expect(fixture.calls.init == 1, "current-buffer execution did not start a kernel")
  fixture:emit_ready("kernel-id", 1)
  expect(
    fixture.calls.run_cell == 1,
    "real-buffer ready event did not replay current-buffer execution"
  )
  fixture.workflow.attach(notebook_buffer)
  expect(fixture.calls.quarto == 1, "real buffer reattached after current-buffer attachment")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture:set_cursor(8, 4)

  fixture.workflow.run_cell(notebook_buffer)
  expect(#fixture.calls.resolve == 1, "first execution must resolve one environment")
  expect(fixture.calls.init == 1, "first execution must initialize one kernel")
  expect(fixture.calls.run_cell == 0, "cell must wait for MoltenKernelReady")
  expect(
    fixture.calls.resolve[1].path == "/work/analysis.ipynb",
    "environment resolution did not use the canonical notebook path"
  )
  expect(
    fixture.calls.resolve[1].metadata
      == fixture.buffers[notebook_buffer].vars.dotfiles_notebook_metadata,
    "environment resolution did not receive notebook metadata"
  )

  fixture:set_cursor(30, 0)
  fixture.workflow.run_cell(notebook_buffer)
  expect(
    #fixture.calls.resolve == 1 and fixture.calls.init == 1,
    "duplicate startup must be single-flight"
  )
  expect(
    fixture:last_notification():find("already starting", 1, true),
    "duplicate startup needs feedback"
  )

  fixture.workflow.setup()
  fixture:emit_ready("kernel-id")
  fixture.running = { "kernel-id" }
  expect(#fixture.calls.imports == 1, "stored output must import after the kernel is ready")
  expect(
    fixture.calls.imports[1] == "/work/analysis.ipynb",
    "output import must use the original notebook"
  )
  expect(fixture.calls.run_cell == 1, "captured action must replay once")
  expect(
    vim.deep_equal(fixture.last_run.cursor, { 8, 4 }),
    "captured cursor was not restored before replay"
  )

  fixture:emit_ready("duplicate-kernel-id", 1)
  expect(#fixture.calls.imports == 1, "duplicate ready event imported output twice")
  expect(fixture.calls.run_cell == 1, "duplicate ready event replayed the action twice")

  fixture.workflow.run_all(notebook_buffer)
  expect(fixture.calls.run_all == 1, "running kernel must execute immediately")
  expect(
    #fixture.calls.resolve == 1 and fixture.calls.init == 1,
    "running kernel must not re-resolve"
  )
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.workflow.setup()
  fixture.command_errors.MoltenInit = "kernel failed"
  fixture.workflow.run_cell(notebook_buffer)
  expect(
    fixture:last_notification():find("kernel failed", 1, true),
    "init failure must be reported"
  )

  fixture.command_errors.MoltenInit = nil
  fixture.workflow.run_cell(notebook_buffer)
  expect(fixture.calls.init == 2, "a later execution must retry after init failure")
  local timed_out = fixture.timers[#fixture.timers]
  expect(timed_out.delay == 30000, "kernel startup timeout changed")
  timed_out.callback()
  expect(
    fixture:last_notification():find("30 seconds", 1, true),
    "startup timeout must be actionable"
  )

  fixture.workflow.run_cell(notebook_buffer)
  expect(fixture.calls.init == 3, "a later execution must retry after timeout")
  local current_timer = fixture.timers[#fixture.timers]
  timed_out.callback()
  expect(current_timer.active, "a stale timeout cancelled the current startup")
  fixture:emit_ready("stale-kernel", 2)
  expect(fixture.calls.run_cell == 0, "a stale ready event replayed the current action")
  fixture:emit_ready("current-kernel", 3)
  expect(fixture.calls.run_cell == 1, "current generation did not replay after a retry")
end

do
  local fixture = new_fixture()
  local uv_choice = {
    kind = "interpreter",
    interpreter = "/work/.venv/bin/python",
    label = "uv: work",
    root = "/work",
  }
  local poetry_choice = {
    kind = "interpreter",
    interpreter = "/poetry/bin/python",
    label = "Poetry: work",
    root = "/work",
  }
  fixture.resolve_result = {
    choices = { uv_choice, poetry_choice },
    kind = "ambiguous",
    root = "/work",
  }
  fixture.select_choice = 2
  fixture.ensure_name = "poetry-kernel"
  fixture:attach()
  fixture.workflow.run_cell(notebook_buffer)
  expect(fixture.calls.select == 1, "ambiguous environment did not open a picker")
  expect(
    fixture.last_select.options.prompt == "Select notebook environment",
    "environment picker prompt changed"
  )
  expect(
    fixture.last_select.options.format_item(poetry_choice) == "Poetry: work",
    "environment picker label changed"
  )
  expect(fixture.calls.ensure[1] == poetry_choice, "selected environment was not registered")
  expect(
    vim.deep_equal(fixture.commands[#fixture.commands].arguments, { "poetry-kernel" }),
    "selected environment did not initialize its registered kernel"
  )
end

do
  local fixture = new_fixture()
  local choice = {
    kind = "interpreter",
    interpreter = "/work/.venv/bin/python",
    label = "uv: work",
    root = "/work",
  }
  fixture.resolve_result = { choices = { choice }, kind = "ambiguous", root = "/work" }
  fixture.defer_select = true
  fixture:attach()
  fixture.workflow.run_cell(notebook_buffer)
  local stale_selection = fixture.select_callback
  fixture.workflow.run_cell(notebook_buffer)
  expect(#fixture.calls.resolve == 1, "pending selection was not single-flight")
  stale_selection(nil)
  expect(
    fixture:last_notification():find("cancelled", 1, true),
    "environment selection cancellation needs feedback"
  )

  fixture.defer_select = false
  fixture.resolve_result = choice
  fixture.workflow.run_cell(notebook_buffer)
  expect(#fixture.calls.resolve == 2, "selection cancellation did not permit a retry")
  local init_calls = fixture.calls.init
  stale_selection(choice)
  expect(fixture.calls.init == init_calls, "a stale environment selection started another kernel")
end

do
  local fixture = new_fixture()
  fixture.resolve_result = { kind = "picker" }
  fixture:attach()
  fixture.workflow.run_cell(notebook_buffer)
  expect(fixture.calls.fallback == 1, "picker fallback did not resolve editor Python")
  expect(#fixture.calls.ensure == 1, "picker fallback was not registered privately")
  local init = fixture.commands[#fixture.commands]
  expect(init.name == "MoltenInit", "picker fallback did not initialize Molten")
  expect(#init.arguments == 0, "picker fallback must leave kernel selection to Molten")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.workflow.setup()
  fixture.buffers[notebook_buffer].marks = {
    ["<"] = { 4, 2 },
    [">"] = { 7, 8 },
  }
  fixture.workflow.run_selection(notebook_buffer)
  fixture.buffers[notebook_buffer].marks = {
    ["<"] = { 20, 0 },
    [">"] = { 21, 0 },
  }
  fixture.command_errors.MoltenImportOutput = "bad output archive"
  fixture:emit_ready("kernel-id", 1)
  expect(
    fixture:last_notification():find("bad output archive", 1, true),
    "output import failure was not reported"
  )
  expect(fixture.calls.run_range == 1, "import failure cancelled the captured selection")
  expect(
    vim.deep_equal(fixture.last_run.marks["<"], { 4, 2 })
      and vim.deep_equal(fixture.last_run.marks[">"], { 7, 8 }),
    "visual marks were not restored before replay"
  )
  fixture:emit_ready("duplicate", 1)
  expect(fixture.calls.run_range == 1, "visual selection replayed more than once")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.workflow.setup()
  fixture.workflow.run_cell(notebook_buffer)
  fixture.windows[101].valid = false
  fixture:emit_ready("kernel-id", 1)
  expect(fixture.calls.run_cell == 0, "replay used an invalid originating window")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.workflow.setup()
  fixture.workflow.run_cell(notebook_buffer)
  fixture.windows[101].buffer = markdown_buffer
  fixture:emit_ready("kernel-id", 1)
  expect(fixture.calls.run_cell == 0, "replay used a window displaying another buffer")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.workflow.setup()
  fixture.workflow.run_cell(notebook_buffer)
  fixture.buffers[notebook_buffer].valid = false
  fixture:emit_ready("kernel-id", 1)
  expect(#fixture.calls.imports == 0, "ready event imported into an invalid buffer")
  expect(fixture.calls.run_cell == 0, "ready event replayed into an invalid buffer")
  expect(not fixture.timers[#fixture.timers].active, "invalid-buffer event left its timer active")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.resolve_error = "resolver exploded"
  local ok = pcall(fixture.workflow.run_cell, notebook_buffer)
  expect(ok, "environment resolver exception escaped the workflow")
  expect(
    fixture:last_notification():find("resolver exploded", 1, true),
    "environment resolver failure was not reported"
  )
  fixture.resolve_error = nil
  fixture.ensure_error = "registration failed"
  fixture.ensure_throws = true
  fixture.workflow.run_cell(notebook_buffer)
  expect(
    fixture:last_notification():find("registration failed", 1, true),
    "kernel registration exception was not reported"
  )
  fixture.ensure_error = nil
  fixture.ensure_throws = false
  fixture.workflow.run_cell(notebook_buffer)
  expect(fixture.calls.init == 1, "environment failure did not permit a later retry")
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture:set_cursor(10, 0)
  fixture.workflow.next_cell(notebook_buffer)
  expect(fixture.windows[101].cursor[1] == 21, "next cell must jump to the next fence start")
  fixture.workflow.previous_cell(notebook_buffer)
  expect(
    fixture.windows[101].cursor[1] == 10,
    "previous cell must jump to the previous fence start"
  )
  fixture:set_cursor(2, 0)
  fixture.workflow.previous_cell(notebook_buffer)
  expect(fixture.windows[101].cursor[1] == 2, "previous cell must not wrap")
  expect(
    fixture:last_notification():find("first cell", 1, true),
    "first-cell boundary needs feedback"
  )
  fixture:set_cursor(21, 0)
  fixture.workflow.next_cell(notebook_buffer)
  expect(
    fixture:last_notification():find("last cell", 1, true),
    "last-cell boundary needs feedback"
  )
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.workflow.enter_output(notebook_buffer)
  fixture.workflow.interrupt(notebook_buffer)
  fixture.workflow.restart(notebook_buffer)
  expect(#fixture.commands == 0, "kernel controls ran without an active kernel")
  expect(
    fixture:last_notification():find("no active kernel", 1, true),
    "missing-kernel controls need feedback"
  )

  fixture.workflow.save_outputs(notebook_buffer)
  expect(fixture.calls.writes == 1, "source-only save did not write the notebook buffer")
  expect(fixture.calls.save_export == 0, "source-only save attempted an output export")
  expect(
    fixture
      :last_notification()
      :find("Notebook source saved; no active kernel outputs to export", 1, true),
    "source-only save feedback changed"
  )

  fixture.running = { "kernel-id" }
  fixture.workflow.enter_output(notebook_buffer)
  fixture.workflow.interrupt(notebook_buffer)
  fixture.workflow.restart(notebook_buffer)
  fixture.workflow.save_outputs(notebook_buffer)
  local first_control = fixture.commands[1]
  expect(first_control.name == "MoltenEnterOutput", "enter-output command changed")
  expect(first_control.modifiers.noautocmd == true, "enter-output must suppress autocmds")
  expect(fixture.commands[2].name == "MoltenInterrupt", "interrupt command changed")
  expect(fixture.commands[3].name == "MoltenRestart", "restart command changed")
  expect(fixture.calls.save_export == 1, "active-kernel save did not delegate to exporter")
  expect(
    fixture.calls.save_buffers[1] == notebook_buffer,
    "active-kernel save delegated the wrong buffer"
  )

  fixture.command_errors.MoltenInterrupt = "interrupt exploded"
  local ok = pcall(fixture.workflow.interrupt, notebook_buffer)
  expect(ok, "kernel control command exception escaped the workflow")
  expect(
    fixture:last_notification():find("interrupt exploded", 1, true),
    "kernel control command failure was not reported"
  )
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.running = { "kernel-id" }
  fixture.workflow.save_outputs(0)
  expect(fixture.calls.save_export == 1, "buffer-zero save did not reach the exporter")
  expect(
    fixture.calls.save_buffers[1] == notebook_buffer,
    "buffer-zero save was not normalized before export"
  )
end

do
  local fixture = new_fixture()
  fixture:attach()
  fixture.write_error = "disk full"
  local ok = pcall(fixture.workflow.save_outputs, notebook_buffer)
  expect(ok, "source write exception escaped the workflow")
  expect(
    fixture:last_notification():find("disk full", 1, true),
    "source write failure was not reported"
  )
end

do
  local fixture = new_fixture()
  fixture.realpaths["/work/analysis.ipynb"] = "/work/canonical.md"
  expect(
    fixture.workflow.attach(notebook_buffer) == false,
    "non-ipynb canonical target entered notebook scope"
  )
  fixture.realpaths["/work/notes.md"] = "/work/canonical.ipynb"
  expect(
    fixture.workflow.attach(markdown_buffer) == true,
    "ipynb canonical target did not enter notebook scope"
  )
end

print("notebook workflow assertions: ok")
