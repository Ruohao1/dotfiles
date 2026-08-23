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

eq(registry_module.names(), { "codex", "claude", "opencode" }, "backend order")

local OPENCODE_PERMISSION =
  '{"*":"ask","read":"allow","edit":"allow","glob":"allow","grep":"allow","list":"allow","lsp":"allow","question":"allow","todowrite":"allow"}'

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
  global_opencode_config = "/home/user/.config/opencode",
  global_opencode_data = "/home/user/.local/share/opencode",
  grants = {},
}

local directories = {
  ["/home/user/.codex"] = true,
  ["/home/user/.claude"] = true,
  ["/home/user/.config/opencode"] = true,
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
  ["/home/user/.local/share/opencode/mcp-auth.json"] = true,
  ["/home/user/.local/share/opencode/account.json"] = true,
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
local calls = { executable = {}, revalidate = {}, version = {}, auth = {}, help = {} }
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
    return { code = 0, signal = 0, stdout = name .. " 1.0\n", stderr = "" }
  end,
  auth = function(name, executable)
    table.insert(calls.auth, { name, executable })
    local output = {
      codex = "Logged in using ChatGPT\n",
      claude = '{"loggedIn":true}\n',
      opencode = "1 credentials\n",
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
  "serve",
  "--hostname",
  "127.0.0.1",
  "--port",
  "43123",
}, "OpenCode server")
eq(opencode_launch.attach_argv, {
  "/usr/bin/opencode",
  "attach",
  "http://127.0.0.1:43123",
  "--dir",
  "/work/repo",
}, "OpenCode attach")
eq(opencode_launch.env, {
  OPENCODE_DISABLE_AUTOUPDATE = "true",
  OPENCODE_DISABLE_LSP_DOWNLOAD = "true",
  OPENCODE_PERMISSION = OPENCODE_PERMISSION,
  OPENCODE_SERVER_PASSWORD = "0123456789abcdef0123456789abcdef",
  OPENCODE_SERVER_USERNAME = "opencode",
  XDG_CACHE_HOME = "/state/identity/backends/opencode/xdg-cache",
  XDG_DATA_HOME = "/state/identity/backends/opencode/xdg-data",
}, "OpenCode isolated environment")
eq(opencode_launch.session, "", "OpenCode starts without a guessed session")
eq(opencode_launch.capabilities, {
  approval = true,
  busy = true,
  completion = true,
  exact_session = true,
}, "OpenCode capabilities")
eq(opencode_launch.read_only_inputs, {
  {
    source = "/home/user/.local/share/opencode/account.json",
    destination = "/state/identity/backends/opencode/xdg-data/opencode/account.json",
    kind = "file",
  },
  {
    source = "/home/user/.local/share/opencode/auth.json",
    destination = "/state/identity/backends/opencode/xdg-data/opencode/auth.json",
    kind = "file",
  },
  {
    source = "/home/user/.local/share/opencode/mcp-auth.json",
    destination = "/state/identity/backends/opencode/xdg-data/opencode/mcp-auth.json",
    kind = "file",
  },
}, "OpenCode read-only authentication")
eq(opencode_launch.protected_paths, {
  "/home/user/.config/opencode",
  "/home/user/.local/share/opencode",
  "/usr/bin/opencode",
}, "OpenCode protected paths")
local opencode_resume = assert(opencode:resume_session(identity, paths, "ses_test123"))
eq(opencode_resume.attach_argv, {
  "/usr/bin/opencode",
  "attach",
  "http://127.0.0.1:43123",
  "--dir",
  "/work/repo",
  "--session",
  "ses_test123",
}, "OpenCode exact resume")
eq(opencode_resume.env.OPENCODE_PERMISSION, OPENCODE_PERMISSION, "OpenCode resume permission")
eq(opencode_resume.env.OPENCODE_DISABLE_AUTOUPDATE, "true", "OpenCode resume update policy")
eq(opencode_resume.env.OPENCODE_DISABLE_LSP_DOWNLOAD, "true", "OpenCode resume LSP download policy")
local invalid_opencode, invalid_opencode_error =
  opencode:resume_session(identity, paths, "../foreign")
eq(invalid_opencode, nil, "OpenCode rejects invalid session")
contains(invalid_opencode_error, "session", "OpenCode session error")

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
  OPENCODE_PERMISSION,
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
  { "opencode", "/usr/bin/opencode", { "--help" } },
  { "opencode", "/usr/bin/opencode", { "serve", "--help" } },
  { "opencode", "/usr/bin/opencode", { "attach", "--help" } },
}, "exact compatibility help probes")
eq(registry_module._test.auth_arguments("codex"), { "login", "status" }, "Codex auth argv")
eq(
  registry_module._test.auth_arguments("claude"),
  { "auth", "status", "--json" },
  "Claude auth argv"
)
eq(registry_module._test.auth_arguments("opencode"), { "auth", "list" }, "OpenCode auth argv")
local changed_auth_arguments = assert(registry_module._test.auth_arguments("opencode"))
changed_auth_arguments[1] = "changed"
eq(registry_module._test.auth_arguments("opencode"), { "auth", "list" }, "fresh auth argv")

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
  {
    "opencode",
    { code = 1, signal = 0, stdout = "No credentials found\n", stderr = "" },
    "unauthenticated",
    "OpenCode explicit empty state on failure",
  },
  {
    "opencode",
    { code = 1, signal = 0, stdout = "", stderr = "No credentials found\n" },
    "unauthenticated",
    "OpenCode explicit empty state on stderr",
  },
  {
    "opencode",
    { code = 0, signal = 0, stdout = "0 credentials\n", stderr = "" },
    "unauthenticated",
    "OpenCode zero credential footer",
  },
  {
    "opencode",
    { code = 0, signal = 0, stdout = "0 credential\n", stderr = "" },
    "unauthenticated",
    "OpenCode singular zero credential footer",
  },
  {
    "opencode",
    { code = 0, signal = 0, stdout = "1 credential\n", stderr = "" },
    "authenticated",
    "OpenCode singular positive credential footer",
  },
  {
    "opencode",
    { code = 0, signal = 0, stdout = "", stderr = "1 credentials\n" },
    "unknown",
    "OpenCode ignores positive footer on stderr",
  },
  {
    "opencode",
    {
      code = 0,
      signal = 0,
      stdout = "private-provider-name oauth\n\27[90m└\27[0m 1 credentials\n",
      stderr = "",
    },
    "authenticated",
    "OpenCode positive credential footer",
  },
  {
    "opencode",
    { code = 0, signal = 0, stdout = "Provider catalog loaded\n", stderr = "" },
    "unknown",
    "OpenCode ambiguous success",
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

local private_failure = health_with_auth("opencode", {
  code = 2,
  signal = 0,
  stdout = "",
  stderr = "credential-secret-sentinel",
})
eq(private_failure.auth, "unknown", "OpenCode failed probe is unknown")
assert(#private_failure.error > 0 and #private_failure.error <= 256, "bounded auth diagnostic")
assert(
  not vim.inspect(private_failure):find("credential-secret-sentinel", 1, true),
  "auth diagnostic leaks credential detail"
)

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
