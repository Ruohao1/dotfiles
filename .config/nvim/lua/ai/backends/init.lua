local bit = require("bit")

local M = {}

local BACKEND_NAMES = { "codex", "claude", "opencode" }
local C0_PATTERN = "[%z\1-\31\127]"
local C1_PATTERN = "\194[\128-\159]"
local GROUP_OR_OTHER_WRITE_BITS = 18
local MAX_DIAGNOSTIC_BYTES = 256
local MAX_HELP_BYTES = 65536

local function has_control(value)
  return type(value) ~= "string" or value:find(C0_PATTERN) ~= nil or value:find(C1_PATTERN) ~= nil
end

local function bound_utf8(value, limit)
  if #value <= limit then
    return value
  end
  local bounded = value:sub(1, limit)
  while #bounded > 0 and not pcall(vim.str_utfindex, bounded) do
    bounded = bounded:sub(1, -2)
  end
  return bounded
end

local function clean_text(value, limit)
  local text = type(value) == "string" and value or ""
  text = text:gsub(C1_PATTERN, " "):gsub(C0_PATTERN, " ")
  text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
  return bound_utf8(text, limit)
end

local function diagnostic(result)
  if type(result) ~= "table" then
    return "probe returned an invalid result"
  end
  local detail = clean_text(result.stderr, MAX_DIAGNOSTIC_BYTES)
  if detail == "" then
    detail = clean_text(result.stdout, MAX_DIAGNOSTIC_BYTES)
  end
  if detail == "" then
    detail = string.format("probe exited with code %s", tostring(result.code))
  end
  return detail
end

local function canonical_path(value, label, allow_root)
  if type(value) ~= "string" or value == "" or value:sub(1, 1) ~= "/" then
    return nil, label .. " must be an absolute path"
  end
  if has_control(value) then
    return nil, label .. " contains a control character"
  end
  if vim.fs.normalize(value) ~= value or (not allow_root and value == "/") then
    return nil, label .. " must be canonical"
  end
  return value
end

local function uuid_v4(random)
  local bytes = assert(random(16))
  assert(type(bytes) == "string" and #bytes == 16, "UUID provider must return 16 bytes")
  local values = { bytes:byte(1, 16) }
  values[7] = bit.bor(bit.band(values[7], 15), 64)
  values[9] = bit.bor(bit.band(values[9], 63), 128)
  local function hex(first, last)
    local output = {}
    for index = first, last do
      output[#output + 1] = string.format("%02x", values[index])
    end
    return table.concat(output)
  end
  return table.concat({
    hex(1, 4),
    hex(5, 6),
    hex(7, 8),
    hex(9, 10),
    hex(11, 16),
  }, "-")
end

local function read_only_probe(executable, arguments, overrides)
  local tools = require("ai.tools")
  local probe = overrides or {}
  local resolve = probe.resolve or tools.resolve
  local revalidate = probe.revalidate or tools.revalidate
  local environ = probe.environ or vim.fn.environ
  local run = probe.run or function(argv, options)
    return vim.system(argv, options):wait()
  end

  local executable_check_ok, executable_ok, executable_error = pcall(revalidate, executable)
  if not executable_check_ok or not executable_ok then
    return {
      code = 126,
      signal = 0,
      stdout = "",
      stderr = executable_check_ok and executable_error or executable_ok,
    }
  end

  local bwrap, resolve_error = resolve("bwrap")
  if not bwrap then
    return { code = 127, signal = 0, stdout = "", stderr = resolve_error }
  end
  local bwrap_check_ok, bwrap_ok, bwrap_error = pcall(revalidate, bwrap)
  if not bwrap_check_ok or not bwrap_ok then
    return {
      code = 126,
      signal = 0,
      stdout = "",
      stderr = bwrap_check_ok and bwrap_error or bwrap_ok,
    }
  end

  local argv = {
    bwrap,
    "--new-session",
    "--unshare-pid",
    "--unshare-ipc",
    "--unshare-uts",
    "--unshare-net",
    "--die-with-parent",
    "--ro-bind",
    "/",
    "/",
    "--dev",
    "/dev",
    "--proc",
    "/proc",
    "--tmpfs",
    "/tmp",
    "--",
    executable,
  }
  vim.list_extend(argv, arguments)
  local environment = environ()
  environment.TMUX = nil
  environment.TMUX_PANE = nil
  environment.NVIM = nil
  environment.NVIM_LISTEN_ADDRESS = nil

  local ok, result = pcall(function()
    return run(argv, {
      text = true,
      timeout = 2000,
      clear_env = true,
      env = environment,
    })
  end)
  if not ok then
    return { code = 126, signal = 0, stdout = "", stderr = tostring(result) }
  end
  return result
end

local function runtime_dependencies()
  return {
    executable = function(name)
      return require("ai.tools").resolve(name)
    end,
    revalidate = function(executable)
      return require("ai.tools").revalidate(executable)
    end,
    version = function(_, executable)
      return read_only_probe(executable, { "--version" })
    end,
    auth = function(name, executable)
      local arguments = {
        codex = { "login", "status" },
        claude = { "auth", "status", "--json" },
        opencode = { "providers", "list" },
      }
      return read_only_probe(executable, assert(arguments[name]))
    end,
    help = function(_, executable, arguments)
      return read_only_probe(executable, arguments)
    end,
    uuid = function()
      return uuid_v4(vim.uv.random)
    end,
    port = function()
      local socket = assert(vim.uv.new_tcp())
      assert(socket:bind("127.0.0.1", 0))
      local name = assert(socket:getsockname())
      socket:close()
      return assert(name.port)
    end,
    password = function()
      return vim.fn.sha256(assert(vim.uv.random(32))):sub(1, 32)
    end,
    stat = vim.uv.fs_lstat,
    uid = vim.uv.getuid,
  }
end

local function new(deps)
  assert(type(deps) == "table", "backend dependencies are required")
  local services = {}
  for key, value in pairs(deps) do
    services[key] = value
  end

  function services.resolve_executable(name)
    local ok, executable, resolve_error = pcall(deps.executable, name)
    if not ok then
      return nil,
        "executable resolution failed: " .. clean_text(executable, MAX_DIAGNOSTIC_BYTES),
        false
    end
    if not executable then
      return nil, clean_text(resolve_error, MAX_DIAGNOSTIC_BYTES), false
    end
    local canonical, canonical_error = canonical_path(executable, name .. " executable", false)
    if not canonical then
      return nil, canonical_error, true
    end
    local stat = deps.stat(canonical)
    if not stat or stat.type ~= "file" then
      return nil, name .. " executable is not a nonsymlink regular file", true
    end
    if type(deps.revalidate) ~= "function" then
      return nil, name .. " executable cannot be revalidated", true
    end
    local check_ok, valid, validation_error = pcall(deps.revalidate, canonical)
    if not check_ok or not valid then
      return nil, clean_text(check_ok and validation_error or valid, MAX_DIAGNOSTIC_BYTES), true
    end
    return canonical, nil, true
  end

  function services.validate_launch(identity, paths)
    if type(identity) ~= "table" then
      return nil, "AI identity is required"
    end
    local root, root_error = canonical_path(identity.root, "AI root", false)
    if not root then
      return nil, root_error
    end
    if type(paths) ~= "table" then
      return nil, "backend paths are required"
    end
    local backend_state, state_error =
      canonical_path(paths.backend_state, "backend state path", false)
    if not backend_state then
      return nil, state_error
    end
    if type(paths.grants) ~= "table" or not vim.islist(paths.grants) then
      return nil, "scope grants must be a sorted list"
    end
    local grants = {}
    local previous
    for _, grant in ipairs(paths.grants) do
      local canonical, grant_error = canonical_path(grant, "scope grant", false)
      if not canonical then
        return nil, grant_error
      end
      if previous and canonical <= previous then
        return nil, "scope grants must be sorted and unique"
      end
      grants[#grants + 1] = canonical
      previous = canonical
    end
    return { root = root, backend_state = backend_state, grants = grants }
  end

  function services.destination(backend_state, relative)
    if type(relative) ~= "string" or relative == "" or relative:sub(1, 1) == "/" then
      return nil, "read-only input destination is invalid"
    end
    local destination = vim.fs.normalize(backend_state .. "/" .. relative)
    if destination:sub(1, #backend_state + 1) ~= backend_state .. "/" then
      return nil, "read-only input destination escapes backend state"
    end
    return destination
  end

  function services.provider_path(path, kind, label)
    local canonical, canonical_error = canonical_path(path, label, false)
    if not canonical then
      return nil, canonical_error
    end
    local stat = deps.stat(canonical)
    if not stat then
      return nil
    end
    if stat.type ~= kind then
      return nil, label .. " has the wrong type"
    end
    if type(stat.mode) ~= "number" or bit.band(stat.mode, GROUP_OR_OTHER_WRITE_BITS) ~= 0 then
      return nil, label .. " has an unsafe mode"
    end
    if type(stat.uid) ~= "number" or stat.uid ~= deps.uid() then
      return nil, label .. " has an unsafe owner"
    end
    return canonical
  end

  function services.read_only_input(source, destination, kind, backend_state, label)
    local canonical_source, source_error = services.provider_path(source, kind, label)
    if source_error then
      return nil, source_error
    end
    if not canonical_source then
      return nil
    end
    local canonical_destination, destination_error =
      services.destination(backend_state, destination)
    if not canonical_destination then
      return nil, destination_error
    end
    return {
      source = canonical_source,
      destination = canonical_destination,
      kind = kind,
    }
  end

  local function probe(executable, callback, ...)
    local check_ok, valid, validation_error = pcall(deps.revalidate, executable)
    if not check_ok or not valid then
      return nil, clean_text(check_ok and validation_error or valid, MAX_DIAGNOSTIC_BYTES)
    end
    local ok, result = pcall(callback, ...)
    if not ok then
      return nil, clean_text(result, MAX_DIAGNOSTIC_BYTES)
    end
    if
      type(result) ~= "table"
      or type(result.code) ~= "number"
      or type(result.stdout) ~= "string"
      or type(result.stderr) ~= "string"
    then
      return nil, "probe returned an invalid result"
    end
    return result
  end

  function services.health_backend(name, capabilities, help_requirements)
    local executable, executable_error, installed = services.resolve_executable(name)
    if not executable then
      return {
        installed = installed,
        executable = "",
        version = "",
        auth = "unknown",
        capabilities = {},
        error = clean_text(executable_error, MAX_DIAGNOSTIC_BYTES),
      }
    end

    local version_result, version_error = probe(executable, deps.version, name, executable)
    if not version_result or version_result.code ~= 0 then
      return {
        installed = true,
        executable = executable,
        version = "",
        auth = "unknown",
        capabilities = {},
        error = clean_text(
          "version probe failed: " .. (version_error or diagnostic(version_result)),
          MAX_DIAGNOSTIC_BYTES
        ),
      }
    end
    local version = clean_text(version_result.stdout, MAX_DIAGNOSTIC_BYTES)
    if version == "" then
      return {
        installed = true,
        executable = executable,
        version = "",
        auth = "unknown",
        capabilities = {},
        error = "version probe returned no version",
      }
    end

    for _, requirement in ipairs(help_requirements) do
      local help_result, help_error =
        probe(executable, deps.help, name, executable, vim.deepcopy(requirement.arguments))
      if not help_result or help_result.code ~= 0 then
        return {
          installed = true,
          executable = executable,
          version = version,
          auth = "unknown",
          capabilities = {},
          error = clean_text(
            "compatibility probe failed: " .. (help_error or diagnostic(help_result)),
            MAX_DIAGNOSTIC_BYTES
          ),
        }
      end
      local output = (help_result.stdout .. "\n" .. help_result.stderr):sub(1, MAX_HELP_BYTES)
      for _, flag in ipairs(requirement.flags) do
        if not output:find(flag, 1, true) then
          return {
            installed = true,
            executable = executable,
            version = version,
            auth = "unknown",
            capabilities = {},
            error = clean_text(
              string.format("incompatible %s CLI: missing %s", name, flag),
              MAX_DIAGNOSTIC_BYTES
            ),
          }
        end
      end
    end

    local auth_result, auth_error = probe(executable, deps.auth, name, executable)
    local auth = "unknown"
    local health_error = ""
    if not auth_result or auth_result.code ~= 0 then
      health_error = clean_text(
        "authentication status unavailable: " .. (auth_error or diagnostic(auth_result)),
        MAX_DIAGNOSTIC_BYTES
      )
    else
      local auth_text = clean_text(auth_result.stdout .. " " .. auth_result.stderr, 4096):lower()
      local compact_auth = auth_text:gsub("%s+", "")
      if
        auth_text:find("not authenticated", 1, true)
        or auth_text:find("not logged in", 1, true)
        or auth_text:find("logged out", 1, true)
        or compact_auth:find('"authenticated":false', 1, true)
        or compact_auth:find('"loggedin":false', 1, true)
      then
        auth = "unauthenticated"
      elseif
        auth_text:find("authenticated", 1, true)
        or auth_text:find("logged in", 1, true)
        or compact_auth:find('"authenticated":true', 1, true)
        or compact_auth:find('"loggedin":true', 1, true)
        or auth_text ~= ""
      then
        auth = "authenticated"
      end
    end

    return {
      installed = true,
      executable = executable,
      version = version,
      auth = auth,
      capabilities = vim.deepcopy(capabilities),
      error = health_error,
    }
  end

  function services.format_context(context)
    if type(context) ~= "table" or type(context.path) ~= "string" or context.path == "" then
      return ""
    end
    if has_control(context.path) then
      return ""
    end
    if
      context.kind == "location"
      and type(context.line) == "number"
      and context.line >= 1
      and context.line % 1 == 0
      and type(context.column) == "number"
      and context.column >= 1
      and context.column % 1 == 0
    then
      return string.format("Regarding %s:%d:%d: ", context.path, context.line, context.column)
    end
    if
      context.kind == "selection"
      and type(context.first) == "number"
      and context.first >= 1
      and context.first % 1 == 0
      and type(context.last) == "number"
      and context.last >= context.first
      and context.last % 1 == 0
      and type(context.context_file) == "string"
      and context.context_file:sub(1, 1) == "/"
      and not has_control(context.context_file)
    then
      return string.format(
        "Use the exact selection from %s:%d-%d stored at %s: ",
        context.path,
        context.first,
        context.last,
        context.context_file
      )
    end
    return ""
  end

  local adapters = {
    codex = require("ai.backends.codex").new(services),
    claude = require("ai.backends.claude").new(services),
    opencode = require("ai.backends.opencode").new(services),
  }
  return {
    names = function()
      return vim.deepcopy(BACKEND_NAMES)
    end,
    get = function(_, name)
      return adapters[name]
    end,
    health = function(_, name)
      local adapter = adapters[name]
      if not adapter then
        return {
          installed = false,
          executable = "",
          version = "",
          auth = "unknown",
          capabilities = {},
          error = "unknown backend",
        }
      end
      return adapter:health()
    end,
  }
end

local runtime

local function runtime_registry()
  if not runtime then
    runtime = new(runtime_dependencies())
  end
  return runtime
end

function M.names()
  return vim.deepcopy(BACKEND_NAMES)
end

function M.get(name)
  return runtime_registry():get(name)
end

function M.health(name)
  return runtime_registry():health(name)
end

M._test = {
  new = new,
  read_only_probe = read_only_probe,
  uuid = uuid_v4,
}

return M
