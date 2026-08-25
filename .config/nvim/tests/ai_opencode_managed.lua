local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local function rejected(call, label)
  local value, err = call()
  assert(value == nil, label .. " was accepted")
  assert(type(err) == "string" and err ~= "", label .. " returned no diagnostic")
  assert(#err <= 256, label .. " returned an unbounded diagnostic")
end

local managed = require("ai.backends.opencode_managed")
local registry_module = require("ai.backends")

local expected_policy = {
  bash = "ask",
  doom_loop = "ask",
  external_directory = "ask",
  skill = "deny",
  task = "deny",
  webfetch = "ask",
  websearch = "ask",
}
local expected_config_json =
  '{"$schema":"https://opencode.ai/config.json","autoupdate":false,"permission":{"bash":"ask","doom_loop":"ask","external_directory":"ask","skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"},"agent":{"general":{"disable":true},"explore":{"disable":true},"compaction":{"permission":{"*":"deny"}},"summary":{"permission":{"*":"deny"}},"title":{"permission":{"*":"deny"}}}}'

eq(managed.version(), "1.18.18", "audited OpenCode version")
eq(managed.policy(), expected_policy, "managed permission policy")
assert(managed.policy()["*"] == nil, "no wildcard permission")
assert(managed.policy().read == nil, "native read permission preserved")
assert(managed.policy().edit == nil, "native edit permission preserved")
eq(
  managed.policy_json(),
  '{"bash":"ask","doom_loop":"ask","external_directory":"ask","skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"}',
  "canonical managed permission policy"
)

local config = managed.config()
eq(config.autoupdate, false, "configuration also disables updates")
eq(config.permission, managed.policy(), "file and environment policies agree")
eq(managed.config_json(), expected_config_json, "canonical managed configuration")
eq(vim.json.decode(managed.config_json()), config, "table and JSON configurations agree")
eq(config.agent.general, { disable = true }, "general subagent disabled")
eq(config.agent.explore, { disable = true }, "explore subagent disabled")
for _, name in ipairs({ "compaction", "summary", "title" }) do
  eq(config.agent[name], { permission = { ["*"] = "deny" } }, name .. " remains tool-denied")
end
assert(
  config.agent.build == nil and config.agent.plan == nil,
  "native Build and Plan are not replaced"
)

local immutable_cases = {
  {
    label = "changed policy key",
    mutate = function()
      local value = managed.policy()
      value.bash = "allow"
      value.provider = "allow"
    end,
    fresh = managed.policy,
    expected = expected_policy,
  },
  {
    label = "changed configuration key",
    mutate = function()
      local value = managed.config()
      value.autoupdate = true
      value.agent.build = { disable = true }
    end,
    fresh = managed.config,
    expected = config,
  },
}
for _, case in ipairs(immutable_cases) do
  case.mutate()
  eq(case.fresh(), case.expected, case.label .. " did not alter the managed contract")
end

local identity = {
  key = string.rep("a", 32),
  root = "/work/repo",
}
local paths = {
  backend_state = "/state/identity/backends/opencode",
  global_opencode_data = "/home/user/.local/share/opencode",
  home_agents = "/home/user/AGENTS.md",
  profile_helper = "/config/nvim/scripts/nvim-ai-opencode-profile.py",
  python = "/usr/bin/python3",
}
local token = string.rep("b", 32)
local request = assert(managed.profile_request(identity, paths, token))
eq(request, {
  schema = 1,
  token = token,
  identity_key = identity.key,
  root = identity.root,
  backend_state = paths.backend_state,
  global_auth = "/home/user/.local/share/opencode/auth.json",
  user_agents = paths.home_agents,
  repo_agents = "/work/repo/AGENTS.md",
  version = "1.18.18",
  config_json = expected_config_json,
  policy_json = managed.policy_json(),
}, "exact managed profile request")
eq(request.global_auth, "/home/user/.local/share/opencode/auth.json", "auth-only source")
eq(request.user_agents, "/home/user/AGENTS.md", "global instruction source")
eq(request.repo_agents, "/work/repo/AGENTS.md", "repository instruction source")
assert(vim.inspect(request):find("account.json", 1, true) == nil, "account data excluded")
assert(vim.inspect(request):find("mcp-auth.json", 1, true) == nil, "MCP auth excluded")

local invalid_request_cases = {
  {
    label = "wrong identity key",
    change = function(changed_identity)
      changed_identity.key = string.rep("A", 32)
    end,
  },
  {
    label = "noncanonical root",
    change = function(changed_identity)
      changed_identity.root = "/work/../work/repo"
    end,
  },
  {
    label = "control-bearing root",
    change = function(changed_identity)
      changed_identity.root = "/work/repo\nchanged"
    end,
  },
}
for _, case in ipairs(invalid_request_cases) do
  local changed_identity = vim.deepcopy(identity)
  case.change(changed_identity)
  rejected(function()
    return managed.profile_request(changed_identity, paths, token)
  end, case.label)
end

for _, field in ipairs({
  "backend_state",
  "global_opencode_data",
  "home_agents",
  "profile_helper",
  "python",
}) do
  local changed_paths = vim.deepcopy(paths)
  changed_paths[field] = changed_paths[field] .. "/../escape"
  rejected(function()
    return managed.profile_request(identity, changed_paths, token)
  end, "noncanonical " .. field)
end
rejected(function()
  return managed.profile_request(identity, paths, string.rep("B", 32))
end, "changed token")

local managed_profile = {
  schema = 1,
  version = "1.18.18",
  profile_root = "/state/identity/backends/opencode/profiles/" .. token,
  fingerprint = string.rep("c", 64),
}
eq(assert(managed.profile_reference(managed_profile)), {
  token = token,
  fingerprint = string.rep("c", 64),
  version = "1.18.18",
}, "bounded durable profile reference")

local password = "0123456789abcdef0123456789abcdef"
eq(assert(managed.environment(managed_profile, password)), {
  OPENCODE_DISABLE_AUTOUPDATE = "true",
  OPENCODE_DISABLE_CLAUDE_CODE = "true",
  OPENCODE_DISABLE_EXTERNAL_SKILLS = "true",
  OPENCODE_DISABLE_LSP_DOWNLOAD = "true",
  OPENCODE_DISABLE_PROJECT_CONFIG = "true",
  OPENCODE_PERMISSION = managed.policy_json(),
  OPENCODE_PURE = "true",
  OPENCODE_SERVER_PASSWORD = password,
  OPENCODE_SERVER_USERNAME = "opencode",
  XDG_CACHE_HOME = "/state/identity/backends/opencode/xdg-cache",
  XDG_CONFIG_HOME = "/state/identity/backends/opencode/xdg-config",
  XDG_DATA_HOME = "/state/identity/backends/opencode/xdg-data",
  XDG_STATE_HOME = "/state/identity/backends/opencode/xdg-state",
}, "exact managed launch environment")

local invalid_profile_cases = {
  {
    label = "changed schema",
    change = function(profile)
      profile.schema = 2
    end,
  },
  {
    label = "changed version",
    change = function(profile)
      profile.version = "1.18.19"
    end,
  },
  {
    label = "changed profile-root component",
    change = function(profile)
      profile.profile_root = "/state/identity/backends/opencode/profile/" .. token
    end,
  },
  {
    label = "changed profile-root token",
    change = function(profile)
      profile.profile_root = "/state/identity/backends/opencode/profiles/" .. string.rep("B", 32)
    end,
  },
  {
    label = "changed fingerprint",
    change = function(profile)
      profile.fingerprint = string.rep("C", 64)
    end,
  },
}
for _, case in ipairs(invalid_profile_cases) do
  local profile = vim.deepcopy(managed_profile)
  case.change(profile)
  rejected(function()
    return managed.profile_reference(profile)
  end, case.label)
end
rejected(function()
  return managed.environment(managed_profile, string.rep("A", 32))
end, "changed password")

local audited_risk_permissions = {
  "bash",
  "webfetch",
  "websearch",
  "external_directory",
  "doom_loop",
}
local audited_denied_permissions = { "task", "skill" }
local audited_hidden_tool_map = {
  invalid = false,
  question = false,
  bash = false,
  read = false,
  glob = false,
  grep = false,
  edit = false,
  write = false,
  task = false,
  webfetch = false,
  todowrite = false,
  websearch = false,
  skill = false,
}

local function audited_primary_permissions(edit_action)
  local rules = {
    {
      permission = "edit",
      pattern = "*",
      action = edit_action == "allow" and "deny" or "allow",
    },
    { permission = "edit", pattern = "src/nvim_ai_probe.lua", action = edit_action },
  }
  for _, permission in ipairs(audited_risk_permissions) do
    rules[#rules + 1] = { permission = permission, pattern = "*", action = "allow" }
    rules[#rules + 1] = {
      permission = permission,
      pattern = "src/nvim_ai_probe.lua",
      action = "ask",
    }
  end
  for _, permission in ipairs(audited_denied_permissions) do
    rules[#rules + 1] = { permission = permission, pattern = "*", action = "ask" }
    rules[#rules + 1] = {
      permission = permission,
      pattern = "src/nvim_ai_probe.lua",
      action = "deny",
    }
  end
  return rules
end

local function audited_hidden_agent()
  return {
    native = true,
    hidden = true,
    tools = vim.deepcopy(audited_hidden_tool_map),
    permission = { { permission = "*", pattern = "*", action = "deny" } },
  }
end

local function audited_compatibility_report()
  return {
    version = "1.18.18",
    help = {
      root = { "--pure", "serve", "attach" },
      serve = { "--hostname", "--port", "OPENCODE_SERVER_PASSWORD" },
      attach = { "--dir", "--session" },
    },
    names = { "build", "compaction", "plan", "summary", "title" },
    agents = {
      build = {
        native = true,
        mode = "primary",
        tools = {},
        permission = audited_primary_permissions("allow"),
      },
      plan = {
        native = true,
        mode = "primary",
        tools = {},
        permission = audited_primary_permissions("deny"),
      },
      compaction = audited_hidden_agent(),
      summary = audited_hidden_agent(),
      title = audited_hidden_agent(),
    },
  }
end

local good = audited_compatibility_report()
eq(good.names, { "build", "compaction", "plan", "summary", "title" }, "audited agent names")
assert(managed.validate_compatibility(good))
eq(
  managed._test.compatibility_fixture(),
  good,
  "production compatibility helper matches the independent audit"
)

local hidden_precedence = vim.deepcopy(good)
table.insert(hidden_precedence.agents.compaction.permission, 1, {
  permission = "bash",
  pattern = "*",
  action = "allow",
})
assert(managed.validate_compatibility(hidden_precedence), "final hidden denial wins precedence")

local nonmatching_wildcard_controls = {
  {
    label = "Lua character class is literal",
    agent = "plan",
    rule = { permission = "edit", pattern = "src/nvim_ai_probe[.]lua", action = "allow" },
  },
  {
    label = "Lua end anchor is literal",
    agent = "plan",
    rule = { permission = "edit", pattern = "src/nvim_ai_probe.lua$", action = "allow" },
  },
  {
    label = "resource matching is fully anchored",
    agent = "plan",
    rule = { permission = "edit", pattern = "nvim_ai_probe.lua", action = "allow" },
  },
  {
    label = "permission matching is fully anchored",
    agent = "build",
    rule = { permission = "ash", pattern = "*", action = "allow" },
  },
  {
    label = "permission brackets are literal",
    agent = "build",
    rule = { permission = "b[as]h", pattern = "*", action = "allow" },
  },
  {
    label = "question wildcard matches exactly one character",
    agent = "build",
    rule = { permission = "b??sh", pattern = "*", action = "allow" },
  },
}
for _, case in ipairs(nonmatching_wildcard_controls) do
  local report = vim.deepcopy(good)
  table.insert(report.agents[case.agent].permission, case.rule)
  assert(managed.validate_compatibility(report), case.label)
end

local wildcard_precedence = vim.deepcopy(good)
table.insert(wildcard_precedence.agents.plan.permission, {
  permission = "edit",
  pattern = "src/*.lua",
  action = "allow",
})
table.insert(wildcard_precedence.agents.plan.permission, {
  permission = "edit",
  pattern = "src/nvim_ai_*.lua",
  action = "deny",
})
assert(managed.validate_compatibility(wildcard_precedence), "last wildcard match wins precedence")

local false_accept_cases = {
  {
    label = "nonempty Build tool map",
    change = function(report)
      report.agents.build.tools.edit = false
    end,
  },
  {
    label = "unknown actionable Plan tool",
    change = function(report)
      report.agents.plan.tools.shell = true
    end,
  },
  {
    label = "hidden final wildcard allow",
    change = function(report)
      report.agents.compaction.permission[1].action = "allow"
    end,
  },
  {
    label = "hidden later permission allow",
    change = function(report)
      table.insert(report.agents.summary.permission, {
        permission = "bash",
        pattern = "src/nvim_ai_probe.lua",
        action = "allow",
      })
    end,
  },
  {
    label = "Plan wildcard edit allow",
    change = function(report)
      table.insert(report.agents.plan.permission, {
        permission = "edit",
        pattern = "src/*.lua",
        action = "allow",
      })
    end,
  },
  {
    label = "Plan optional trailing wildcard allow",
    change = function(report)
      table.insert(report.agents.plan.permission, {
        permission = "edit *",
        pattern = "src/nvim_ai_probe.lua",
        action = "allow",
      })
    end,
  },
  {
    label = "Build web-star risk allow",
    change = function(report)
      table.insert(report.agents.build.permission, {
        permission = "web*",
        pattern = "*",
        action = "allow",
      })
    end,
  },
  {
    label = "Plan bash-question risk allow",
    change = function(report)
      table.insert(report.agents.plan.permission, {
        permission = "b?sh",
        pattern = "*",
        action = "allow",
      })
    end,
  },
  {
    label = "hidden permission wildcard allow",
    change = function(report)
      table.insert(report.agents.compaction.permission, {
        permission = "b?sh",
        pattern = "*",
        action = "allow",
      })
    end,
  },
  {
    label = "hidden resource wildcard allow",
    change = function(report)
      table.insert(report.agents.summary.permission, {
        permission = "*",
        pattern = "src/*.lua",
        action = "allow",
      })
    end,
  },
  {
    label = "hidden normalized-backslash wildcard allow",
    change = function(report)
      table.insert(report.agents.title.permission, {
        permission = "*",
        pattern = "src\\*.lua",
        action = "allow",
      })
    end,
  },
}
local false_accepts = {}
for _, case in ipairs(false_accept_cases) do
  local report = vim.deepcopy(good)
  case.change(report)
  local ok, err = managed.validate_compatibility(report)
  if ok then
    false_accepts[#false_accepts + 1] = case.label
  else
    assert(type(err) == "string" and err ~= "", case.label .. " returned no diagnostic")
    assert(#err <= 256, case.label .. " returned an unbounded diagnostic")
  end
end
assert(#false_accepts == 0, "compatibility false accepts: " .. table.concat(false_accepts, ", "))

local function change_last_matching_action(report, agent_name, permission, action)
  local rules = report.agents[agent_name].permission
  for index = #rules, 1, -1 do
    local rule = rules[index]
    if
      (rule.permission == permission or rule.permission == "*")
      and (rule.pattern == "*" or rule.pattern == "src/nvim_ai_probe.lua")
    then
      rule.action = action
      return
    end
  end
  error("independent compatibility rule is missing")
end

local compatibility_mutations = {
  {
    label = "version",
    change = function(report)
      report.version = "1.18.19"
    end,
  },
  {
    label = "agents",
    change = function(report)
      report.agents.title = nil
    end,
  },
  {
    label = "build_edit",
    change = function(report)
      change_last_matching_action(report, "build", "edit", "deny")
    end,
  },
  {
    label = "plan_edit",
    change = function(report)
      change_last_matching_action(report, "plan", "edit", "allow")
    end,
  },
  {
    label = "risk",
    change = function(report)
      change_last_matching_action(report, "build", "websearch", "allow")
    end,
  },
  {
    label = "hidden_tools",
    change = function(report)
      report.agents.title.tools.websearch = true
    end,
  },
}
for _, mutation in ipairs(compatibility_mutations) do
  local changed = vim.deepcopy(good)
  mutation.change(changed)
  rejected(function()
    return managed.validate_compatibility(changed)
  end, "compatibility mutation: " .. mutation.label)
end

local invalid_compatibility_cases = {
  {
    label = "duplicate compatibility name",
    change = function(report)
      report.names[5] = "summary"
    end,
  },
  {
    label = "control-bearing compatibility name",
    change = function(report)
      report.names[1] = "build\nchanged"
    end,
  },
  {
    label = "missing compatibility field",
    change = function(report)
      report.help.attach = nil
    end,
  },
  {
    label = "changed configuration key",
    change = function(report)
      report.agents.build.configuration = {}
    end,
  },
  {
    label = "changed policy key",
    change = function(report)
      report.agents.build.permission[1].unexpected = true
    end,
  },
  {
    label = "unknown compatibility field",
    change = function(report)
      report.unexpected = true
    end,
  },
  {
    label = "missing pure-mode help",
    change = function(report)
      report.help.root[1] = "--unsafe"
    end,
  },
}
for _, case in ipairs(invalid_compatibility_cases) do
  local report = vim.deepcopy(good)
  case.change(report)
  rejected(function()
    return managed.validate_compatibility(report)
  end, case.label)
end

local oversized = vim.deepcopy(good)
oversized.unexpected = string.rep("x", 1024 * 1024)
rejected(function()
  return managed.validate_compatibility(oversized)
end, "oversized report")

local profile_token = string.rep("b", 32)
local profile_fingerprint = string.rep("c", 64)
local helper_profile = {
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
  credential_count = 2,
}
local public_profile = {
  schema = 1,
  version = "1.18.18",
  profile_root = helper_profile.profile_root,
  fingerprint = helper_profile.fingerprint,
  config_source = helper_profile.config_source,
  auth_source = helper_profile.auth_source,
  home_mask_source = helper_profile.home_mask_source,
}
local launch_identity = { key = string.rep("a", 32), root = "/work/repo" }
local launch_paths = {
  backend_state = "/state/identity/backends/opencode",
  global_opencode_data = "/home/user/.local/share/opencode",
  home_agents = "/home/user/AGENTS.md",
  profile_helper = "/config/nvim/scripts/nvim-ai-opencode-profile.py",
  python = "/usr/bin/python3",
  grants = {},
}

local function adapter_fixture(options)
  local settings = options or {}
  local calls = { prepare = {}, inspect = {} }
  local adapter = require("ai.backends.opencode").new({
    validate_launch = function(candidate_identity, candidate_paths)
      eq(candidate_identity, launch_identity, "managed adapter launch identity")
      eq(candidate_paths.backend_state, launch_paths.backend_state, "managed adapter state")
      return {
        root = candidate_identity.root,
        backend_state = candidate_paths.backend_state,
        grants = vim.deepcopy(candidate_paths.grants),
      }
    end,
    resolve_executable = function(name)
      eq(name, "opencode", "managed adapter executable")
      return "/usr/bin/opencode"
    end,
    profile_token = function()
      return profile_token
    end,
    prepare_opencode_profile = function(request)
      calls.prepare[#calls.prepare + 1] = vim.deepcopy(request)
      if settings.prepare_exception then
        error(settings.prepare_exception)
      end
      if settings.prepare_error then
        return nil, settings.prepare_error
      end
      return vim.deepcopy(settings.prepare_profile or helper_profile)
    end,
    inspect_opencode_profile = function(request)
      calls.inspect[#calls.inspect + 1] = vim.deepcopy(request)
      if settings.inspect_exception then
        error(settings.inspect_exception)
      end
      if settings.inspect_error then
        return nil, settings.inspect_error
      end
      return vim.deepcopy(settings.inspect_profile or helper_profile)
    end,
    port = function()
      return 43123
    end,
    password = function()
      return "0123456789abcdef0123456789abcdef"
    end,
    format_context = function()
      return ""
    end,
  })
  return adapter, calls
end

local managed_adapter, managed_calls = adapter_fixture()
local managed_launch = assert(managed_adapter:new_session(launch_identity, launch_paths))
eq(managed_launch.managed_profile, public_profile, "helper-private profile fields are stripped")
eq(assert(managed_adapter:profile_reference(managed_launch)), {
  token = profile_token,
  fingerprint = profile_fingerprint,
  version = "1.18.18",
}, "adapter profile reference is bounded and secret-free")
eq(#managed_calls.prepare, 1, "first activation prepares one fresh profile")
eq(managed_calls.prepare[1], request, "adapter sends the exact managed request to prepare")

local reference_paths = vim.deepcopy(launch_paths)
reference_paths.opencode_profile = {
  token = profile_token,
  fingerprint = profile_fingerprint,
  version = "1.18.18",
}
local reused =
  assert(managed_adapter:resume_session(launch_identity, reference_paths, "ses_test123"))
eq(reused.managed_profile, public_profile, "active relaunch reuses the inspected profile")
eq(#managed_calls.prepare, 1, "profile reuse does not resnapshot credentials or instructions")
eq(managed_calls.inspect, {
  {
    schema = 1,
    backend_state = launch_paths.backend_state,
    token = profile_token,
    identity_key = launch_identity.key,
    root = launch_identity.root,
    version = "1.18.18",
    fingerprint = profile_fingerprint,
  },
}, "profile inspection receives only the nonsecret identity-bound reference")
eq(
  assert(
    managed_adapter:validate_profile(
      reference_paths.opencode_profile,
      launch_identity,
      launch_paths
    )
  ),
  public_profile,
  "explicit profile validation returns the stripped public profile"
)
eq(#managed_calls.prepare, 1, "explicit validation never prepares a profile")

local invalid_reference_adapter, invalid_reference_calls = adapter_fixture({
  inspect_error = "profile-secret-canary",
})
local invalid_reference, invalid_reference_error =
  invalid_reference_adapter:resume_session(launch_identity, reference_paths, "ses_test123")
eq(invalid_reference, nil, "invalid supplied reference fails closed")
assert(type(invalid_reference_error) == "string" and invalid_reference_error ~= "")
assert(#invalid_reference_error <= 256, "invalid reference diagnostic is unbounded")
assert(
  not invalid_reference_error:find("profile-secret-canary", 1, true),
  "invalid reference diagnostic leaks helper output"
)
eq(#invalid_reference_calls.prepare, 0, "invalid supplied reference has no prepare fallback")

for _, field in ipairs({
  "schema",
  "version",
  "profile_root",
  "fingerprint",
  "config_source",
  "auth_source",
  "home_mask_source",
  "auth",
  "credential_count",
}) do
  local changed = vim.deepcopy(helper_profile)
  if field == "schema" then
    changed[field] = 2
  elseif field == "version" then
    changed[field] = "1.18.19"
  elseif field == "auth" then
    changed[field] = "unauthenticated"
  elseif field == "credential_count" then
    changed[field] = 0
  else
    changed[field] = tostring(changed[field]) .. "-changed"
  end
  local mismatch_adapter = adapter_fixture({ inspect_profile = changed })
  rejected(function()
    return mismatch_adapter:validate_profile(
      reference_paths.opencode_profile,
      launch_identity,
      launch_paths
    )
  end, "profile inspection mismatch: " .. field)
end

local helper_argv
local helper_options
local helper_revalidations = {}
local helper_result =
  assert(registry_module._test.invoke_profile_helper(launch_paths, "prepare", request, {
    revalidate = function(path)
      helper_revalidations[#helper_revalidations + 1] = path
      return true
    end,
    run = function(argv, options)
      helper_argv = vim.deepcopy(argv)
      helper_options = vim.deepcopy(options)
      return {
        code = 0,
        signal = 0,
        stdout = vim.json.encode(helper_profile) .. "\n",
        stderr = "",
      }
    end,
  }))
eq(helper_result, helper_profile, "prepare helper report")
eq(helper_argv, {
  "/usr/bin/python3",
  "-I",
  "-B",
  "/config/nvim/scripts/nvim-ai-opencode-profile.py",
  "--operation",
  "prepare",
}, "exact isolated profile-helper argv")
eq(helper_options.clear_env, true, "profile helper clears inherited environment")
eq(helper_options.env, { LANG = "C.UTF-8" }, "profile helper receives only the locale")
eq(helper_options.text, true, "profile helper uses text pipes")
eq(helper_options.timeout, 5000, "profile helper timeout")
eq(vim.json.decode(helper_options.stdin), request, "profile helper receives canonical request JSON")
eq(
  helper_revalidations,
  { "/usr/bin/python3", "/config/nvim/scripts/nvim-ai-opencode-profile.py" },
  "profile helper revalidates canonical Python and helper paths"
)

for _, failure in ipairs({
  { stdout = "", stderr = "credential-secret-canary", code = 2 },
  { stdout = "{malformed credential-secret-canary", stderr = "", code = 0 },
  { stdout = string.rep("x", 65537), stderr = "", code = 0 },
}) do
  local report, err =
    registry_module._test.invoke_profile_helper(launch_paths, "prepare", request, {
      revalidate = function()
        return true
      end,
      run = function()
        return {
          code = failure.code,
          signal = 0,
          stdout = failure.stdout,
          stderr = failure.stderr,
        }
      end,
    })
  eq(report, nil, "unsafe helper result is rejected")
  assert(type(err) == "string" and err ~= "" and #err <= 256, "helper error is not bounded")
  assert(not err:find("credential-secret-canary", 1, true), "helper error leaks secret output")
end

local semantic_probe_argv
local semantic_probe_options
local semantic_probe = registry_module._test.read_only_probe("/usr/bin/opencode", { "--version" }, {
  resolve = function(name)
    eq(name, "bwrap", "semantic probe resolves Bubblewrap")
    return "/usr/bin/bwrap"
  end,
  revalidate = function(path)
    assert(path == "/usr/bin/opencode" or path == "/usr/bin/bwrap")
    return true
  end,
  environment = { HOME = "/probe/home", OPENCODE_PURE = "true" },
  working_directory = "/probe",
  read_only_mounts = {
    { source = "/tmp/probe-home", destination = "/probe/home" },
    { source = "/tmp/probe-config", destination = "/probe/xdg-config" },
  },
  run = function(argv, options)
    semantic_probe_argv = vim.deepcopy(argv)
    semantic_probe_options = vim.deepcopy(options)
    return { code = 0, signal = 0, stdout = "1.18.18\n", stderr = "" }
  end,
})
eq(semantic_probe.code, 0, "semantic Bubblewrap probe result")
eq(semantic_probe_argv, {
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
  "--dir",
  "/probe",
  "--ro-bind",
  "/tmp/probe-home",
  "/probe/home",
  "--ro-bind",
  "/tmp/probe-config",
  "/probe/xdg-config",
  "--chdir",
  "/probe",
  "--",
  "/usr/bin/opencode",
  "--version",
}, "exact semantic Bubblewrap probe argv")
eq(semantic_probe_options.clear_env, true, "semantic probe clears the environment")
eq(semantic_probe_options.env, {
  HOME = "/probe/home",
  OPENCODE_PURE = "true",
}, "semantic probe admits only the exact environment")
eq(semantic_probe_options.timeout, 2000, "semantic probe command timeout")

local compatibility_calls = {}
local compatibility_metadata = 4
local compatibility_options = {
  revalidate = function()
    return true
  end,
  stat = function()
    return {
      type = "file",
      dev = 1,
      ino = 2,
      mode = 493,
      uid = 0,
      size = 3,
      mtime = { sec = compatibility_metadata, nsec = 5 },
      ctime = { sec = 6, nsec = 7 },
    }
  end,
  probe = function(_, arguments, options)
    compatibility_calls[#compatibility_calls + 1] = {
      arguments = vim.deepcopy(arguments),
      options = vim.deepcopy(options),
    }
    local key = table.concat(arguments, "\0")
    local outputs = {
      ["--version"] = "1.18.18\n",
      ["--help"] = "--pure serve attach",
      ["serve\0--help"] = "--hostname --port OPENCODE_SERVER_PASSWORD",
      ["attach\0--help"] = "--dir --session",
      ["--pure\0agent\0list"] = table.concat({
        "build (primary)",
        "compaction (subagent)",
        "plan (primary)",
        "summary (subagent)",
        "title (subagent)",
      }, "\n") .. "\n",
    }
    local agent = key:match("^%-%-pure%zdebug%zagent%z(.+)$")
    if agent == "general" or agent == "explore" then
      return { code = 1, signal = 0, stdout = "", stderr = "Agent " .. agent .. " not found\n" }
    end
    if agent then
      return {
        code = 0,
        signal = 0,
        stdout = vim.json.encode(good.agents[agent]) .. "\n",
        stderr = "",
      }
    end
    return { code = 0, signal = 0, stdout = assert(outputs[key]), stderr = "" }
  end,
}
registry_module._test.reset_opencode_compatibility_cache()
local compatibility =
  assert(registry_module._test.opencode_compatibility("/usr/bin/opencode", compatibility_options))
assert(managed.validate_compatibility(compatibility))
eq(#compatibility_calls, 12, "exact OpenCode compatibility command count")
eq(compatibility_calls[1].arguments, { "--version" }, "exact version probe")
eq(compatibility_calls[5].arguments, { "--pure", "agent", "list" }, "exact pure agent-list probe")
eq(
  compatibility_calls[12].arguments,
  { "--pure", "debug", "agent", "explore" },
  "exact disabled explore probe"
)
for _, call in ipairs(compatibility_calls) do
  eq(call.options.environment, {
    HOME = "/probe/home",
    OPENCODE_CONFIG_CONTENT = managed.config_json(),
    OPENCODE_DISABLE_AUTOUPDATE = "true",
    OPENCODE_DISABLE_CLAUDE_CODE = "true",
    OPENCODE_DISABLE_EXTERNAL_SKILLS = "true",
    OPENCODE_DISABLE_LSP_DOWNLOAD = "true",
    OPENCODE_DISABLE_PROJECT_CONFIG = "true",
    OPENCODE_PERMISSION = managed.policy_json(),
    OPENCODE_PURE = "true",
    XDG_CACHE_HOME = "/tmp/xdg-cache",
    XDG_CONFIG_HOME = "/probe/xdg-config",
    XDG_DATA_HOME = "/tmp/xdg-data",
    XDG_STATE_HOME = "/tmp/xdg-state",
  }, "exact clear OpenCode probe environment")
  eq(call.options.working_directory, "/probe", "fixed OpenCode probe working directory")
end

assert(registry_module._test.opencode_compatibility("/usr/bin/opencode", compatibility_options))
eq(#compatibility_calls, 12, "successful sanitized compatibility is cached")
compatibility_metadata = 5
assert(registry_module._test.opencode_compatibility("/usr/bin/opencode", compatibility_options))
eq(#compatibility_calls, 24, "executable metadata change invalidates compatibility cache")

local successful_probe = compatibility_options.probe
local probe_failure_cases = {
  {
    label = "prefixed version",
    key = "--version",
    result = { code = 0, signal = 0, stdout = "opencode 1.18.18\n", stderr = "" },
  },
  {
    label = "missing pure flag",
    key = "--help",
    result = { code = 0, signal = 0, stdout = "serve attach", stderr = "" },
  },
  {
    label = "malformed agent JSON",
    key = "--pure\0debug\0agent\0build",
    result = { code = 0, signal = 0, stdout = "{probe-secret-canary", stderr = "" },
  },
  {
    label = "changed visible agent set",
    key = "--pure\0agent\0list",
    result = {
      code = 0,
      signal = 0,
      stdout = "build (primary)\ncompaction (subagent)\ncustom (subagent)\nplan (primary)\nsummary (subagent)\ntitle (subagent)\n",
      stderr = "",
    },
  },
  {
    label = "arbitrary disabled-agent failure",
    key = "--pure\0debug\0agent\0general",
    result = { code = 1, signal = 0, stdout = "", stderr = "probe-secret-canary\n" },
  },
}
for _, case in ipairs(probe_failure_cases) do
  registry_module._test.reset_opencode_compatibility_cache()
  compatibility_metadata = compatibility_metadata + 1
  compatibility_options.probe = function(executable, arguments, options)
    if table.concat(arguments, "\0") == case.key then
      compatibility_calls[#compatibility_calls + 1] = {
        arguments = vim.deepcopy(arguments),
        options = vim.deepcopy(options),
      }
      return vim.deepcopy(case.result)
    end
    return successful_probe(executable, arguments, options)
  end
  local failed, failure_error =
    registry_module._test.opencode_compatibility("/usr/bin/opencode", compatibility_options)
  eq(failed, nil, case.label .. " is incompatible")
  assert(
    type(failure_error) == "string" and failure_error ~= "" and #failure_error <= 256,
    case.label .. " returned no bounded diagnostic"
  )
  assert(
    not failure_error:find("probe-secret-canary", 1, true),
    case.label .. " leaked raw probe output"
  )
end
compatibility_options.probe = successful_probe

print("AI managed OpenCode assertions: ok")
