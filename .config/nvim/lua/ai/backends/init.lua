local bit = require("bit")

local M = {}

local BACKEND_NAMES = { "codex", "claude", "opencode" }
local C0_PATTERN = "[%z\1-\31\127]"
local C1_PATTERN = "\194[\128-\159]"
local GROUP_OR_OTHER_WRITE_BITS = 18
local MAX_DIAGNOSTIC_BYTES = 256
local MAX_HELP_BYTES = 65536
local MAX_AUTH_BYTES = 65536
local MAX_PROFILE_REPORT_BYTES = 65536
local MAX_COMPATIBILITY_REPORT_BYTES = 1024 * 1024
local AUTH_ARGUMENTS = {
  codex = { "login", "status" },
  claude = { "auth", "status", "--json" },
}

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

local function auth_arguments(name)
  local arguments = AUTH_ARGUMENTS[name]
  return arguments and vim.deepcopy(arguments) or nil
end

local function auth_output(value)
  local text = type(value) == "string" and value:sub(1, MAX_AUTH_BYTES) or ""
  text = text:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
  text = text:gsub(C1_PATTERN, " ")
  text = text:gsub("[%z\1-\9\11\12\14-\31\127]", " ")
  return text
end

local function auth_lines(value)
  local lines = {}
  for line in (auth_output(value):gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line:match("^%s*(.-)%s*$")
  end
  return lines
end

local function parse_codex_auth(result)
  local positive_lines = {
    ["logged in using chatgpt"] = true,
    ["logged in using an api key"] = true,
    ["logged in using workload identity"] = true,
    ["logged in using access token"] = true,
    ["logged in using personal access token"] = true,
    ["logged in using amazon bedrock api key"] = true,
    ["logged in using agent identity"] = true,
  }
  for _, line in ipairs(auth_lines(result.stdout .. "\n" .. result.stderr)) do
    local lower = line:lower()
    if lower:find("not logged in", 1, true) == 1 then
      return "unauthenticated"
    end
  end
  for _, line in ipairs(auth_lines(result.stdout)) do
    local lower = line:lower()
    if positive_lines[lower] or lower:match("^logged in using an api key %- .+$") then
      return "authenticated"
    end
  end
  return "unknown"
end

local function parse_claude_auth(result)
  local ok, decoded = pcall(vim.json.decode, auth_output(result.stdout))
  if not ok or type(decoded) ~= "table" or type(decoded.loggedIn) ~= "boolean" then
    return "unknown"
  end
  return decoded.loggedIn and "authenticated" or "unauthenticated"
end

local AUTH_PARSERS = {
  codex = parse_codex_auth,
  claude = parse_claude_auth,
}

local function parse_auth(name, result)
  local parser = AUTH_PARSERS[name]
  return parser and parser(result) or "unknown"
end

local function auth_diagnostic(name, result)
  if type(result) ~= "table" then
    return clean_text(
      string.format("authentication status unavailable: %s probe could not run", name),
      MAX_DIAGNOSTIC_BYTES
    )
  end
  if result.code ~= 0 then
    return clean_text(
      string.format(
        "authentication status unavailable: %s probe exited with code %s",
        name,
        tostring(result.code)
      ),
      MAX_DIAGNOSTIC_BYTES
    )
  end
  return clean_text(
    string.format("authentication status unavailable: unrecognized %s status", name),
    MAX_DIAGNOSTIC_BYTES
  )
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
  }
  if probe.working_directory ~= nil then
    local working_directory, directory_error =
      canonical_path(probe.working_directory, "probe working directory", false)
    if not working_directory then
      return { code = 126, signal = 0, stdout = "", stderr = directory_error }
    end
    argv[#argv + 1] = "--dir"
    argv[#argv + 1] = working_directory
  end
  if probe.read_only_mounts ~= nil then
    if type(probe.read_only_mounts) ~= "table" or not vim.islist(probe.read_only_mounts) then
      return { code = 126, signal = 0, stdout = "", stderr = "probe mounts are invalid" }
    end
    local mounts = {}
    for _, mount in ipairs(probe.read_only_mounts) do
      if type(mount) ~= "table" then
        return { code = 126, signal = 0, stdout = "", stderr = "probe mount is invalid" }
      end
      local source, source_error = canonical_path(mount.source, "probe mount source", false)
      local destination, destination_error =
        canonical_path(mount.destination, "probe mount destination", false)
      if not source or not destination then
        return {
          code = 126,
          signal = 0,
          stdout = "",
          stderr = source_error or destination_error,
        }
      end
      mounts[#mounts + 1] = { source = source, destination = destination }
    end
    for _, mount in ipairs(mounts) do
      vim.list_extend(argv, { "--dir", mount.destination })
    end
    for _, mount in ipairs(mounts) do
      vim.list_extend(argv, { "--ro-bind", mount.source, mount.destination })
    end
  end
  if probe.working_directory ~= nil then
    vim.list_extend(argv, { "--chdir", probe.working_directory })
  end
  vim.list_extend(argv, { "--", executable })
  vim.list_extend(argv, arguments)
  local environment
  if probe.environment ~= nil then
    if type(probe.environment) ~= "table" then
      return { code = 126, signal = 0, stdout = "", stderr = "probe environment is invalid" }
    end
    environment = vim.deepcopy(probe.environment)
  else
    environment = environ()
    environment.TMUX = nil
    environment.TMUX_PANE = nil
    environment.NVIM = nil
    environment.NVIM_LISTEN_ADDRESS = nil
  end

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

local OPENCODE_COMPATIBILITY_CACHE = {}

local function executable_metadata(stat)
  if
    type(stat) ~= "table"
    or stat.type ~= "file"
    or type(stat.dev) ~= "number"
    or type(stat.ino) ~= "number"
    or type(stat.mode) ~= "number"
    or type(stat.uid) ~= "number"
    or type(stat.size) ~= "number"
    or type(stat.mtime) ~= "table"
    or type(stat.mtime.sec) ~= "number"
    or type(stat.mtime.nsec) ~= "number"
    or type(stat.ctime) ~= "table"
    or type(stat.ctime.sec) ~= "number"
    or type(stat.ctime.nsec) ~= "number"
  then
    return nil
  end
  return table.concat({
    tostring(stat.dev),
    tostring(stat.ino),
    tostring(stat.mode),
    tostring(stat.uid),
    tostring(stat.size),
    string.format("%d:%d", stat.mtime.sec, stat.mtime.nsec),
    string.format("%d:%d", stat.ctime.sec, stat.ctime.nsec),
  }, ":")
end

local function create_opencode_probe_tree()
  local root = vim.fn.tempname()
  local home = root .. "/home"
  local config = root .. "/xdg-config"
  local created = false
  local ok = pcall(function()
    assert(vim.fn.mkdir(root, "p", 448) == 1)
    created = true
    assert(vim.fn.mkdir(home, "", 448) == 1)
    assert(vim.fn.mkdir(config, "", 448) == 1)
    for _, path in ipairs({ root, home, config }) do
      assert(vim.uv.fs_chmod(path, 448))
      local stat = assert(vim.uv.fs_lstat(path))
      assert(stat.type == "directory" and stat.uid == vim.uv.getuid())
      assert(bit.band(stat.mode, 511) == 448)
    end
  end)
  if not ok then
    if created then
      pcall(vim.fn.delete, root, "rf")
    end
    return nil, "managed OpenCode probe directory creation failed"
  end
  return { root = root, home = home, config = config }
end

local function valid_probe_result(result)
  return type(result) == "table"
    and type(result.code) == "number"
    and type(result.stdout) == "string"
    and type(result.stderr) == "string"
end

local function opencode_probe_environment()
  local managed = require("ai.backends.opencode_managed")
  return {
    HOME = "/tmp/nvim-ai-probe/home",
    OPENCODE_CONFIG_CONTENT = managed.config_json(),
    OPENCODE_DISABLE_AUTOUPDATE = "true",
    OPENCODE_DISABLE_CLAUDE_CODE = "true",
    OPENCODE_DISABLE_EXTERNAL_SKILLS = "true",
    OPENCODE_DISABLE_LSP_DOWNLOAD = "true",
    OPENCODE_DISABLE_PROJECT_CONFIG = "true",
    OPENCODE_PERMISSION = managed.policy_json(),
    OPENCODE_PURE = "true",
    XDG_CACHE_HOME = "/tmp/nvim-ai-probe/xdg-cache",
    XDG_CONFIG_HOME = "/tmp/nvim-ai-probe/xdg-config",
    XDG_DATA_HOME = "/tmp/nvim-ai-probe/xdg-data",
    XDG_STATE_HOME = "/tmp/nvim-ai-probe/xdg-state",
  }
end

local function opencode_compatibility(executable, overrides)
  local options = overrides or {}
  local revalidate = options.revalidate or require("ai.tools").revalidate
  local stat = options.stat or vim.uv.fs_lstat
  local canonical, canonical_error = canonical_path(executable, "OpenCode executable", false)
  if not canonical then
    return nil, canonical_error
  end
  local valid_ok, valid = pcall(revalidate, canonical)
  if not valid_ok or not valid then
    return nil, "managed OpenCode executable validation failed"
  end
  local before = executable_metadata(stat(canonical))
  if not before then
    return nil, "managed OpenCode executable metadata is invalid"
  end
  local cached = OPENCODE_COMPATIBILITY_CACHE[canonical]
  if cached and cached.metadata == before then
    return vim.deepcopy(cached.report)
  end

  local tree
  local owns_tree = false
  if options.probe then
    tree = options.tree
      or {
        home = "/tmp/nvim-ai-opencode-probe-home",
        config = "/tmp/nvim-ai-opencode-probe-config",
      }
  else
    local tree_error
    tree, tree_error = create_opencode_probe_tree()
    if not tree then
      return nil, tree_error
    end
    owns_tree = true
  end
  local probe_options = {
    environment = opencode_probe_environment(),
    working_directory = "/tmp/nvim-ai-probe",
    read_only_mounts = {
      { source = tree.home, destination = "/tmp/nvim-ai-probe/home" },
      { source = tree.config, destination = "/tmp/nvim-ai-probe/xdg-config" },
    },
  }
  local function run(arguments)
    local check_ok, check = pcall(revalidate, canonical)
    if not check_ok or not check then
      return nil
    end
    local ok, result
    if options.probe then
      ok, result =
        pcall(options.probe, canonical, vim.deepcopy(arguments), vim.deepcopy(probe_options))
    else
      ok, result = pcall(read_only_probe, canonical, arguments, probe_options)
    end
    if
      not ok
      or not valid_probe_result(result)
      or #result.stdout > MAX_COMPATIBILITY_REPORT_BYTES
      or #result.stderr > MAX_HELP_BYTES
    then
      return nil
    end
    return result
  end

  local commands = {
    version = { "--version" },
    root_help = { "--help" },
    serve_help = { "serve", "--help" },
    attach_help = { "attach", "--help" },
    names = { "--pure", "agent", "list" },
    build = { "--pure", "debug", "agent", "build" },
    plan = { "--pure", "debug", "agent", "plan" },
    compaction = { "--pure", "debug", "agent", "compaction" },
    summary = { "--pure", "debug", "agent", "summary" },
    title = { "--pure", "debug", "agent", "title" },
    general = { "--pure", "debug", "agent", "general" },
    explore = { "--pure", "debug", "agent", "explore" },
  }
  local order = {
    "version",
    "root_help",
    "serve_help",
    "attach_help",
    "names",
    "build",
    "plan",
    "compaction",
    "summary",
    "title",
    "general",
    "explore",
  }
  local results = {}
  for _, name in ipairs(order) do
    results[name] = run(commands[name])
    if not results[name] then
      if owns_tree then
        pcall(vim.fn.delete, tree.root, "rf")
      end
      return nil, "managed OpenCode compatibility probe failed"
    end
  end
  if owns_tree then
    pcall(vim.fn.delete, tree.root, "rf")
  end

  local forbidden_evidence = {
    "installing configuration dependenc",
    "downloading plugin",
    "loading plugin",
    "checking for update",
    "downloading lsp",
    "network request",
  }
  for _, name in ipairs(order) do
    local output = (results[name].stdout .. "\n" .. results[name].stderr):lower()
    for _, evidence in ipairs(forbidden_evidence) do
      if output:find(evidence, 1, true) then
        return nil, "managed OpenCode probe observed forbidden side-effect evidence"
      end
    end
  end

  local version = results.version
  if
    version.code ~= 0
    or version.stderr ~= ""
    or (version.stdout ~= "1.18.18" and version.stdout ~= "1.18.18\n")
  then
    return nil, "managed OpenCode exact version probe failed"
  end

  local help_requirements = {
    root_help = { "--pure", "serve", "attach" },
    serve_help = { "--hostname", "--port", "OPENCODE_SERVER_PASSWORD" },
    attach_help = { "--dir", "--session" },
  }
  for name, requirements in pairs(help_requirements) do
    local result = results[name]
    if result.code ~= 0 or result.stderr ~= "" or #result.stdout > MAX_HELP_BYTES then
      return nil, "managed OpenCode command compatibility probe failed"
    end
    for _, requirement in ipairs(requirements) do
      if not result.stdout:find(requirement, 1, true) then
        return nil, "managed OpenCode command compatibility probe failed"
      end
    end
  end

  local names_result = results.names
  if
    names_result.code ~= 0
    or names_result.stderr ~= ""
    or #names_result.stdout > MAX_HELP_BYTES
  then
    return nil, "managed OpenCode agent-list probe failed"
  end
  local names = {}
  local seen = {}
  for line in (names_result.stdout:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
    local name = line:match("^([%w_-]+) %([%w_-]+%)$")
    if name then
      if seen[name] then
        return nil, "managed OpenCode agent-list probe failed"
      end
      seen[name] = true
      names[#names + 1] = name
    end
  end
  table.sort(names)

  local agents = {}
  for _, name in ipairs({ "build", "plan", "compaction", "summary", "title" }) do
    local result = results[name]
    if
      result.code ~= 0
      or result.stderr ~= ""
      or #result.stdout > MAX_COMPATIBILITY_REPORT_BYTES
    then
      return nil, "managed OpenCode agent probe failed"
    end
    local decoded_ok, decoded = pcall(vim.json.decode, result.stdout)
    if not decoded_ok or type(decoded) ~= "table" then
      return nil, "managed OpenCode agent probe failed"
    end
    if name == "build" or name == "plan" then
      agents[name] = {
        native = decoded.native,
        mode = decoded.mode,
        tools = decoded.tools,
        permission = decoded.permission,
      }
    else
      agents[name] = {
        native = decoded.native,
        hidden = decoded.hidden,
        tools = decoded.tools,
        permission = decoded.permission,
      }
    end
  end
  for _, name in ipairs({ "general", "explore" }) do
    local result = results[name]
    local expected = "Agent " .. name .. " not found"
    local output = result.stderr ~= "" and result.stderr or result.stdout
    if
      result.code == 0
      or (result.stderr ~= "" and result.stdout ~= "")
      or (output ~= expected and output ~= expected .. "\n")
    then
      return nil, "managed OpenCode disabled-agent probe failed"
    end
  end

  local report = {
    version = "1.18.18",
    help = {
      root = { "--pure", "serve", "attach" },
      serve = { "--hostname", "--port", "OPENCODE_SERVER_PASSWORD" },
      attach = { "--dir", "--session" },
    },
    names = names,
    agents = agents,
  }
  local managed = require("ai.backends.opencode_managed")
  if not managed.validate_compatibility(report) then
    return nil, "managed OpenCode compatibility validation failed"
  end
  local final_ok, final_valid = pcall(revalidate, canonical)
  local after = executable_metadata(stat(canonical))
  if not final_ok or not final_valid or after ~= before then
    return nil, "managed OpenCode executable changed during compatibility validation"
  end
  OPENCODE_COMPATIBILITY_CACHE[canonical] = {
    metadata = before,
    report = vim.deepcopy(report),
  }
  return report
end

local PROFILE_HELPER_REQUEST_KEYS = {
  prepare = {
    "schema",
    "token",
    "identity_key",
    "root",
    "backend_state",
    "global_auth",
    "user_agents",
    "repo_agents",
    "version",
    "config_json",
    "policy_json",
  },
  ["inspect-auth"] = { "global_auth" },
  ["inspect-profile"] = {
    "schema",
    "backend_state",
    "token",
    "identity_key",
    "root",
    "version",
    "fingerprint",
  },
}

local PROFILE_HELPER_REPORT_KEYS = {
  prepare = {
    "schema",
    "version",
    "profile_root",
    "fingerprint",
    "config_source",
    "auth_source",
    "home_mask_source",
    "auth",
    "credential_count",
  },
  ["inspect-auth"] = { "auth", "count" },
  ["inspect-profile"] = {
    "schema",
    "version",
    "profile_root",
    "fingerprint",
    "config_source",
    "auth_source",
    "home_mask_source",
    "auth",
    "credential_count",
  },
}

local function exact_object(value, keys)
  if type(value) ~= "table" or vim.islist(value) then
    return false
  end
  local expected = {}
  for _, key in ipairs(keys) do
    expected[key] = true
    if value[key] == nil then
      return false
    end
  end
  for key in pairs(value) do
    if type(key) ~= "string" or not expected[key] then
      return false
    end
  end
  return true
end

local function canonical_request_json(operation, request)
  local keys = PROFILE_HELPER_REQUEST_KEYS[operation]
  if not keys or not exact_object(request, keys) then
    return nil
  end
  local fields = {}
  for _, key in ipairs(keys) do
    local encoded_ok, encoded = pcall(vim.json.encode, request[key])
    if not encoded_ok or type(encoded) ~= "string" then
      return nil
    end
    fields[#fields + 1] = vim.json.encode(key) .. ":" .. encoded
  end
  return "{" .. table.concat(fields, ",") .. "}\n"
end

local function invoke_profile_helper(paths, operation, request, overrides)
  if type(paths) ~= "table" then
    return nil, "managed OpenCode profile helper paths are invalid"
  end
  local python = canonical_path(paths.python, "OpenCode Python", false)
  local helper = canonical_path(paths.profile_helper, "OpenCode profile helper", false)
  if not python or not helper then
    return nil, "managed OpenCode profile helper paths are invalid"
  end
  local stdin = canonical_request_json(operation, request)
  if not stdin then
    return nil, "managed OpenCode profile helper request is invalid"
  end
  local options = overrides or {}
  local revalidate = options.revalidate or require("ai.tools").revalidate
  for _, path in ipairs({ python, helper }) do
    local check_ok, valid = pcall(revalidate, path)
    if not check_ok or not valid then
      return nil, "managed OpenCode profile helper validation failed"
    end
  end
  local run = options.run
    or function(argv, system_options)
      return vim.system(argv, system_options):wait()
    end
  local argv = { python, "-I", "-B", helper, "--operation", operation }
  local run_ok, result = pcall(run, argv, {
    clear_env = true,
    env = { LANG = "C.UTF-8" },
    text = true,
    timeout = 5000,
    stdin = stdin,
  })
  if
    not run_ok
    or not valid_probe_result(result)
    or result.code ~= 0
    or result.stderr ~= ""
    or #result.stdout > MAX_PROFILE_REPORT_BYTES
  then
    return nil, "managed OpenCode profile helper failed"
  end
  local decoded_ok, decoded = pcall(vim.json.decode, result.stdout)
  if not decoded_ok or not exact_object(decoded, assert(PROFILE_HELPER_REPORT_KEYS[operation])) then
    return nil, "managed OpenCode profile helper returned an invalid report"
  end
  return decoded
end

local function runtime_opencode_paths()
  local tools = require("ai.tools")
  local python, python_error = tools.resolve("python3")
  if not python then
    return nil, python_error
  end
  local helper_candidate = vim.fn.stdpath("config") .. "/scripts/nvim-ai-opencode-profile.py"
  local helper = vim.uv.fs_realpath(helper_candidate)
  if type(helper) ~= "string" or helper == "" or vim.fs.normalize(helper) ~= helper then
    return nil, "managed OpenCode profile helper is unavailable"
  end
  local helper_stat = vim.uv.fs_lstat(helper)
  if
    not helper_stat
    or helper_stat.type ~= "file"
    or helper_stat.uid ~= vim.uv.getuid()
    or bit.band(helper_stat.mode, GROUP_OR_OTHER_WRITE_BITS) ~= 0
  then
    return nil, "managed OpenCode profile helper is unsafe"
  end

  local inherited_home = vim.env.HOME
  local home = type(inherited_home) == "string" and vim.uv.fs_realpath(inherited_home) or nil
  if type(home) ~= "string" or home == "" or vim.fs.normalize(home) ~= home then
    return nil, "managed OpenCode inherited home is invalid"
  end
  local home_stat = vim.uv.fs_lstat(home)
  if
    not home_stat
    or home_stat.type ~= "directory"
    or home_stat.uid ~= vim.uv.getuid()
    or bit.band(home_stat.mode, GROUP_OR_OTHER_WRITE_BITS) ~= 0
  then
    return nil, "managed OpenCode inherited home is unsafe"
  end
  local data_candidate = vim.env.XDG_DATA_HOME
  if type(data_candidate) ~= "string" or data_candidate == "" then
    data_candidate = home .. "/.local/share"
  end
  local data_root = vim.uv.fs_realpath(data_candidate)
  if type(data_root) ~= "string" or data_root == "" or vim.fs.normalize(data_root) ~= data_root then
    return nil, "managed OpenCode data root is invalid"
  end
  local data_stat = vim.uv.fs_lstat(data_root)
  if
    not data_stat
    or data_stat.type ~= "directory"
    or data_stat.uid ~= vim.uv.getuid()
    or bit.band(data_stat.mode, GROUP_OR_OTHER_WRITE_BITS) ~= 0
  then
    return nil, "managed OpenCode data root is unsafe"
  end
  return {
    python = python,
    profile_helper = helper,
    home_agents = home .. "/AGENTS.md",
    global_opencode_data = data_root .. "/opencode",
  }
end

local function runtime_helper_revalidate(path, expected)
  if path == expected.python then
    return require("ai.tools").revalidate(path)
  end
  if path ~= expected.profile_helper or vim.uv.fs_realpath(path) ~= path then
    return nil, "managed OpenCode profile helper changed"
  end
  local stat = vim.uv.fs_lstat(path)
  if
    not stat
    or stat.type ~= "file"
    or stat.uid ~= vim.uv.getuid()
    or bit.band(stat.mode, GROUP_OR_OTHER_WRITE_BITS) ~= 0
  then
    return nil, "managed OpenCode profile helper changed"
  end
  return true
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
      return read_only_probe(executable, assert(auth_arguments(name)))
    end,
    help = function(_, executable, arguments)
      return read_only_probe(executable, arguments)
    end,
    opencode_compatibility = opencode_compatibility,
    opencode_paths = runtime_opencode_paths,
    opencode_auth_path = function()
      local paths, paths_error = runtime_opencode_paths()
      if not paths then
        error(paths_error)
      end
      return paths.global_opencode_data .. "/auth.json"
    end,
    prepare_opencode_profile = function(request, supplied_paths)
      local expected, paths_error = runtime_opencode_paths()
      if not expected then
        return nil, paths_error
      end
      if
        type(supplied_paths) ~= "table"
        or supplied_paths.python ~= expected.python
        or supplied_paths.profile_helper ~= expected.profile_helper
      then
        return nil, "managed OpenCode profile helper paths changed"
      end
      return invoke_profile_helper(expected, "prepare", request, {
        revalidate = function(path)
          return runtime_helper_revalidate(path, expected)
        end,
      })
    end,
    inspect_opencode_profile = function(request, supplied_paths)
      local expected, paths_error = runtime_opencode_paths()
      if not expected then
        return nil, paths_error
      end
      if
        type(supplied_paths) ~= "table"
        or supplied_paths.python ~= expected.python
        or supplied_paths.profile_helper ~= expected.profile_helper
      then
        return nil, "managed OpenCode profile helper paths changed"
      end
      return invoke_profile_helper(expected, "inspect-profile", request, {
        revalidate = function(path)
          return runtime_helper_revalidate(path, expected)
        end,
      })
    end,
    inspect_opencode_auth = function(path)
      local expected, paths_error = runtime_opencode_paths()
      if not expected then
        return nil, paths_error
      end
      local report, report_error = invoke_profile_helper(
        expected,
        "inspect-auth",
        { global_auth = path },
        {
          revalidate = function(candidate)
            return runtime_helper_revalidate(candidate, expected)
          end,
        }
      )
      if not report then
        return nil, report_error
      end
      if
        (report.auth ~= "authenticated" and report.auth ~= "unauthenticated")
        or type(report.count) ~= "number"
        or report.count % 1 ~= 0
        or report.count < 0
        or report.count > 128
        or (report.auth == "authenticated" and report.count < 1)
        or (report.auth == "unauthenticated" and report.count ~= 0)
      then
        return nil, "managed OpenCode authentication report is invalid"
      end
      return report.auth
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
    profile_token = function()
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
    if paths.opencode_profile ~= nil then
      return nil, "OpenCode profile references are not valid for this backend"
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

  function services.validate_opencode_paths(paths)
    if type(deps.opencode_paths) ~= "function" then
      return true
    end
    local ok, expected = pcall(deps.opencode_paths)
    if not ok or not expected then
      return nil, "managed OpenCode source path validation failed"
    end
    for _, field in ipairs({
      "python",
      "profile_helper",
      "home_agents",
      "global_opencode_data",
    }) do
      local actual, actual_error = canonical_path(paths[field], "OpenCode " .. field, false)
      if not actual or actual ~= expected[field] then
        return nil, actual_error or "managed OpenCode source path changed"
      end
    end
    return true
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

    local auth_result = probe(executable, deps.auth, name, executable)
    local auth = "unknown"
    local health_error = ""
    local parsed_auth = auth_result and parse_auth(name, auth_result) or "unknown"
    if parsed_auth == "unauthenticated" then
      auth = "unauthenticated"
    elseif auth_result and auth_result.code == 0 and parsed_auth == "authenticated" then
      auth = "authenticated"
    else
      health_error = auth_diagnostic(name, auth_result)
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
  auth_arguments = auth_arguments,
  invoke_profile_helper = invoke_profile_helper,
  new = new,
  opencode_compatibility = opencode_compatibility,
  read_only_probe = read_only_probe,
  reset_opencode_compatibility_cache = function()
    OPENCODE_COMPATIBILITY_CACHE = {}
  end,
  uuid = uuid_v4,
}

return M
