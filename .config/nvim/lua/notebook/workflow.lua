local M = {}

local mappings = {
  { "n", "<leader>jc", "run_cell", "Notebook: run cell" },
  { "x", "<leader>jv", "run_selection", "Notebook: run selection" },
  { "n", "<leader>ja", "run_all", "Notebook: run all cells" },
  { "n", "<leader>jn", "next_cell", "Notebook: next cell" },
  { "n", "<leader>jp", "previous_cell", "Notebook: previous cell" },
  { "n", "<leader>jo", "enter_output", "Notebook: enter output" },
  { "n", "<leader>jx", "interrupt", "Notebook: interrupt kernel" },
  { "n", "<leader>jR", "restart", "Notebook: restart kernel" },
  { "n", "<leader>js", "save_outputs", "Notebook: save outputs" },
}

local function new(deps)
  local Workflow = {}
  local attached = {}
  local setup_done = false
  local states = {}

  local function normalize_bufnr(bufnr)
    if bufnr == nil or bufnr == 0 then
      return deps.get_current_buf()
    end
    return bufnr
  end

  local function notify(message, level)
    deps.notify(message, level or vim.log.levels.ERROR)
  end

  local function notebook_path(bufnr)
    local name = deps.buf_name(bufnr)
    if name == "" then
      return nil
    end
    local canonical = deps.realpath(name)
    if not canonical or canonical:lower():sub(-6) ~= ".ipynb" then
      return nil
    end
    return canonical
  end

  local function state_for(bufnr)
    if not states[bufnr] then
      states[bufnr] = {
        generation = 0,
        kernel_id = nil,
        path = nil,
        pending = nil,
        phase = "idle",
        timeout = nil,
      }
    end
    return states[bufnr]
  end

  local function close_timeout(state)
    local timeout = state.timeout
    state.timeout = nil
    if not timeout then
      return
    end
    pcall(timeout.stop, timeout)
    pcall(timeout.close, timeout)
  end

  local function reset_start(state, generation)
    if generation and state.generation ~= generation then
      return false
    end
    close_timeout(state)
    state.phase = "idle"
    state.kernel_id = nil
    state.pending = nil
    state.path = nil
    return true
  end

  local function fail_start(state, generation, message)
    if reset_start(state, generation) then
      notify(message, vim.log.levels.ERROR)
    end
  end

  local function valid_origin(bufnr, winid)
    return deps.buf_is_valid(bufnr)
      and deps.win_is_valid(winid)
      and deps.win_get_buf(winid) == bufnr
  end

  local function capture_action(bufnr, callback, visual)
    local winid = deps.get_current_win()
    if not valid_origin(bufnr, winid) then
      notify("Notebook action no longer has a valid originating window", vim.log.levels.WARN)
      return nil
    end

    local cursor = deps.get_cursor(winid)
    local marks
    if visual then
      marks = {
        ["<"] = deps.get_buf_mark(bufnr, "<"),
        [">"] = deps.get_buf_mark(bufnr, ">"),
      }
    end

    local replayed = false
    return function()
      if replayed then
        return
      end
      replayed = true

      if not valid_origin(bufnr, winid) then
        notify(
          "Notebook action was cancelled because its window is no longer valid",
          vim.log.levels.WARN
        )
        return
      end

      local ok, replay_error = pcall(function()
        deps.set_current_win(winid)
        deps.set_cursor(winid, cursor)
        if marks then
          deps.set_buf_mark(bufnr, "<", marks["<"])
          deps.set_buf_mark(bufnr, ">", marks[">"])
        end
        deps.buf_call(bufnr, callback)
      end)
      if not ok then
        notify("Notebook action failed: " .. tostring(replay_error), vim.log.levels.ERROR)
      end
    end
  end

  local function running_kernels()
    local ok, kernels = pcall(deps.running_kernels, true)
    if not ok then
      notify("Could not inspect notebook kernels: " .. tostring(kernels), vim.log.levels.ERROR)
      return nil
    end
    if type(kernels) ~= "table" then
      notify("Could not inspect notebook kernels: provider returned no list", vim.log.levels.ERROR)
      return nil
    end
    return kernels
  end

  local function start_timeout(state, generation)
    local ok, timeout = pcall(deps.start_timer, 30000, function()
      if state.phase ~= "starting" or state.generation ~= generation then
        return
      end
      fail_start(state, generation, "Notebook kernel did not become ready within 30 seconds")
    end)
    if not ok or not timeout then
      fail_start(
        state,
        generation,
        "Could not start notebook kernel timeout: " .. tostring(timeout)
      )
      return false
    end
    state.timeout = timeout
    return true
  end

  local function initialize(bufnr, state, generation, candidate, use_picker)
    if state.phase ~= "starting" or state.generation ~= generation then
      return
    end

    local ensure_ok, kernel, ensure_error = pcall(deps.environment_ensure_kernel, candidate)
    if not ensure_ok then
      fail_start(state, generation, "Could not register notebook kernel: " .. tostring(kernel))
      return
    end
    if not kernel then
      fail_start(
        state,
        generation,
        "Could not register notebook kernel: " .. tostring(ensure_error or "unknown error")
      )
      return
    end

    if not start_timeout(state, generation) then
      return
    end

    local arguments = use_picker and {} or { kernel }
    local command_ok, command_error = pcall(deps.buf_call, bufnr, function()
      deps.command("MoltenInit", arguments)
    end)
    if not command_ok then
      fail_start(state, generation, tostring(command_error))
    end
  end

  local function choose_candidate(bufnr, state, generation, candidate)
    if candidate.kind == "ambiguous" then
      local choices = type(candidate.choices) == "table" and candidate.choices or {}
      if #choices == 0 then
        fail_start(state, generation, "No usable notebook environments were found")
        return
      end
      local select_ok, select_error = pcall(deps.select, choices, {
        format_item = function(choice)
          return choice.label
        end,
        prompt = "Select notebook environment",
      }, function(choice)
        if state.phase ~= "starting" or state.generation ~= generation then
          return
        end
        if not choice then
          reset_start(state, generation)
          notify("Notebook environment selection cancelled", vim.log.levels.INFO)
          return
        end
        initialize(bufnr, state, generation, choice, false)
      end)
      if not select_ok then
        fail_start(
          state,
          generation,
          "Could not select a notebook environment: " .. tostring(select_error)
        )
      end
      return
    end

    if candidate.kind == "picker" then
      local fallback_ok, fallback, fallback_error = pcall(deps.environment_fallback)
      if not fallback_ok then
        fail_start(
          state,
          generation,
          "Could not prepare the editor notebook environment: " .. tostring(fallback)
        )
        return
      end
      if not fallback then
        fail_start(
          state,
          generation,
          "Could not prepare the editor notebook environment: "
            .. tostring(fallback_error or "unknown error")
        )
        return
      end
      initialize(bufnr, state, generation, fallback, true)
      return
    end

    if candidate.kind ~= "registered" and candidate.kind ~= "interpreter" then
      fail_start(state, generation, "Notebook environment resolution returned an invalid candidate")
      return
    end
    initialize(bufnr, state, generation, candidate, false)
  end

  local function with_kernel(bufnr, action)
    local kernels = running_kernels()
    if not kernels then
      return false
    end
    if #kernels > 0 then
      action()
      return true
    end

    local state = state_for(bufnr)
    if state.phase == "starting" then
      notify("Notebook kernel is already starting", vim.log.levels.INFO)
      return false
    end

    state.phase = "starting"
    state.generation = state.generation + 1
    local generation = state.generation
    state.kernel_id = nil
    state.pending = action
    state.path = notebook_path(bufnr)
    if not state.path then
      fail_start(state, generation, "Notebook path is no longer available")
      return false
    end

    local resolve_ok, candidate = pcall(
      deps.environment_resolve,
      state.path,
      deps.get_buf_var(bufnr, "dotfiles_notebook_metadata") or {}
    )
    if not resolve_ok then
      fail_start(
        state,
        generation,
        "Could not resolve a notebook environment: " .. tostring(candidate)
      )
      return false
    end
    if type(candidate) ~= "table" then
      fail_start(state, generation, "Could not resolve a notebook environment")
      return false
    end
    choose_candidate(bufnr, state, generation, candidate)
    return true
  end

  local function on_kernel_ready(args)
    local bufnr = args.buf
    local state = states[bufnr]
    if not state or state.phase ~= "starting" then
      return
    end

    local data = type(args.data) == "table" and args.data or {}
    if data.generation ~= nil and data.generation ~= state.generation then
      return
    end
    if not deps.buf_is_valid(bufnr) then
      reset_start(state, state.generation)
      return
    end

    state.phase = "ready"
    state.kernel_id = data.kernel_id
    close_timeout(state)

    local pending = state.pending
    local path = state.path
    state.pending = nil
    state.path = nil

    local import_ok, import_error = pcall(deps.buf_call, bufnr, function()
      deps.command("MoltenImportOutput", { path })
    end)
    if not import_ok then
      notify("Could not import notebook outputs: " .. tostring(import_error), vim.log.levels.ERROR)
    end

    if pending then
      pending()
    end
  end

  local function current_notebook_window(bufnr)
    if not notebook_path(bufnr) then
      return nil
    end
    local winid = deps.get_current_win()
    if not valid_origin(bufnr, winid) then
      notify("Notebook buffer is not displayed in the current window", vim.log.levels.WARN)
      return nil
    end
    return winid
  end

  local function ranges_for(bufnr)
    local ok, ranges = pcall(deps.cell_ranges, bufnr)
    if not ok then
      notify("Could not inspect notebook cells: " .. tostring(ranges), vim.log.levels.ERROR)
      return nil
    end
    return ranges
  end

  local function safe_command(bufnr, name, arguments, modifiers)
    local ok, command_error = pcall(deps.buf_call, bufnr, function()
      deps.command(name, arguments or {}, modifiers or {})
    end)
    if not ok then
      notify("Notebook command failed: " .. tostring(command_error), vim.log.levels.ERROR)
      return false
    end
    return true
  end

  local function with_running_kernel(bufnr, callback)
    local kernels = running_kernels()
    if not kernels then
      return false
    end
    if #kernels == 0 then
      notify("This notebook has no active kernel", vim.log.levels.WARN)
      return false
    end
    callback()
    return true
  end

  function Workflow.attach(bufnr)
    bufnr = normalize_bufnr(bufnr)
    local canonical = notebook_path(bufnr)
    if not canonical then
      return false
    end
    if attached[bufnr] then
      return true
    end

    attached[bufnr] = true
    local ok, attach_error = pcall(function()
      deps.set_buf_var(bufnr, "dotfiles_notebook", true)
      deps.buf_call(bufnr, deps.quarto_activate)
      for _, mapping in ipairs(mappings) do
        local mode, lhs, method, description = unpack(mapping)
        deps.set_keymap(mode, lhs, function()
          Workflow[method](bufnr)
        end, {
          buffer = bufnr,
          desc = description,
          silent = true,
        })
      end
    end)
    if not ok then
      attached[bufnr] = nil
      pcall(deps.set_buf_var, bufnr, "dotfiles_notebook", false)
      notify("Could not attach notebook workflow: " .. tostring(attach_error), vim.log.levels.ERROR)
      return false
    end
    return true
  end

  function Workflow.setup()
    if setup_done then
      return
    end

    local group = deps.create_augroup("dotfiles-notebook", { clear = true })
    deps.create_autocmd({ "BufReadPost", "BufEnter" }, {
      callback = function(args)
        Workflow.attach(args.buf)
      end,
      group = group,
      pattern = "*.ipynb",
    })
    deps.create_autocmd("User", {
      callback = on_kernel_ready,
      group = group,
      pattern = "MoltenKernelReady",
    })
    setup_done = true
  end

  function Workflow.run_cell(bufnr)
    bufnr = normalize_bufnr(bufnr)
    if not notebook_path(bufnr) then
      return false
    end
    local action = capture_action(bufnr, deps.quarto_run_cell, false)
    if not action then
      return false
    end
    return with_kernel(bufnr, action)
  end

  function Workflow.run_selection(bufnr)
    bufnr = normalize_bufnr(bufnr)
    if not notebook_path(bufnr) then
      return false
    end
    local action = capture_action(bufnr, deps.quarto_run_range, true)
    if not action then
      return false
    end
    return with_kernel(bufnr, action)
  end

  function Workflow.run_all(bufnr)
    bufnr = normalize_bufnr(bufnr)
    if not notebook_path(bufnr) then
      return false
    end
    local action = capture_action(bufnr, deps.quarto_run_all, false)
    if not action then
      return false
    end
    return with_kernel(bufnr, action)
  end

  function Workflow.next_cell(bufnr)
    bufnr = normalize_bufnr(bufnr)
    local winid = current_notebook_window(bufnr)
    if not winid then
      return false
    end
    local ranges = ranges_for(bufnr)
    if not ranges then
      return false
    end

    local row = deps.get_cursor(winid)[1]
    for _, range in ipairs(ranges) do
      if range[1] > row then
        deps.set_cursor(winid, { range[1], 0 })
        return true
      end
    end
    notify("Already at the last cell", vim.log.levels.INFO)
    return false
  end

  function Workflow.previous_cell(bufnr)
    bufnr = normalize_bufnr(bufnr)
    local winid = current_notebook_window(bufnr)
    if not winid then
      return false
    end
    local ranges = ranges_for(bufnr)
    if not ranges then
      return false
    end

    local row = deps.get_cursor(winid)[1]
    local anchor = row
    for _, range in ipairs(ranges) do
      if row >= range[1] and row <= range[2] then
        anchor = range[1]
        break
      end
    end

    local target
    for _, range in ipairs(ranges) do
      if range[1] < anchor then
        target = range[1]
      else
        break
      end
    end
    if target then
      deps.set_cursor(winid, { target, 0 })
      return true
    end
    notify("Already at the first cell", vim.log.levels.INFO)
    return false
  end

  function Workflow.enter_output(bufnr)
    bufnr = normalize_bufnr(bufnr)
    if not notebook_path(bufnr) then
      return false
    end
    return with_running_kernel(bufnr, function()
      safe_command(bufnr, "MoltenEnterOutput", {}, { noautocmd = true })
    end)
  end

  function Workflow.interrupt(bufnr)
    bufnr = normalize_bufnr(bufnr)
    if not notebook_path(bufnr) then
      return false
    end
    return with_running_kernel(bufnr, function()
      safe_command(bufnr, "MoltenInterrupt")
    end)
  end

  function Workflow.restart(bufnr)
    bufnr = normalize_bufnr(bufnr)
    if not notebook_path(bufnr) then
      return false
    end
    return with_running_kernel(bufnr, function()
      safe_command(bufnr, "MoltenRestart")
    end)
  end

  function Workflow.save_outputs(bufnr)
    bufnr = normalize_bufnr(bufnr)
    if not notebook_path(bufnr) then
      return false
    end
    local kernels = running_kernels()
    if not kernels then
      return false
    end
    if #kernels == 0 then
      local write_ok, write_error = pcall(deps.write_buffer, bufnr)
      if not write_ok then
        notify("Could not save notebook source: " .. tostring(write_error), vim.log.levels.ERROR)
        return false
      end
      notify("Notebook source saved; no active kernel outputs to export", vim.log.levels.INFO)
      return true
    end

    local export_ok, export_error = pcall(deps.save_export, bufnr)
    if not export_ok then
      notify("Could not export notebook outputs: " .. tostring(export_error), vim.log.levels.ERROR)
      return false
    end
    return true
  end

  return Workflow
end

local function cell_ranges(bufnr)
  local query = vim.treesitter.query.parse("markdown", "(fenced_code_block) @cell")
  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local tree = parser:parse()[1]
  local ranges = {}
  for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    local start_row, _, end_row = node:range()
    table.insert(ranges, { start_row + 1, end_row + 1 })
  end
  table.sort(ranges, function(left, right)
    return left[1] < right[1]
  end)
  return ranges
end

local default_dependencies = {
  buf_call = vim.api.nvim_buf_call,
  buf_is_valid = vim.api.nvim_buf_is_valid,
  buf_name = vim.api.nvim_buf_get_name,
  cell_ranges = cell_ranges,
  command = function(name, arguments, modifiers)
    vim.api.nvim_cmd({ args = arguments or {}, cmd = name, mods = modifiers or {} }, {})
  end,
  create_augroup = vim.api.nvim_create_augroup,
  create_autocmd = vim.api.nvim_create_autocmd,
  environment_ensure_kernel = function(candidate)
    return require("notebook.environment").ensure_kernel(candidate)
  end,
  environment_fallback = function()
    return require("notebook.environment").fallback()
  end,
  environment_resolve = function(path, metadata)
    return require("notebook.environment").resolve(path, metadata)
  end,
  get_buf_mark = vim.api.nvim_buf_get_mark,
  get_buf_var = function(bufnr, name)
    return vim.b[bufnr][name]
  end,
  get_current_buf = vim.api.nvim_get_current_buf,
  get_current_win = vim.api.nvim_get_current_win,
  get_cursor = vim.api.nvim_win_get_cursor,
  notify = vim.notify,
  quarto_activate = function()
    require("quarto").activate()
  end,
  quarto_run_all = function()
    require("quarto.runner").run_all()
  end,
  quarto_run_cell = function()
    require("quarto.runner").run_cell()
  end,
  quarto_run_range = function()
    require("quarto.runner").run_range()
  end,
  realpath = vim.uv.fs_realpath,
  running_kernels = function(local_only)
    if vim.fn.exists("*MoltenRunningKernels") == 0 then
      return {}
    end
    return vim.fn.MoltenRunningKernels(local_only)
  end,
  save_export = function(bufnr)
    return require("notebook.save").export(bufnr)
  end,
  select = vim.ui.select,
  set_buf_mark = function(bufnr, name, mark)
    vim.api.nvim_buf_set_mark(bufnr, name, mark[1], mark[2], {})
  end,
  set_buf_var = function(bufnr, name, value)
    vim.b[bufnr][name] = value
  end,
  set_current_win = vim.api.nvim_set_current_win,
  set_cursor = vim.api.nvim_win_set_cursor,
  set_keymap = vim.keymap.set,
  start_timer = function(delay, callback)
    local timer = assert(vim.uv.new_timer())
    timer:start(delay, 0, vim.schedule_wrap(callback))
    return timer
  end,
  win_get_buf = vim.api.nvim_win_get_buf,
  win_is_valid = vim.api.nvim_win_is_valid,
  write_buffer = function(bufnr)
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd.write()
    end)
  end,
}

local workflow = new(default_dependencies)
M.setup = workflow.setup
M.attach = workflow.attach
M.run_cell = workflow.run_cell
M.run_selection = workflow.run_selection
M.run_all = workflow.run_all
M.next_cell = workflow.next_cell
M.previous_cell = workflow.previous_cell
M.enter_output = workflow.enter_output
M.interrupt = workflow.interrupt
M.restart = workflow.restart
M.save_outputs = workflow.save_outputs
M._test = { new = new }

return M
