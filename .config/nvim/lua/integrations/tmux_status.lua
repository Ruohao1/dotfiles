local M = {}

local option_names = {
  "@dotfiles_nvim_mode",
  "@dotfiles_nvim_root",
  "@dotfiles_nvim_path",
  "@dotfiles_nvim_errors",
  "@dotfiles_nvim_warnings",
  "@dotfiles_nvim_line",
  "@dotfiles_nvim_column",
}

local allowed_modes = {
  NORMAL = true,
  INSERT = true,
  VISUAL = true,
  SELECT = true,
  REPLACE = true,
  COMMAND = true,
  PROMPT = true,
  TERMINAL = true,
}

local snapshot_keys = { "mode", "root", "path", "errors", "warnings", "line", "column" }

local function valid_pane(pane)
  return type(pane) == "string" and pane:match("^%%%d+$") ~= nil
end

local function contains_control(value)
  return value:find("[%z\1-\31\127]") ~= nil or value:find("\194[\128-\159]") ~= nil
end

local function strip_controls(value)
  return value:gsub("[%z\1-\31\127]", ""):gsub("\194[\128-\159]", "")
end

local function trim_graphemes_to_bytes(value, byte_limit)
  while #value > byte_limit do
    local characters = vim.fn.strchars(value, 1)
    if characters <= 0 then
      return ""
    end
    local shortened = vim.fn.strcharpart(value, 0, characters - 1, 1)
    if #shortened >= #value then
      return ""
    end
    value = shortened
  end
  return value
end

local function safe_text(value, byte_limit)
  value = strip_controls(tostring(value or ""))
  return trim_graphemes_to_bytes(value, byte_limit)
end

local function safe_root(value)
  value = tostring(value or "")
  if value == "" then
    return ""
  end
  if value:sub(1, 1) ~= "/" then
    return ""
  end
  if contains_control(value) or #value > 1024 then
    return ""
  end
  return value
end

local function decimal(value, minimum)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then
    value = minimum
  end
  value = math.floor(value)
  return tostring(math.min(999999999, math.max(minimum, value)))
end

local function tmux_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function canonicalize(snapshot)
  snapshot = snapshot or {}
  local mode = safe_text(snapshot.mode, 8)
  if not allowed_modes[mode] then
    mode = "NORMAL"
  end
  return {
    mode = mode,
    root = safe_root(snapshot.root),
    path = safe_text(snapshot.path, 512),
    errors = decimal(snapshot.errors, 0),
    warnings = decimal(snapshot.warnings, 0),
    line = decimal(snapshot.line, 1),
    column = decimal(snapshot.column, 1),
  }
end

local function copy_snapshot(snapshot)
  if snapshot == nil then
    return nil
  end
  local copy = {}
  for _, key in ipairs(snapshot_keys) do
    copy[key] = snapshot[key]
  end
  return copy
end

local function same_snapshot(left, right)
  if left == nil or right == nil then
    return left == right
  end
  for _, key in ipairs(snapshot_keys) do
    if left[key] ~= right[key] then
      return false
    end
  end
  return true
end

local function append_argv_command(argv, command)
  if #argv > 1 then
    table.insert(argv, ";")
  end
  vim.list_extend(argv, command)
end

local function claim_value(value)
  if value:sub(-1) == ";" then
    return value:sub(1, -2) .. "\\;"
  end
  return value
end

local function append_snapshot_argv(argv, pane, snapshot)
  for _, name in ipairs(option_names) do
    local key = name:gsub("^@dotfiles_nvim_", "")
    append_argv_command(argv, { "set-option", "-pt", pane, name, claim_value(snapshot[key]) })
  end
end

local function claim_argv(pane, owner, snapshot)
  local argv = { "tmux" }
  append_argv_command(argv, { "set-option", "-pt", pane, "@dotfiles_nvim_owner", owner })
  append_argv_command(argv, { "set-option", "-pt", pane, "@dotfiles_nvim_active", "0" })
  append_snapshot_argv(argv, pane, snapshot)
  append_argv_command(argv, { "set-option", "-pt", pane, "@dotfiles_nvim_active", "1" })
  return argv
end

local function set_command(pane, name, value)
  return table.concat({ "set-option -pt", pane, name, tmux_quote(value) }, " ")
end

local function update_command(pane, snapshot)
  local commands = { set_command(pane, "@dotfiles_nvim_active", "0") }
  for _, name in ipairs(option_names) do
    local key = name:gsub("^@dotfiles_nvim_", "")
    table.insert(commands, set_command(pane, name, snapshot[key]))
  end
  table.insert(commands, set_command(pane, "@dotfiles_nvim_active", "1"))
  return table.concat(commands, " ; ")
end

local function guarded_argv(pane, owner, command)
  return {
    "tmux",
    "if-shell",
    "-F",
    "-t",
    pane,
    "#{==:#{@dotfiles_nvim_owner}," .. owner .. "}",
    command,
    "",
  }
end

local function update_argv(pane, owner, snapshot)
  return guarded_argv(pane, owner, update_command(pane, snapshot))
end

local function cleanup_argv(pane, owner)
  local names = { "@dotfiles_nvim_active" }
  vim.list_extend(names, option_names)
  table.insert(names, "@dotfiles_nvim_owner")
  local commands = {}
  for _, name in ipairs(names) do
    table.insert(commands, table.concat({ "set-option -pu -t", pane, name }, " "))
  end
  return guarded_argv(pane, owner, table.concat(commands, " ; "))
end

local function new(deps)
  assert(valid_pane(deps.pane), "invalid tmux pane")
  assert(type(deps.owner) == "string" and deps.owner:match("^%d+_%d+$"), "invalid owner")

  local state = {
    stopped = false,
    claimed = false,
    debounce_generation = 0,
    desired = nil,
    published = nil,
    in_flight = nil,
    pending = nil,
    warned = false,
  }
  local controller = {}
  local launch

  local function warn_once(detail)
    if state.warned then
      return
    end
    state.warned = true
    deps.notify("tmux status publication failed: " .. tostring(detail), deps.warn_level)
  end

  local function finish(flight, result)
    deps.schedule(function()
      if state.stopped or state.in_flight ~= flight then
        return
      end
      state.in_flight = nil
      if result and result.code == 0 and result.signal == 0 then
        state.claimed = true
        state.published = flight.snapshot
        state.warned = false
      else
        local detail = result and result.stderr or ""
        warn_once(detail ~= "" and detail or "tmux exited unsuccessfully")
      end
      local pending = state.pending
      state.pending = nil
      if pending and not same_snapshot(pending, state.published) then
        launch(pending)
      end
    end)
  end

  launch = function(snapshot)
    if state.stopped then
      return
    end
    if state.in_flight then
      state.pending = snapshot
      return
    end
    local flight = { snapshot = snapshot, handle = nil }
    state.in_flight = flight
    local argv = state.claimed and update_argv(deps.pane, deps.owner, snapshot)
      or claim_argv(deps.pane, deps.owner, snapshot)
    local ok, handle = pcall(deps.system, argv, { text = true }, function(result)
      finish(flight, result)
    end)
    if ok and handle then
      flight.handle = handle
    elseif ok then
      finish(flight, { code = 1, signal = 0, stderr = "tmux process handle unavailable" })
    else
      finish(flight, { code = 1, signal = 0, stderr = handle })
    end
  end

  local function flush(generation)
    if state.stopped or generation ~= state.debounce_generation then
      return
    end
    local snapshot = state.desired
    if state.in_flight then
      state.pending = snapshot
      return
    end
    if same_snapshot(snapshot, state.published) then
      return
    end
    launch(snapshot)
  end

  function controller:request(snapshot)
    if state.stopped then
      return
    end
    state.desired = canonicalize(snapshot)
    state.debounce_generation = state.debounce_generation + 1
    local generation = state.debounce_generation
    deps.defer(function()
      flush(generation)
    end, 75)
  end

  function controller:start(snapshot)
    self:request(snapshot)
  end

  function controller:stop()
    if state.stopped then
      return
    end
    state.stopped = true
    state.debounce_generation = state.debounce_generation + 1
    state.desired = nil
    state.pending = nil
    local flight = state.in_flight
    state.in_flight = nil
    if flight and flight.handle then
      pcall(flight.handle.kill, flight.handle, 15)
      pcall(flight.handle.wait, flight.handle, 150)
    end
    local ok, handle = pcall(
      deps.system,
      cleanup_argv(deps.pane, deps.owner),
      { text = true },
      function() end
    )
    if ok and handle then
      pcall(handle.wait, handle, 200)
    end
  end

  function controller:debug_state()
    return {
      stopped = state.stopped,
      claimed = state.claimed,
      debounce_generation = state.debounce_generation,
      desired = copy_snapshot(state.desired),
      published = copy_snapshot(state.published),
      in_flight = state.in_flight ~= nil,
      pending = copy_snapshot(state.pending),
      warned = state.warned,
    }
  end

  return controller
end

function M.setup(options)
  options = options or {}
  local pane = options.pane or vim.env.TMUX_PANE
  if not (type(vim.env.TMUX) == "string" and vim.env.TMUX ~= "") then
    return nil
  end
  if not valid_pane(pane) or vim.fn.executable("tmux") ~= 1 then
    return nil
  end
  local publisher = new({
    pane = pane,
    owner = string.format("%d_%d", vim.fn.getpid(), vim.uv.hrtime()),
    system = vim.system,
    schedule = vim.schedule,
    defer = vim.defer_fn,
    notify = vim.notify,
    warn_level = vim.log.levels.WARN,
  })
  if options.snapshot then
    publisher:start(options.snapshot)
  end
  return publisher
end

M._test = {
  canonicalize = canonicalize,
  cleanup_argv = cleanup_argv,
  decimal = decimal,
  new = new,
  tmux_quote = tmux_quote,
  update_argv = update_argv,
  valid_pane = valid_pane,
}

return M
