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

print("AI managed OpenCode assertions: ok")
