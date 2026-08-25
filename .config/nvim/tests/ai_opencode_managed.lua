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
eq(
  managed.bootstrap_gitignore(),
  "node_modules\npackage.json\npackage-lock.json\nbun.lock\n.gitignore",
  "canonical OpenCode configuration bootstrap"
)
eq(
  managed.bootstrap_gitignore_sha256(),
  "663a068e76d264d0bc6740f5450b6c4193c7b41ecf5e0dc222485b8a17404d95",
  "canonical OpenCode configuration bootstrap digest"
)
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
local audited_primary_tool_map = {
  invalid = true,
  question = true,
  bash = true,
  read = true,
  glob = true,
  grep = true,
  edit = true,
  write = true,
  task = false,
  webfetch = true,
  todowrite = true,
  websearch = true,
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
      serve = { "--hostname", "--port" },
      attach = { "--dir", "--session", "OPENCODE_SERVER_PASSWORD" },
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
  lstat = function()
    return { type = "directory", uid = 1000, mode = 448 }
  end,
  getuid = function()
    return 1000
  end,
  environment = { HOME = "/tmp/nvim-ai-probe/home", OPENCODE_PURE = "true" },
  working_directory = "/tmp/nvim-ai-probe",
  read_only_mounts = {
    { source = "/tmp/probe-home", destination = "/tmp/nvim-ai-probe/home" },
    { source = "/tmp/probe-config", destination = "/tmp/nvim-ai-probe/xdg-config" },
  },
  writable_mounts = {
    { source = "/tmp/probe-data", destination = "/tmp/nvim-ai-probe/xdg-data" },
    { source = "/tmp/probe-cache", destination = "/tmp/nvim-ai-probe/xdg-cache" },
    { source = "/tmp/probe-state", destination = "/tmp/nvim-ai-probe/xdg-state" },
  },
  inspect_artifacts = function()
    return true
  end,
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
  "/tmp/nvim-ai-probe",
  "--dir",
  "/tmp/nvim-ai-probe/home",
  "--dir",
  "/tmp/nvim-ai-probe/xdg-config",
  "--dir",
  "/tmp/nvim-ai-probe/xdg-data",
  "--dir",
  "/tmp/nvim-ai-probe/xdg-cache",
  "--dir",
  "/tmp/nvim-ai-probe/xdg-state",
  "--ro-bind",
  "/tmp/probe-home",
  "/tmp/nvim-ai-probe/home",
  "--ro-bind",
  "/tmp/probe-config",
  "/tmp/nvim-ai-probe/xdg-config",
  "--bind",
  "/tmp/probe-data",
  "/tmp/nvim-ai-probe/xdg-data",
  "--bind",
  "/tmp/probe-cache",
  "/tmp/nvim-ai-probe/xdg-cache",
  "--bind",
  "/tmp/probe-state",
  "/tmp/nvim-ai-probe/xdg-state",
  "--chdir",
  "/tmp/nvim-ai-probe",
  "--",
  "/usr/bin/opencode",
  "--version",
}, "exact semantic Bubblewrap probe argv")
eq(semantic_probe_options.clear_env, true, "semantic probe clears the environment")
eq(semantic_probe_options.env, {
  HOME = "/tmp/nvim-ai-probe/home",
  OPENCODE_PURE = "true",
}, "semantic probe admits only the exact environment")
eq(semantic_probe_options.timeout, 2000, "semantic probe command timeout")

local raised_probe_inspected = false
local raised_probe = registry_module._test.read_only_probe("/usr/bin/opencode", {}, {
  resolve = function()
    return "/usr/bin/bwrap"
  end,
  revalidate = function()
    return true
  end,
  run = function()
    error("probe-artifact-secret-canary")
  end,
  inspect_artifacts = function(result)
    raised_probe_inspected = type(result) == "string"
    return true
  end,
})
assert(raised_probe_inspected, "probe artifacts were not inspected after runner exception")
eq(raised_probe.code, 126, "runner exception fails the probe boundary")
assert(
  not raised_probe.stderr:find("probe-artifact-secret-canary", 1, true),
  "runner exception leaked through the probe boundary"
)

local real_probe_root = vim.fn.tempname()
assert(vim.fn.mkdir(real_probe_root, "p", 448) == 1, "create real probe fixture root")
local real_probe_home = real_probe_root .. "/home"
local real_probe_config = real_probe_root .. "/xdg-config"
assert(vim.fn.mkdir(real_probe_home, "", 448) == 1, "create real probe home")
assert(vim.fn.mkdir(real_probe_config, "", 448) == 1, "create real probe config")
local true_executable = assert(require("ai.tools").resolve("true"))
local real_probe = registry_module._test.read_only_probe(true_executable, {}, {
  environment = { HOME = "/tmp/nvim-ai-probe/home" },
  working_directory = "/tmp/nvim-ai-probe",
  read_only_mounts = {
    { source = real_probe_home, destination = "/tmp/nvim-ai-probe/home" },
    { source = real_probe_config, destination = "/tmp/nvim-ai-probe/xdg-config" },
  },
})
vim.fn.delete(real_probe_root, "rf")
assert(real_probe.code == 0, "provider-free real Bubblewrap probe failed: " .. real_probe.stderr)

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
      ["serve\0--help"] = "--hostname --port",
      ["attach\0--help"] = "--dir --session OPENCODE_SERVER_PASSWORD",
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
      return {
        code = 1,
        signal = 0,
        stdout = "",
        stderr = "Agent "
          .. agent
          .. " not found, run 'opencode agent list' to get an agent list\n",
      }
    end
    if agent then
      local report = vim.deepcopy(good.agents[agent])
      if agent == "build" or agent == "plan" then
        report.tools = vim.deepcopy(audited_primary_tool_map)
      end
      return {
        code = 0,
        signal = 0,
        stdout = vim.json.encode(report) .. "\n",
        stderr = "",
      }
    end
    if key == "--help" or key == "serve\0--help" or key == "attach\0--help" then
      return { code = 0, signal = 0, stdout = "", stderr = assert(outputs[key]) }
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
  }, "exact clear OpenCode probe environment")
  eq(call.options.working_directory, "/tmp/nvim-ai-probe", "fixed OpenCode probe working directory")
  eq(call.options.read_only_mounts, {
    {
      source = "/tmp/nvim-ai-opencode-probe-home",
      destination = "/tmp/nvim-ai-probe/home",
    },
    {
      source = "/tmp/nvim-ai-opencode-probe-config",
      destination = "/tmp/nvim-ai-probe/xdg-config",
    },
  }, "exact OpenCode probe read-only mounts")
  eq(call.options.writable_mounts, {
    {
      source = "/tmp/nvim-ai-opencode-probe-data",
      destination = "/tmp/nvim-ai-probe/xdg-data",
    },
    {
      source = "/tmp/nvim-ai-opencode-probe-cache",
      destination = "/tmp/nvim-ai-probe/xdg-cache",
    },
    {
      source = "/tmp/nvim-ai-opencode-probe-state",
      destination = "/tmp/nvim-ai-probe/xdg-state",
    },
  }, "exact OpenCode probe writable mounts")
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

local artifact_failures = {}
registry_module._test.reset_opencode_compatibility_cache()
compatibility_metadata = compatibility_metadata + 1
local injected_artifact_options = vim.tbl_extend("force", {}, compatibility_options, {
  inspect_artifacts = function()
    return nil, "probe-artifact-secret-canary"
  end,
})
local injected_artifact_report, injected_artifact_error =
  registry_module._test.opencode_compatibility("/usr/bin/opencode", injected_artifact_options)
if injected_artifact_report ~= nil then
  artifact_failures[#artifact_failures + 1] = "injected forbidden artifact was accepted"
else
  assert(
    type(injected_artifact_error) == "string"
      and not injected_artifact_error:find("probe-artifact-secret-canary", 1, true),
    "injected artifact diagnostic leaks raw evidence"
  )
end

local sentinel_root = vim.fs.joinpath(
  assert(vim.env.HOME),
  ".config",
  ".nvim-ai-opencode-probe-" .. vim.fn.sha256(vim.fn.tempname()):sub(1, 16)
)
assert(vim.fn.mkdir(sentinel_root, "p", 448) == 1, "create sentinel probe root")
local sentinel_paths = {
  home = sentinel_root .. "/home",
  config = sentinel_root .. "/xdg-config",
  data = sentinel_root .. "/xdg-data",
  cache = sentinel_root .. "/xdg-cache",
  state = sentinel_root .. "/xdg-state",
}
for _, path in pairs(sentinel_paths) do
  assert(vim.fn.mkdir(path, "", 448) == 1, "create sentinel probe directory")
end
local sentinel_executable = sentinel_root .. "/write-xdg-sentinel"
vim.fn.writefile({
  "#!/bin/sh",
  'mkdir -p "$XDG_CACHE_HOME"',
  'printf forbidden > "$XDG_CACHE_HOME/forbidden-sentinel"',
  "exit 0",
}, sentinel_executable)
assert(vim.uv.fs_chmod(sentinel_executable, 448))
local resolved_sentinel = assert(require("ai.tools").resolve(sentinel_executable))
local sentinel_probe = registry_module._test.read_only_probe(resolved_sentinel, {}, {
  environment = {
    HOME = "/tmp/nvim-ai-probe/home",
    XDG_CACHE_HOME = "/tmp/nvim-ai-probe/xdg-cache",
    XDG_CONFIG_HOME = "/tmp/nvim-ai-probe/xdg-config",
    XDG_DATA_HOME = "/tmp/nvim-ai-probe/xdg-data",
    XDG_STATE_HOME = "/tmp/nvim-ai-probe/xdg-state",
  },
  working_directory = "/tmp/nvim-ai-probe",
  read_only_mounts = {
    { source = sentinel_paths.home, destination = "/tmp/nvim-ai-probe/home" },
    { source = sentinel_paths.config, destination = "/tmp/nvim-ai-probe/xdg-config" },
  },
  writable_mounts = {
    { source = sentinel_paths.data, destination = "/tmp/nvim-ai-probe/xdg-data" },
    { source = sentinel_paths.cache, destination = "/tmp/nvim-ai-probe/xdg-cache" },
    { source = sentinel_paths.state, destination = "/tmp/nvim-ai-probe/xdg-state" },
  },
  inspect_artifacts = function()
    if vim.uv.fs_lstat(sentinel_paths.cache .. "/forbidden-sentinel") then
      return nil, "probe-artifact-secret-canary"
    end
    return true
  end,
})
vim.fn.delete(sentinel_root, "rf")
if sentinel_probe.code ~= 125 then
  artifact_failures[#artifact_failures + 1] = string.format(
    "real Bubblewrap XDG sentinel was not detected (code=%s, stderr=%s)",
    tostring(sentinel_probe.code),
    sentinel_probe.stderr
  )
else
  assert(
    not sentinel_probe.stderr:find("probe-artifact-secret-canary", 1, true),
    "real artifact diagnostic leaks raw evidence"
  )
end

assert(#artifact_failures == 0, table.concat(artifact_failures, "; "))

local installed_opencode = assert(require("ai.tools").resolve("opencode"))
local real_artifact_environment = {
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

local function real_artifact_probe_options(tree)
  return {
    environment = vim.deepcopy(real_artifact_environment),
    working_directory = "/tmp/nvim-ai-probe",
    read_only_mounts = {
      { source = tree.home, destination = "/tmp/nvim-ai-probe/home" },
      { source = tree.config, destination = "/tmp/nvim-ai-probe/xdg-config" },
    },
    writable_mounts = {
      { source = tree.data, destination = "/tmp/nvim-ai-probe/xdg-data" },
      { source = tree.cache, destination = "/tmp/nvim-ai-probe/xdg-cache" },
      { source = tree.state, destination = "/tmp/nvim-ai-probe/xdg-state" },
    },
    inspect_artifacts = function()
      return true
    end,
  }
end

local function fixture_read(path)
  local stat = assert(vim.uv.fs_lstat(path))
  local descriptor = assert(vim.uv.fs_open(path, "r", 0))
  local bytes = stat.size == 0 and "" or assert(vim.uv.fs_read(descriptor, stat.size, 0))
  assert(vim.uv.fs_close(descriptor))
  return bytes
end

local function fixture_write(path, bytes)
  local descriptor = assert(vim.uv.fs_open(path, "w", 384))
  if #bytes > 0 then
    eq(vim.uv.fs_write(descriptor, bytes, 0), #bytes, "complete artifact-fixture write")
  end
  assert(vim.uv.fs_fsync(descriptor))
  assert(vim.uv.fs_close(descriptor))
  assert(vim.uv.fs_chmod(path, 384))
end

local artifact_trees = {}
local artifact_summaries = {}
for index = 1, 2 do
  local tree = assert(registry_module._test.create_opencode_probe_tree())
  artifact_trees[index] = tree
  local result = registry_module._test.read_only_probe(
    installed_opencode,
    { "--pure", "agent", "list" },
    real_artifact_probe_options(tree)
  )
  assert(result.code == 0, "clean real OpenCode artifact fixture failed")
  assert(
    registry_module._test.inspect_opencode_probe_artifacts(tree, true),
    "production artifact inspector rejected a clean real OpenCode fixture"
  )
  local database = tree.data .. "/opencode/opencode.db"
  local shared_memory = tree.data .. "/opencode/opencode.db-shm"
  local write_ahead_log = tree.data .. "/opencode/opencode.db-wal"
  artifact_summaries[index] = {
    lock = assert(
      vim.uv.fs_lstat(tree.state .. "/opencode/locks/0a009c556ac8352fed53ef8323a3a97270935d30.lock")
    ).type,
    database_sha256 = vim.fn.sha256(fixture_read(database)),
    database_size = assert(vim.uv.fs_lstat(database)).size,
    shared_memory_size = assert(vim.uv.fs_lstat(shared_memory)).size,
    write_ahead_log_size = assert(vim.uv.fs_lstat(write_ahead_log)).size,
  }
end
local exact_artifact_summary = {
  lock = "directory",
  database_sha256 = "40cf07c52bfaa52b334ef341456f970787f6dc701ffe18ad3c572cb5056dbd70",
  database_size = 4096,
  shared_memory_size = 32768,
  write_ahead_log_size = 259592,
}
eq(artifact_summaries[1], exact_artifact_summary, "first clean real artifact shape")
eq(artifact_summaries[2], exact_artifact_summary, "repeated clean real artifact shape")

local mutation_tree = artifact_trees[1]
local artifact_paths = {
  bootstrap = mutation_tree.bootstrap,
  database = mutation_tree.data .. "/opencode/opencode.db",
  log = mutation_tree.data .. "/opencode/log/opencode.log",
  metadata = mutation_tree.state
    .. "/opencode/locks/0a009c556ac8352fed53ef8323a3a97270935d30.lock/meta.json",
  heartbeat = mutation_tree.state
    .. "/opencode/locks/0a009c556ac8352fed53ef8323a3a97270935d30.lock/heartbeat",
  shared_memory = mutation_tree.data .. "/opencode/opencode.db-shm",
  unknown = mutation_tree.cache .. "/opencode/unknown-artifact",
  write_ahead_log = mutation_tree.data .. "/opencode/opencode.db-wal",
}
local function artifacts_rejected(label, overrides)
  assert(
    not registry_module._test.inspect_opencode_probe_artifacts(mutation_tree, true, overrides),
    label .. " was accepted by the production artifact inspector"
  )
end

fixture_write(artifact_paths.unknown, "unknown")
artifacts_rejected("unknown artifact")
assert(vim.uv.fs_unlink(artifact_paths.unknown))

fixture_write(artifact_paths.log, "forbidden log")
artifacts_rejected("nonempty probe log")
fixture_write(artifact_paths.log, "")

local database_bytes = fixture_read(artifact_paths.database)
fixture_write(artifact_paths.database, "X" .. database_bytes:sub(2))
artifacts_rejected("altered probe database")
fixture_write(artifact_paths.database, database_bytes)

local write_ahead_log_bytes = fixture_read(artifact_paths.write_ahead_log)
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes:sub(1, -2))
artifacts_rejected("altered probe write-ahead log")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)

local function flip_artifact_byte(bytes, offset)
  return bytes:sub(1, offset - 1)
    .. string.char(require("bit").bxor(bytes:byte(offset), 1))
    .. bytes:sub(offset + 1)
end

local SQLITE_U32_MODULO = 4294967296

local function artifact_u32(bytes, offset, little_endian)
  local first, second, third, fourth = bytes:byte(offset, offset + 3)
  assert(fourth, "complete artifact u32")
  if little_endian then
    return first + second * 256 + third * 65536 + fourth * 16777216
  end
  return first * 16777216 + second * 65536 + third * 256 + fourth
end

local function artifact_pack_u32(value, little_endian)
  value = value % SQLITE_U32_MODULO
  local first = math.floor(value / 16777216) % 256
  local second = math.floor(value / 65536) % 256
  local third = math.floor(value / 256) % 256
  local fourth = value % 256
  if little_endian then
    return string.char(fourth, third, second, first)
  end
  return string.char(first, second, third, fourth)
end

local function artifact_replace(bytes, offset, replacement)
  return bytes:sub(1, offset - 1) .. replacement .. bytes:sub(offset + #replacement)
end

local function artifact_sqlite_checksum(bytes, offset, length, checksum0, checksum1)
  for index = offset, offset + length - 1, 8 do
    local word0 = artifact_u32(bytes, index, true)
    local word1 = artifact_u32(bytes, index + 4, true)
    checksum0 = (checksum0 + word0 + checksum1) % SQLITE_U32_MODULO
    checksum1 = (checksum1 + word1 + checksum0) % SQLITE_U32_MODULO
  end
  return checksum0, checksum1
end

local function rechecksum_artifact_wal(bytes)
  local checksum0, checksum1 = artifact_sqlite_checksum(bytes, 1, 24, 0, 0)
  bytes = artifact_replace(
    bytes,
    25,
    artifact_pack_u32(checksum0, false) .. artifact_pack_u32(checksum1, false)
  )
  for frame = 0, 62 do
    local base = 33 + frame * 4120
    checksum0, checksum1 = artifact_sqlite_checksum(bytes, base, 8, checksum0, checksum1)
    checksum0, checksum1 = artifact_sqlite_checksum(bytes, base + 24, 4096, checksum0, checksum1)
    bytes = artifact_replace(
      bytes,
      base + 16,
      artifact_pack_u32(checksum0, false) .. artifact_pack_u32(checksum1, false)
    )
  end
  return bytes
end

local function link_artifact_shm_to_wal(shared_memory, write_ahead_log)
  local final_frame = 33 + 62 * 4120
  local checksum0 = artifact_u32(write_ahead_log, final_frame + 16, false)
  local checksum1 = artifact_u32(write_ahead_log, final_frame + 20, false)
  local header = artifact_replace(
    shared_memory,
    25,
    artifact_pack_u32(checksum0, true) .. artifact_pack_u32(checksum1, true)
  )
  header = artifact_replace(header, 33, write_ahead_log:sub(17, 24))
  checksum0, checksum1 = artifact_sqlite_checksum(header, 1, 40, 0, 0)
  header = artifact_replace(
    header,
    41,
    artifact_pack_u32(checksum0, true) .. artifact_pack_u32(checksum1, true)
  )
  return artifact_replace(header, 49, header:sub(1, 48))
end

local function artifact_u48_be(bytes, offset)
  local value = 0
  for index = offset, offset + 5 do
    value = value * 256 + bytes:byte(index)
  end
  return value
end

local function artifact_pack_u48_be(value)
  local bytes = {}
  for index = 6, 1, -1 do
    bytes[index] = string.char(value % 256)
    value = math.floor(value / 256)
  end
  return table.concat(bytes)
end

local unchecked_same_size_mutations = {}
local function require_same_size_mutation_rejection(label)
  if registry_module._test.inspect_opencode_probe_artifacts(mutation_tree, true) then
    unchecked_same_size_mutations[#unchecked_same_size_mutations + 1] = label
  end
end

fixture_write(
  artifact_paths.write_ahead_log,
  flip_artifact_byte(write_ahead_log_bytes, #write_ahead_log_bytes)
)
require_same_size_mutation_rejection("same-size WAL final-byte flip")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)

fixture_write(artifact_paths.write_ahead_log, flip_artifact_byte(write_ahead_log_bytes, 1000))
require_same_size_mutation_rejection("same-size WAL interior-byte flip")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)

fixture_write(artifact_paths.write_ahead_log, flip_artifact_byte(write_ahead_log_bytes, 25))
require_same_size_mutation_rejection("corrupt WAL header checksum")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)

fixture_write(artifact_paths.write_ahead_log, flip_artifact_byte(write_ahead_log_bytes, 49))
require_same_size_mutation_rejection("corrupt WAL frame checksum")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)

local shared_memory_bytes = fixture_read(artifact_paths.shared_memory)
fixture_write(
  artifact_paths.shared_memory,
  flip_artifact_byte(shared_memory_bytes, #shared_memory_bytes)
)
require_same_size_mutation_rejection("same-size SHM final-byte flip")
fixture_write(artifact_paths.shared_memory, shared_memory_bytes)

local corrupt_shm_header_checksum = flip_artifact_byte(shared_memory_bytes, 41)
corrupt_shm_header_checksum = flip_artifact_byte(corrupt_shm_header_checksum, 89)
fixture_write(artifact_paths.shared_memory, corrupt_shm_header_checksum)
require_same_size_mutation_rejection("corrupt duplicated SHM header checksum")
fixture_write(artifact_paths.shared_memory, shared_memory_bytes)

local corrupt_shm_frame_checksum = flip_artifact_byte(shared_memory_bytes, 25)
corrupt_shm_frame_checksum = flip_artifact_byte(corrupt_shm_frame_checksum, 73)
fixture_write(artifact_paths.shared_memory, corrupt_shm_frame_checksum)
require_same_size_mutation_rejection("corrupt duplicated SHM WAL-checksum linkage")
fixture_write(artifact_paths.shared_memory, shared_memory_bytes)

local rechecksummed_interior_wal =
  rechecksum_artifact_wal(flip_artifact_byte(write_ahead_log_bytes, 1000))
local relinked_interior_shm =
  link_artifact_shm_to_wal(shared_memory_bytes, rechecksummed_interior_wal)
fixture_write(artifact_paths.write_ahead_log, rechecksummed_interior_wal)
fixture_write(artifact_paths.shared_memory, relinked_interior_shm)
require_same_size_mutation_rejection("rechecksummed WAL non-dynamic-byte flip")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)
fixture_write(artifact_paths.shared_memory, shared_memory_bytes)

local migration_timestamp_offset = 245568
local migration_timestamp = artifact_u48_be(write_ahead_log_bytes, migration_timestamp_offset)
local corrupt_timestamp_wal = artifact_replace(
  write_ahead_log_bytes,
  migration_timestamp_offset,
  artifact_pack_u48_be(migration_timestamp + 5000)
)
corrupt_timestamp_wal = rechecksum_artifact_wal(corrupt_timestamp_wal)
local corrupt_timestamp_shm = link_artifact_shm_to_wal(shared_memory_bytes, corrupt_timestamp_wal)
fixture_write(artifact_paths.write_ahead_log, corrupt_timestamp_wal)
fixture_write(artifact_paths.shared_memory, corrupt_timestamp_shm)
require_same_size_mutation_rejection("rechecksummed inconsistent migration timestamp")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)
fixture_write(artifact_paths.shared_memory, shared_memory_bytes)

assert(
  #unchecked_same_size_mutations == 0,
  "production artifact inspector accepted: " .. table.concat(unchecked_same_size_mutations, "; ")
)

local corrupt_wal_salt = flip_artifact_byte(write_ahead_log_bytes, 41)
fixture_write(artifact_paths.write_ahead_log, corrupt_wal_salt)
artifacts_rejected("corrupt WAL frame salt")
fixture_write(artifact_paths.write_ahead_log, write_ahead_log_bytes)

local corrupt_shm_salt = flip_artifact_byte(shared_memory_bytes, 33)
corrupt_shm_salt = flip_artifact_byte(corrupt_shm_salt, 81)
fixture_write(artifact_paths.shared_memory, corrupt_shm_salt)
artifacts_rejected("corrupt duplicated SHM salt linkage")
fixture_write(artifact_paths.shared_memory, shared_memory_bytes)

local metadata_bytes = fixture_read(artifact_paths.metadata)
local altered_metadata, replacements = metadata_bytes:gsub('"pid": 2', '"pid": 3', 1)
eq(replacements, 1, "lock metadata fixture mutation")
fixture_write(artifact_paths.metadata, altered_metadata)
artifacts_rejected("altered probe lock metadata")
fixture_write(artifact_paths.metadata, metadata_bytes)

assert(vim.uv.fs_chmod(artifact_paths.log, 420))
artifacts_rejected("wrong artifact mode")
assert(vim.uv.fs_chmod(artifact_paths.log, 384))

artifacts_rejected("wrong artifact owner", {
  lstat = function(path)
    local stat = vim.uv.fs_lstat(path)
    if path == artifact_paths.log and stat then
      stat = vim.deepcopy(stat)
      stat.uid = stat.uid + 1
    end
    return stat
  end,
})

assert(vim.uv.fs_unlink(artifact_paths.heartbeat))
assert(vim.uv.fs_symlink(artifact_paths.log, artifact_paths.heartbeat))
artifacts_rejected("artifact symlink")
assert(vim.uv.fs_unlink(artifact_paths.heartbeat))
fixture_write(artifact_paths.heartbeat, "")

local replacement_lstat_calls = 0
artifacts_rejected("artifact replacement", {
  lstat = function(path)
    local stat = vim.uv.fs_lstat(path)
    if path == artifact_paths.database and stat then
      replacement_lstat_calls = replacement_lstat_calls + 1
      if replacement_lstat_calls > 1 then
        stat = vim.deepcopy(stat)
        stat.ino = stat.ino + 1
      end
    end
    return stat
  end,
})
assert(replacement_lstat_calls > 1, "artifact replacement check did not revalidate identity")

local directory_path = mutation_tree.cache .. "/opencode"
local directory_lstat_calls = 0
artifacts_rejected("artifact directory replacement", {
  lstat = function(path)
    local stat = vim.uv.fs_lstat(path)
    if path == directory_path and stat then
      directory_lstat_calls = directory_lstat_calls + 1
      if directory_lstat_calls > 1 then
        stat = vim.deepcopy(stat)
        stat.ino = stat.ino + 1
      end
    end
    return stat
  end,
})
assert(directory_lstat_calls > 1, "artifact directory replacement was not revalidated")

fixture_write(artifact_paths.unknown, "unknown")
local parked_directory = mutation_tree.cache .. "/opencode-parked"
local descriptor_swap_exercised = false
artifacts_rejected("descriptor-bound directory swap", {
  scandir = function(path)
    local target = vim.uv.fs_readlink(path)
    if not descriptor_swap_exercised and target == directory_path then
      assert(vim.uv.fs_rename(directory_path, parked_directory))
      assert(vim.fn.mkdir(directory_path, "", 448) == 1)
      local request = assert(vim.uv.fs_scandir(path))
      assert(vim.uv.fs_rmdir(directory_path))
      assert(vim.uv.fs_rename(parked_directory, directory_path))
      descriptor_swap_exercised = true
      return request
    end
    return vim.uv.fs_scandir(path)
  end,
})
assert(descriptor_swap_exercised, "artifact enumeration did not use its directory descriptor")
assert(vim.uv.fs_unlink(artifact_paths.unknown))

local bootstrap_bytes = fixture_read(artifact_paths.bootstrap)
fixture_write(artifact_paths.bootstrap, bootstrap_bytes .. "\n")
artifacts_rejected("altered configuration bootstrap")
fixture_write(artifact_paths.bootstrap, bootstrap_bytes)
assert(vim.uv.fs_chmod(artifact_paths.bootstrap, 420))
artifacts_rejected("wrong configuration bootstrap mode")
assert(vim.uv.fs_chmod(artifact_paths.bootstrap, 384))

for _, tree in ipairs(artifact_trees) do
  vim.fn.delete(tree.root, "rf")
end

registry_module._test.reset_opencode_compatibility_cache()
local installed_compatibility, installed_compatibility_error =
  registry_module._test.opencode_compatibility(installed_opencode)
assert(
  installed_compatibility ~= nil,
  "real pinned OpenCode compatibility boundary failed: " .. tostring(installed_compatibility_error)
)
assert(managed.validate_compatibility(installed_compatibility))

print("AI managed OpenCode assertions: ok")
