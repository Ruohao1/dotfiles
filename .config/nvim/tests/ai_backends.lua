local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local function contains(value, needle, label)
  assert(
    tostring(value):find(needle, 1, true),
    string.format("%s\nexpected text containing: %s\nactual: %s", label, needle, tostring(value))
  )
end

local registry_module = require("ai.backends")
local managed = require("ai.backends.opencode_managed")

eq(registry_module.names(), { "codex", "claude", "opencode" }, "backend order")

local identity = {
  key = string.rep("a", 32),
  root = "/work/repo",
  inside_git = true,
  git_dir = "/git/worktrees/repo",
  git_common_dir = "/git",
  git_entry = "/work/repo/.git",
  owner_pane = "%12",
  tmux_socket = "/tmp/tmux/default",
  namespace = "tmux:/tmp/tmux/default:41:9001",
}
local paths = {
  state = "/state/identity",
  backend_state = "/state/identity/backends/codex",
  event_file = "/run/identity/events.ndjson",
  event_helper = "/config/nvim/scripts/nvim-ai-event.py",
  python = "/usr/bin/python3",
  global_codex_home = "/home/user/.codex",
  global_claude_config = "/home/user/.claude",
  global_claude_home_file = "/home/user/.claude.json",
  global_opencode_data = "/home/user/.local/share/opencode",
  home_agents = "/home/user/AGENTS.md",
  profile_helper = "/config/nvim/scripts/nvim-ai-opencode-profile.py",
  grants = {},
}

local directories = {
  ["/home/user/.codex"] = true,
  ["/home/user/.claude"] = true,
  ["/home/user"] = true,
  ["/home/user/.local/share/opencode"] = true,
}
local files = {
  ["/usr/bin/codex"] = true,
  ["/usr/bin/claude"] = true,
  ["/usr/bin/opencode"] = true,
  ["/home/user/.codex/auth.json"] = true,
  ["/home/user/.codex/config.toml"] = true,
  ["/home/user/.claude/settings.json"] = true,
  ["/home/user/.claude.json"] = true,
  ["/home/user/.local/share/opencode/auth.json"] = true,
  ["/config/nvim/scripts/nvim-ai-opencode-profile.py"] = true,
  ["/usr/bin/python3"] = true,
}
local help_text = {
  codex = {
    ["--help"] = "-C --sandbox --ask-for-approval --add-dir",
    ["resume\0--help"] = "--last -C --sandbox --ask-for-approval --add-dir",
  },
  claude = {
    ["--help"] = "--session-id --resume --permission-mode --add-dir",
  },
  opencode = {
    ["--help"] = "serve attach",
    ["serve\0--help"] = "--hostname --port OPENCODE_SERVER_PASSWORD",
    ["attach\0--help"] = "--dir --session",
  },
}
local profile_token = string.rep("b", 32)
local profile_fingerprint = string.rep("c", 64)
local prepared_profile = {
  schema = 1,
  version = "1.18.18",
  profile_root = "/state/identity/backends/opencode/profiles/" .. profile_token,
  fingerprint = profile_fingerprint,
  config_source = "/state/identity/backends/opencode/profiles/" .. profile_token .. "/xdg-config",
  auth_source = "/state/identity/backends/opencode/profiles/"
    .. profile_token
    .. "/credentials/auth.json",
  home_mask_source = "/state/identity/backends/opencode/profiles/"
    .. profile_token
    .. "/empty-home-opencode",
  auth = "authenticated",
  credential_count = 1,
}
local compatibility_report = managed._test.compatibility_fixture()
local calls = {
  executable = {},
  revalidate = {},
  version = {},
  auth = {},
  help = {},
  compatibility = {},
  inspect_auth = {},
  prepare = {},
  inspect_profile = {},
}
local registry = registry_module._test.new({
  executable = function(name)
    table.insert(calls.executable, name)
    return "/usr/bin/" .. name
  end,
  revalidate = function(executable)
    table.insert(calls.revalidate, executable)
    return true
  end,
  version = function(name, executable)
    table.insert(calls.version, { name, executable })
    local output = name == "opencode" and "1.18.18\n" or name .. " 1.0\n"
    return { code = 0, signal = 0, stdout = output, stderr = "" }
  end,
  auth = function(name, executable)
    table.insert(calls.auth, { name, executable })
    assert(name ~= "opencode", "OpenCode must never invoke auth list")
    local output = {
      codex = "Logged in using ChatGPT\n",
      claude = '{"loggedIn":true}\n',
    }
    return { code = 0, signal = 0, stdout = assert(output[name]), stderr = "" }
  end,
  help = function(name, executable, arguments)
    table.insert(calls.help, { name, executable, vim.deepcopy(arguments) })
    return {
      code = 0,
      signal = 0,
      stdout = assert(help_text[name][table.concat(arguments, "\0")]),
      stderr = "",
    }
  end,
  uuid = function()
    return "11111111-1111-4111-8111-111111111111"
  end,
  port = function()
    return 43123
  end,
  password = function()
    return "0123456789abcdef0123456789abcdef"
  end,
  profile_token = function()
    return profile_token
  end,
  prepare_opencode_profile = function(request)
    calls.prepare[#calls.prepare + 1] = vim.deepcopy(request)
    return vim.deepcopy(prepared_profile)
  end,
  inspect_opencode_profile = function(request)
    calls.inspect_profile[#calls.inspect_profile + 1] = vim.deepcopy(request)
    return vim.deepcopy(prepared_profile)
  end,
  inspect_opencode_auth = function(path)
    calls.inspect_auth[#calls.inspect_auth + 1] = path
    return "authenticated"
  end,
  opencode_auth_path = function()
    return "/home/user/.local/share/opencode/auth.json"
  end,
  opencode_compatibility = function(executable)
    calls.compatibility[#calls.compatibility + 1] = executable
    return vim.deepcopy(compatibility_report)
  end,
  stat = function(path)
    if directories[path] then
      return { type = "directory", mode = 448, uid = 1000 }
    end
    if files[path] then
      return {
        type = "file",
        mode = path:match("^/usr/bin/") and 493 or 384,
        uid = path:match("^/usr/bin/") and 0 or 1000,
      }
    end
    return nil
  end,
  uid = function()
    return 1000
  end,
})

eq(calls.executable, {}, "registry construction is lazy")
eq(registry:names(), { "codex", "claude", "opencode" }, "injected backend order")
eq(registry:get("missing"), nil, "unknown backend lookup")

local codex = assert(registry:get("codex"))
eq(codex:new_session(identity, paths), {
  kind = "direct",
  backend = "codex",
  argv = {
    "/usr/bin/codex",
    "-C",
    "/work/repo",
    "--sandbox",
    "workspace-write",
    "--ask-for-approval",
    "on-request",
  },
  env = { CODEX_HOME = "/state/identity/backends/codex" },
  session = "last",
  capabilities = { approval = false, busy = false, completion = false, exact_session = false },
  read_only_inputs = {
    {
      source = "/home/user/.codex/auth.json",
      destination = "/state/identity/backends/codex/auth.json",
      kind = "file",
    },
    {
      source = "/home/user/.codex/config.toml",
      destination = "/state/identity/backends/codex/config.toml",
      kind = "file",
    },
  },
  protected_paths = { "/home/user/.codex", "/usr/bin/codex" },
}, "Codex new session")

eq(codex:resume_session(identity, paths, "last").argv, {
  "/usr/bin/codex",
  "resume",
  "--last",
  "-C",
  "/work/repo",
  "--sandbox",
  "workspace-write",
  "--ask-for-approval",
  "on-request",
}, "Codex isolated resume")
local invalid_codex, invalid_codex_error = codex:resume_session(identity, paths, "other")
eq(invalid_codex, nil, "Codex rejects an ambiguous session")
contains(invalid_codex_error, "session", "Codex session error")

paths.backend_state = "/state/identity/backends/claude"
local claude = assert(registry:get("claude"))
local claude_launch = assert(claude:new_session(identity, paths))
eq(claude_launch.session, "11111111-1111-4111-8111-111111111111", "Claude UUID")
eq(claude_launch.argv, {
  "/usr/bin/claude",
  "--session-id",
  "11111111-1111-4111-8111-111111111111",
  "--permission-mode",
  "acceptEdits",
}, "Claude new session")
eq(claude_launch.env, {
  CLAUDE_CODE_ADDITIONAL_SETTINGS = "/state/identity/backends/claude/additional-settings.json",
  CLAUDE_CONFIG_DIR = "/state/identity/backends/claude",
}, "Claude isolated config")
eq(claude_launch.capabilities, {
  approval = true,
  busy = true,
  completion = true,
  exact_session = true,
}, "Claude capabilities")
eq(claude_launch.read_only_inputs, {
  {
    source = "/home/user/.claude/settings.json",
    destination = "/state/identity/backends/claude/settings.json",
    kind = "file",
  },
}, "Claude read-only settings")
eq(claude_launch.protected_paths, {
  "/home/user/.claude",
  "/home/user/.claude.json",
  "/usr/bin/claude",
}, "Claude protected paths")
eq(claude:resume_session(identity, paths, claude_launch.session).argv, {
  "/usr/bin/claude",
  "--resume",
  "11111111-1111-4111-8111-111111111111",
  "--permission-mode",
  "acceptEdits",
}, "Claude resume")
local invalid_claude, invalid_claude_error = claude:resume_session(identity, paths, "not-a-uuid")
eq(invalid_claude, nil, "Claude rejects invalid UUID")
contains(invalid_claude_error, "session", "Claude session error")

paths.backend_state = "/state/identity/backends/opencode"
local opencode = assert(registry:get("opencode"))
local opencode_launch = assert(opencode:new_session(identity, paths))
eq(opencode_launch.kind, "server_attach", "OpenCode launch kind")
eq(opencode_launch.server_argv, {
  "/usr/bin/opencode",
  "--pure",
  "serve",
  "--hostname",
  "127.0.0.1",
  "--port",
  "43123",
}, "OpenCode server")
eq(opencode_launch.attach_argv, {
  "/usr/bin/opencode",
  "--pure",
  "attach",
  "http://127.0.0.1:43123",
  "--dir",
  "/work/repo",
}, "OpenCode attach")
eq(opencode_launch.env, {
  OPENCODE_DISABLE_AUTOUPDATE = "true",
  OPENCODE_DISABLE_CLAUDE_CODE = "true",
  OPENCODE_DISABLE_EXTERNAL_SKILLS = "true",
  OPENCODE_DISABLE_LSP_DOWNLOAD = "true",
  OPENCODE_DISABLE_PROJECT_CONFIG = "true",
  OPENCODE_PERMISSION = managed.policy_json(),
  OPENCODE_PURE = "true",
  OPENCODE_SERVER_PASSWORD = "0123456789abcdef0123456789abcdef",
  OPENCODE_SERVER_USERNAME = "opencode",
  XDG_CACHE_HOME = "/state/identity/backends/opencode/xdg-cache",
  XDG_CONFIG_HOME = "/state/identity/backends/opencode/xdg-config",
  XDG_DATA_HOME = "/state/identity/backends/opencode/xdg-data",
  XDG_STATE_HOME = "/state/identity/backends/opencode/xdg-state",
}, "OpenCode isolated environment")
eq(opencode_launch.session, "", "OpenCode starts without a guessed session")
eq(opencode_launch.capabilities, {
  approval = true,
  busy = true,
  completion = true,
  exact_session = true,
}, "OpenCode capabilities")
eq(opencode_launch.read_only_inputs, {}, "raw global OpenCode inputs excluded")
eq(opencode_launch.protected_paths, {
  prepared_profile.profile_root,
  "/usr/bin/opencode",
}, "OpenCode protected paths")
eq(opencode_launch.managed_profile, {
  schema = 1,
  version = "1.18.18",
  profile_root = prepared_profile.profile_root,
  fingerprint = profile_fingerprint,
  config_source = prepared_profile.config_source,
  auth_source = prepared_profile.auth_source,
  home_mask_source = prepared_profile.home_mask_source,
}, "OpenCode launch strips helper-private profile fields")
eq(calls.prepare, {
  {
    schema = 1,
    token = profile_token,
    identity_key = identity.key,
    root = identity.root,
    backend_state = paths.backend_state,
    global_auth = paths.global_opencode_data .. "/auth.json",
    user_agents = paths.home_agents,
    repo_agents = identity.root .. "/AGENTS.md",
    version = "1.18.18",
    config_json = managed.config_json(),
    policy_json = managed.policy_json(),
  },
}, "OpenCode helper receives the exact approved prepare request")

local resume_paths = vim.deepcopy(paths)
resume_paths.opencode_profile = {
  token = profile_token,
  fingerprint = profile_fingerprint,
  version = "1.18.18",
}
local opencode_resume = assert(opencode:resume_session(identity, resume_paths, "ses_test123"))
eq(opencode_resume.attach_argv, {
  "/usr/bin/opencode",
  "--pure",
  "attach",
  "http://127.0.0.1:43123",
  "--dir",
  "/work/repo",
  "--session",
  "ses_test123",
}, "OpenCode exact resume")
eq(
  opencode_resume.managed_profile.profile_root,
  opencode_launch.managed_profile.profile_root,
  "OpenCode resume reuses profile"
)
eq(#calls.prepare, 1, "OpenCode reuse does not prepare a replacement profile")
eq(calls.inspect_profile, {
  {
    schema = 1,
    backend_state = paths.backend_state,
    token = profile_token,
    identity_key = identity.key,
    root = identity.root,
    version = "1.18.18",
    fingerprint = profile_fingerprint,
  },
}, "OpenCode reuse inspects only the exact nonsecret reference")
eq(opencode_resume.env.OPENCODE_PERMISSION, managed.policy_json(), "OpenCode resume permission")
eq(opencode_resume.env.OPENCODE_DISABLE_AUTOUPDATE, "true", "OpenCode resume update policy")
eq(opencode_resume.env.OPENCODE_DISABLE_LSP_DOWNLOAD, "true", "OpenCode resume LSP download policy")
eq(
  assert(opencode:profile_reference(opencode_launch)),
  resume_paths.opencode_profile,
  "OpenCode profile reference"
)
eq(
  assert(opencode:validate_profile(resume_paths.opencode_profile, identity, paths)),
  opencode_launch.managed_profile,
  "OpenCode profile reference validation"
)
eq(#calls.prepare, 1, "profile validation never prepares a replacement")
local invalid_opencode, invalid_opencode_error =
  opencode:resume_session(identity, paths, "../foreign")
eq(invalid_opencode, nil, "OpenCode rejects invalid session")
contains(invalid_opencode_error, "session", "OpenCode session error")

local bad_reference_paths = vim.deepcopy(resume_paths)
bad_reference_paths.opencode_profile.fingerprint = string.rep("d", 64)
local prepare_before_bad_reference = #calls.prepare
local invalid_reference, invalid_reference_error =
  opencode:resume_session(identity, bad_reference_paths, "ses_test123")
eq(invalid_reference, nil, "invalid managed profile reference fails closed")
contains(invalid_reference_error, "profile", "invalid profile reference diagnostic")
eq(#calls.prepare, prepare_before_bad_reference, "invalid reference has no fresh-profile fallback")

local foreign_profile_paths = vim.deepcopy(paths)
foreign_profile_paths.opencode_profile = resume_paths.opencode_profile
local foreign_codex = codex:new_session(identity, foreign_profile_paths)
eq(foreign_codex, nil, "Codex rejects an OpenCode profile reference")
local foreign_claude = claude:new_session(identity, foreign_profile_paths)
eq(foreign_claude, nil, "Claude rejects an OpenCode profile reference")

eq(
  codex:format_context({ kind = "location", path = "lua/main.lua", line = 7, column = 3 }),
  "Regarding lua/main.lua:7:3: ",
  "Codex location context"
)
eq(
  claude:format_context({
    kind = "selection",
    path = "lua/main.lua",
    first = 7,
    last = 9,
    context_file = "/run/context/abc.txt",
  }),
  "Use the exact selection from lua/main.lua:7-9 stored at /run/context/abc.txt: ",
  "Claude selection context"
)

eq(codex:suspend(), { signal = 1, timeout = 2000 }, "suspend policy")
eq(codex:stop(), { signal = 15, timeout = 2000 }, "stop policy")
eq(claude:session_reference(claude_launch), claude_launch.session, "Claude session reference")
eq(opencode:session_reference(opencode_launch), "", "OpenCode empty session reference")

paths.backend_state = "/state/identity/backends/codex"
paths.grants = { "/extra/a", "/extra/b" }
local granted = assert(codex:new_session(identity, paths))
eq(vim.list_slice(granted.argv, #granted.argv - 3), {
  "--add-dir",
  "/extra/a",
  "--add-dir",
  "/extra/b",
}, "sorted Codex grants")
paths.grants = { "/extra/b", "/extra/a" }
local unsorted, unsorted_error = codex:new_session(identity, paths)
eq(unsorted, nil, "unsorted grants refused")
contains(unsorted_error, "sorted", "unsorted grant error")
paths.grants = {}

local first_capabilities = codex:capabilities()
first_capabilities.approval = true
eq(codex:capabilities().approval, false, "capabilities are fresh")
local first_launch = assert(codex:new_session(identity, paths))
first_launch.argv[1] = "/changed"
eq(assert(codex:new_session(identity, paths)).argv[1], "/usr/bin/codex", "launch tables are fresh")
local opencode_paths = vim.deepcopy(paths)
opencode_paths.backend_state = "/state/identity/backends/opencode"
local first_opencode_launch = assert(opencode:new_session(identity, opencode_paths))
first_opencode_launch.env.OPENCODE_PERMISSION = "changed"
local fresh_opencode_launch = assert(opencode:new_session(identity, opencode_paths))
eq(
  fresh_opencode_launch.env.OPENCODE_PERMISSION,
  managed.policy_json(),
  "OpenCode permission tables are fresh"
)

local before_health_revalidations = #calls.revalidate
for _, name in ipairs(registry_module.names()) do
  local health = registry:health(name)
  eq(health.installed, true, name .. " installed")
  eq(health.executable, "/usr/bin/" .. name, name .. " executable")
  assert(type(health.version) == "string" and health.version ~= "", name .. " version")
  eq(health.auth, "authenticated", name .. " authentication")
  assert(type(health.capabilities) == "table", name .. " capabilities")
  eq(health.error, "", name .. " health error")
end
assert(#calls.revalidate > before_health_revalidations, "health revalidates executables")
eq(calls.help, {
  { "codex", "/usr/bin/codex", { "--help" } },
  { "codex", "/usr/bin/codex", { "resume", "--help" } },
  { "claude", "/usr/bin/claude", { "--help" } },
}, "exact compatibility help probes")
eq(calls.compatibility, { "/usr/bin/opencode" }, "OpenCode uses the semantic compatibility probe")
eq(
  calls.inspect_auth,
  { "/home/user/.local/share/opencode/auth.json" },
  "OpenCode health inspects only the approved global auth file"
)
eq(registry_module._test.auth_arguments("codex"), { "login", "status" }, "Codex auth argv")
eq(
  registry_module._test.auth_arguments("claude"),
  { "auth", "status", "--json" },
  "Claude auth argv"
)
eq(registry_module._test.auth_arguments("opencode"), nil, "OpenCode has no auth-list argv")
for _, call in ipairs(calls.auth) do
  assert(call[1] ~= "opencode", "OpenCode invoked auth list")
end

local function health_with_auth(name, result)
  local fixture = registry_module._test.new({
    executable = function(requested)
      return "/usr/bin/" .. requested
    end,
    revalidate = function()
      return true
    end,
    version = function(requested)
      return { code = 0, signal = 0, stdout = requested .. " 1.0\n", stderr = "" }
    end,
    auth = function(requested)
      eq(requested, name, "authentication parser backend")
      return vim.deepcopy(result)
    end,
    help = function(requested, _, arguments)
      return {
        code = 0,
        signal = 0,
        stdout = assert(help_text[requested][table.concat(arguments, "\0")]),
        stderr = "",
      }
    end,
    stat = function(path)
      return files[path] and { type = "file", mode = 493, uid = 0 } or nil
    end,
    uid = function()
      return 1000
    end,
  })
  return fixture:health(name)
end

local auth_cases = {
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using ChatGPT\n", stderr = "" },
    "authenticated",
    "Codex explicit login",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "", stderr = "Logged in using ChatGPT\n" },
    "unknown",
    "Codex ignores positive marker on stderr",
  },
  {
    "codex",
    {
      code = 0,
      signal = 0,
      stdout = "Logged in using an API key - redacted-key-sentinel\n",
      stderr = "",
    },
    "authenticated",
    "Codex API key login",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using workload identity\n", stderr = "" },
    "authenticated",
    "Codex workload identity login",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using access token\n", stderr = "" },
    "authenticated",
    "Codex access token login",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using personal access token\n", stderr = "" },
    "authenticated",
    "Codex personal access token login",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using Amazon Bedrock API key\n", stderr = "" },
    "authenticated",
    "Codex Bedrock login",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using Agent Identity\n", stderr = "" },
    "authenticated",
    "Codex legacy agent identity login",
  },
  {
    "codex",
    { code = 1, signal = 0, stdout = "Not logged in\n", stderr = "" },
    "unauthenticated",
    "Codex explicit logout on failure",
  },
  {
    "codex",
    { code = 1, signal = 0, stdout = "", stderr = "Not logged in\n" },
    "unauthenticated",
    "Codex explicit logout on stderr",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Codex is ready\n", stderr = "" },
    "unknown",
    "Codex ambiguous success",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using surprise provider\n", stderr = "" },
    "unknown",
    "Codex arbitrary login suffix",
  },
  {
    "codex",
    { code = 0, signal = 0, stdout = "Logged in using ChatGPT extra\n", stderr = "" },
    "unknown",
    "Codex known login with extra suffix",
  },
  {
    "claude",
    { code = 0, signal = 0, stdout = '{"loggedIn":true}\n', stderr = "" },
    "authenticated",
    "Claude JSON login",
  },
  {
    "claude",
    { code = 1, signal = 0, stdout = '{"loggedIn":false}\n', stderr = "" },
    "unauthenticated",
    "Claude JSON logout on failure",
  },
  {
    "claude",
    { code = 1, signal = 0, stdout = "", stderr = '{"loggedIn":false}\n' },
    "unknown",
    "Claude ignores JSON-shaped stderr",
  },
  {
    "claude",
    { code = 0, signal = 0, stdout = '{"loggedIn":"yes"}\n', stderr = "" },
    "unknown",
    "Claude ambiguous JSON",
  },
  {
    "claude",
    { code = 0, signal = 0, stdout = "not json\n", stderr = "" },
    "unknown",
    "Claude malformed JSON",
  },
}
for _, case in ipairs(auth_cases) do
  local health = health_with_auth(case[1], case[2])
  eq(health.auth, case[3], case[4])
  assert(#health.error <= 256, case[4] .. " diagnostic exceeds byte cap")
  local serialized_health = vim.inspect(health)
  for _, private_text in ipairs({ "private-provider-name", "redacted-key-sentinel" }) do
    assert(
      not serialized_health:find(private_text, 1, true),
      case[4] .. " leaks authentication detail"
    )
  end
end

local function managed_health(overrides)
  local options = overrides or {}
  local order = {}
  local fixture = registry_module._test.new({
    executable = function(name)
      order[#order + 1] = "executable"
      return "/usr/bin/" .. name
    end,
    revalidate = function()
      order[#order + 1] = "revalidate"
      return true
    end,
    opencode_compatibility = function()
      order[#order + 1] = "compatibility"
      if options.compatibility_error then
        return nil, options.compatibility_error
      end
      return vim.deepcopy(options.compatibility or compatibility_report)
    end,
    opencode_auth_path = function()
      order[#order + 1] = "auth_path"
      return "/home/user/.local/share/opencode/auth.json"
    end,
    inspect_opencode_auth = function(path)
      order[#order + 1] = "inspect_auth"
      eq(path, "/home/user/.local/share/opencode/auth.json", "managed auth inspection path")
      if options.auth_exception then
        error(options.auth_exception)
      end
      return options.auth or "authenticated", options.auth_error
    end,
    stat = function(path)
      return path == "/usr/bin/opencode" and { type = "file", mode = 493, uid = 0 } or nil
    end,
    uid = function()
      return 1000
    end,
  })
  return fixture:health("opencode"), order
end

local healthy_opencode, healthy_order = managed_health()
eq(healthy_opencode.installed, true, "managed OpenCode is installed")
eq(healthy_opencode.version, "1.18.18", "managed OpenCode exact health version")
eq(healthy_opencode.auth, "authenticated", "managed OpenCode filtered authentication")
eq(healthy_opencode.capabilities, opencode:capabilities(), "managed OpenCode health capabilities")
eq(healthy_opencode.error, "", "managed OpenCode health succeeds")
eq(
  healthy_order,
  { "executable", "revalidate", "compatibility", "auth_path", "inspect_auth" },
  "managed OpenCode health ordering"
)

local health_failures = {
  {
    label = "unknown exact version",
    mutate = function(options)
      options.compatibility = vim.deepcopy(compatibility_report)
      options.compatibility.version = "1.18.19"
    end,
  },
  {
    label = "missing pure mode",
    mutate = function(options)
      options.compatibility = vim.deepcopy(compatibility_report)
      options.compatibility.help.root[1] = "--unsafe"
    end,
  },
  {
    label = "malformed agent report",
    mutate = function(options)
      options.compatibility = vim.deepcopy(compatibility_report)
      options.compatibility.agents.build = "malformed-agent-canary"
    end,
  },
  {
    label = "semantic helper failure",
    mutate = function(options)
      options.compatibility_error = "compatibility-secret-canary"
    end,
  },
  {
    label = "unauthenticated filtered credentials",
    mutate = function(options)
      options.auth = "unauthenticated"
    end,
  },
  {
    label = "authentication helper exception",
    mutate = function(options)
      options.auth_exception = "credential-secret-canary"
    end,
  },
  {
    label = "unknown authentication",
    mutate = function(options)
      options.auth = "unknown"
      options.auth_error = "credential-helper-private-canary"
    end,
  },
}
for _, case in ipairs(health_failures) do
  local options = {}
  case.mutate(options)
  local health = managed_health(options)
  eq(health.installed, true, case.label .. " remains detected")
  eq(health.capabilities, {}, case.label .. " disables capabilities")
  assert(type(health.error) == "string" and health.error ~= "", case.label .. " has no error")
  assert(#health.error <= 256, case.label .. " error is unbounded")
  local serialized = vim.inspect(health)
  for _, canary in ipairs({
    "malformed-agent-canary",
    "compatibility-secret-canary",
    "credential-secret-canary",
    "credential-helper-private-canary",
  }) do
    assert(not serialized:find(canary, 1, true), case.label .. " leaked private output")
  end
end

local absent_calls = 0
local absent = registry_module._test.new({
  executable = function()
    return nil, "not found"
  end,
  revalidate = function()
    absent_calls = absent_calls + 1
    return true
  end,
  version = function()
    absent_calls = absent_calls + 1
  end,
  auth = function()
    absent_calls = absent_calls + 1
  end,
  help = function()
    absent_calls = absent_calls + 1
  end,
  stat = function()
    return nil
  end,
  uid = function()
    return 1000
  end,
})
local absent_health = absent:health("codex")
eq(absent_health.installed, false, "absent executable")
eq(absent_calls, 0, "absent backend runs no probes")

for _, case in ipairs({
  {
    label = "signaled generic version probe",
    result = {
      code = 0,
      signal = 9,
      stdout = "codex 9.9 generic-signal-secret-canary\n",
      stderr = "",
    },
  },
  {
    label = "missing-signal generic version probe",
    result = {
      code = 0,
      stdout = "codex 9.9 generic-signal-secret-canary\n",
      stderr = "",
    },
  },
}) do
  local later_probe_calls = 0
  local signaled = registry_module._test.new({
    executable = function(name)
      return "/usr/bin/" .. name
    end,
    revalidate = function()
      return true
    end,
    version = function()
      return vim.deepcopy(case.result)
    end,
    auth = function()
      later_probe_calls = later_probe_calls + 1
      return { code = 0, signal = 0, stdout = "Logged in using ChatGPT\n", stderr = "" }
    end,
    help = function()
      later_probe_calls = later_probe_calls + 1
      return { code = 0, signal = 0, stdout = "", stderr = "" }
    end,
    stat = function(path)
      return files[path] and { type = "file", mode = 493, uid = 0 } or nil
    end,
    uid = function()
      return 1000
    end,
  })
  local health = signaled:health("codex")
  eq(health.version, "", case.label .. " is rejected")
  eq(health.auth, "unknown", case.label .. " skips authentication")
  eq(health.capabilities, {}, case.label .. " disables capabilities")
  eq(later_probe_calls, 0, case.label .. " skips later probes")
  assert(type(health.error) == "string" and health.error ~= "", case.label .. " is generic")
  assert(
    not vim.inspect(health):find("generic-signal-secret-canary", 1, true),
    case.label .. " leaked subprocess output"
  )
end

local incompatible = registry_module._test.new({
  executable = function(name)
    return "/usr/bin/" .. name
  end,
  revalidate = function()
    return true
  end,
  version = function()
    return { code = 0, signal = 0, stdout = "codex 1.0\n", stderr = "" }
  end,
  auth = function()
    error("authentication must not run for an incompatible CLI")
  end,
  help = function()
    return { code = 0, signal = 0, stdout = "--sandbox only", stderr = "" }
  end,
  stat = function(path)
    return files[path] and { type = "file", mode = 384, uid = 0 } or nil
  end,
  uid = function()
    return 1000
  end,
})
local incompatible_health = incompatible:health("codex")
eq(incompatible_health.installed, true, "incompatible CLI remains detected")
eq(incompatible_health.capabilities, {}, "incompatible CLI is disabled")
contains(incompatible_health.error, "incompatible", "incompatible health diagnostic")

local unsafe_paths = vim.deepcopy(paths)
unsafe_paths.global_codex_home = "/home/user/.unsafe-codex"
directories[unsafe_paths.global_codex_home] = true
files[unsafe_paths.global_codex_home .. "/auth.json"] = true
local original_stat = registry_module._test.new({
  executable = function(name)
    return "/usr/bin/" .. name
  end,
  revalidate = function()
    return true
  end,
  version = function()
    return { code = 0, signal = 0, stdout = "1", stderr = "" }
  end,
  auth = function()
    return { code = 0, signal = 0, stdout = "authenticated", stderr = "" }
  end,
  help = function()
    return { code = 0, signal = 0, stdout = "", stderr = "" }
  end,
  stat = function(path)
    if path == unsafe_paths.global_codex_home then
      return { type = "directory", mode = 511, uid = 1000 }
    end
    if files[path] then
      return { type = "file", mode = 384, uid = 1000 }
    end
    return nil
  end,
  uid = function()
    return 1000
  end,
})
local unsafe_launch, unsafe_error =
  assert(original_stat:get("codex")):new_session(identity, unsafe_paths)
eq(unsafe_launch, nil, "unsafe provider directory refused")
contains(unsafe_error, "unsafe mode", "unsafe provider directory diagnostic")

local uuid = registry_module._test.uuid(function(length)
  eq(length, 16, "UUID byte count")
  return string.char(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
end)
eq(uuid, "00010203-0405-4607-8809-0a0b0c0d0e0f", "deterministic RFC-4122 UUID")
assert(
  uuid:match(
    "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]%-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]%-4[0-9a-f][0-9a-f][0-9a-f]%-[89ab][0-9a-f][0-9a-f][0-9a-f]%-[0-9a-f]+$"
  ),
  "generated UUID is lowercase RFC-4122 version 4: " .. uuid
)

local probe_argv
local probe_options
local probe_revalidations = {}
local probe_result = registry_module._test.read_only_probe(
  "/usr/bin/codex",
  { "resume", "--help" },
  {
    resolve = function(name)
      eq(name, "bwrap", "probe resolves Bubblewrap")
      return "/usr/bin/bwrap"
    end,
    revalidate = function(path)
      assert(path == "/usr/bin/codex" or path == "/usr/bin/bwrap", "unexpected probe tool")
      probe_revalidations[#probe_revalidations + 1] = path
      return true
    end,
    environ = function()
      return {
        HOME = "/home/user",
        NVIM = "/run/nvim/socket",
        NVIM_LISTEN_ADDRESS = "/run/nvim/legacy",
        TMUX = "/tmp/tmux/default,1,2",
        TMUX_PANE = "%12",
      }
    end,
    run = function(argv, options)
      probe_argv = vim.deepcopy(argv)
      probe_options = vim.deepcopy(options)
      return { code = 0, signal = 0, stdout = "help", stderr = "" }
    end,
  }
)
eq(probe_result.code, 0, "read-only probe result")
eq(probe_argv, {
  "/usr/bin/bwrap",
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
  "/usr/bin/codex",
  "resume",
  "--help",
}, "read-only network-isolated probe argv")
eq(probe_options.clear_env, true, "probe clears inherited environment")
eq(probe_options.timeout, 2000, "probe timeout")
eq(probe_options.env, { HOME = "/home/user" }, "probe hides editor and tmux sockets")
eq(probe_revalidations, { "/usr/bin/codex", "/usr/bin/bwrap" }, "probe revalidates exact programs")

local unconfined_run = false
local missing_bwrap = registry_module._test.read_only_probe("/usr/bin/codex", { "--version" }, {
  resolve = function()
    return nil, "Bubblewrap missing"
  end,
  revalidate = function()
    return true
  end,
  environ = function()
    return {}
  end,
  run = function()
    unconfined_run = true
  end,
})
eq(missing_bwrap.code, 127, "missing Bubblewrap fails health probe")
eq(unconfined_run, false, "missing Bubblewrap never retries unconfined")

print("AI backend adapter assertions: ok")
