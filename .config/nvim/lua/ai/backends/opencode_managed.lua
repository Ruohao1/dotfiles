local M = {}

local VERSION = "1.18.18"
local POLICY = {
  bash = "ask",
  doom_loop = "ask",
  external_directory = "ask",
  skill = "deny",
  task = "deny",
  webfetch = "ask",
  websearch = "ask",
}

local CONFIG = {
  ["$schema"] = "https://opencode.ai/config.json",
  autoupdate = false,
  permission = POLICY,
  agent = {
    general = { disable = true },
    explore = { disable = true },
    compaction = { permission = { ["*"] = "deny" } },
    summary = { permission = { ["*"] = "deny" } },
    title = { permission = { ["*"] = "deny" } },
  },
}

local POLICY_JSON =
  '{"bash":"ask","doom_loop":"ask","external_directory":"ask","skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"}'
local CONFIG_JSON =
  '{"$schema":"https://opencode.ai/config.json","autoupdate":false,"permission":{"bash":"ask","doom_loop":"ask","external_directory":"ask","skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"},"agent":{"general":{"disable":true},"explore":{"disable":true},"compaction":{"permission":{"*":"deny"}},"summary":{"permission":{"*":"deny"}},"title":{"permission":{"*":"deny"}}}}'

local C0_PATTERN = "[%z\1-\31\127]"
local C1_PATTERN = "\194[\128-\159]"
local MAX_REPORT_BYTES = 1024 * 1024
local PROBE_PATH = "src/nvim_ai_probe.lua"
local EXPECTED_NAMES = { "build", "compaction", "plan", "summary", "title" }
local EXPECTED_HELP = {
  root = { "--pure", "serve", "attach" },
  serve = { "--hostname", "--port", "OPENCODE_SERVER_PASSWORD" },
  attach = { "--dir", "--session" },
}
local RISK_PERMISSIONS = { "bash", "webfetch", "websearch", "external_directory", "doom_loop" }
local DENIED_PERMISSIONS = { "task", "skill" }
local HIDDEN_TOOLS = {
  "invalid",
  "question",
  "bash",
  "read",
  "glob",
  "grep",
  "edit",
  "write",
  "task",
  "webfetch",
  "todowrite",
  "websearch",
  "skill",
}

local function has_control(value)
  return type(value) ~= "string" or value:find(C0_PATTERN) ~= nil or value:find(C1_PATTERN) ~= nil
end

local function valid_hex(value, length)
  return type(value) == "string" and #value == length and value:match("^[0-9a-f]+$") ~= nil
end

local function canonical_path(value, label)
  if type(value) ~= "string" or value == "" or value:sub(1, 1) ~= "/" then
    return nil, label .. " must be an absolute path"
  end
  if has_control(value) then
    return nil, label .. " contains a control character"
  end
  local ok, normalized = pcall(vim.fs.normalize, value)
  if not ok or normalized ~= value or value == "/" then
    return nil, label .. " must be canonical"
  end
  return value
end

local function exact_keys(value, keys, label)
  if type(value) ~= "table" then
    return nil, label .. " must be an object"
  end
  local allowed = {}
  for _, key in ipairs(keys) do
    allowed[key] = true
    if value[key] == nil then
      return nil, label .. " is missing a field"
    end
  end
  for key in pairs(value) do
    if type(key) ~= "string" or not allowed[key] then
      return nil, label .. " contains an unknown field"
    end
  end
  return true
end

local function array_length(value, label)
  if type(value) ~= "table" then
    return nil, label .. " must be an array"
  end
  local count = 0
  local maximum = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
      return nil, label .. " must be a dense array"
    end
    count = count + 1
    maximum = math.max(maximum, key)
  end
  if count ~= maximum then
    return nil, label .. " must be a dense array"
  end
  return count
end

local function profile_components(profile)
  if type(profile) ~= "table" then
    return nil, "managed profile must be an object"
  end
  if profile.schema ~= 1 then
    return nil, "managed profile schema is unsupported"
  end
  if profile.version ~= VERSION then
    return nil, "managed profile version is unsupported"
  end
  local profile_root, root_error = canonical_path(profile.profile_root, "managed profile root")
  if not profile_root then
    return nil, root_error
  end
  if not valid_hex(profile.fingerprint, 64) then
    return nil, "managed profile fingerprint is invalid"
  end
  local backend_state, token = profile_root:match("^(.*)/profiles/([^/]+)$")
  if not backend_state or not valid_hex(token, 32) then
    return nil, "managed profile root has an invalid generation"
  end
  local canonical_backend, backend_error = canonical_path(backend_state, "managed backend state")
  if not canonical_backend then
    return nil, backend_error
  end
  return {
    backend_state = canonical_backend,
    token = token,
    fingerprint = profile.fingerprint,
  }
end

local function validate_rules(value, label)
  local length, length_error = array_length(value, label)
  if not length then
    return nil, length_error
  end
  for index = 1, length do
    local rule = value[index]
    local exact, exact_error =
      exact_keys(rule, { "permission", "pattern", "action" }, label .. " rule")
    if not exact then
      return nil, exact_error
    end
    if
      type(rule.permission) ~= "string"
      or rule.permission == ""
      or #rule.permission > 128
      or has_control(rule.permission)
    then
      return nil, label .. " contains an invalid permission"
    end
    if
      type(rule.pattern) ~= "string"
      or rule.pattern == ""
      or #rule.pattern > 4096
      or has_control(rule.pattern)
    then
      return nil, label .. " contains an invalid pattern"
    end
    if rule.action ~= "allow" and rule.action ~= "ask" and rule.action ~= "deny" then
      return nil, label .. " contains an invalid action"
    end
  end
  return true
end

local function resolve_permission(rules, permission)
  local action
  for _, rule in ipairs(rules) do
    if
      (rule.permission == permission or rule.permission == "*")
      and (rule.pattern == "*" or rule.pattern == PROBE_PATH)
    then
      action = rule.action
    end
  end
  return action
end

local function validate_tool_map(value, label)
  if type(value) ~= "table" then
    return nil, label .. " tools must be an object"
  end
  for name, enabled in pairs(value) do
    if
      type(name) ~= "string"
      or name == ""
      or #name > 128
      or has_control(name)
      or type(enabled) ~= "boolean"
    then
      return nil, label .. " tools are invalid"
    end
  end
  return true
end

local function validate_primary_agent(agent, label)
  local exact, exact_error = exact_keys(agent, { "native", "mode", "tools", "permission" }, label)
  if not exact then
    return nil, exact_error
  end
  if agent.native ~= true or agent.mode ~= "primary" then
    return nil, label .. " native definition changed"
  end
  local tools_ok, tools_error = validate_tool_map(agent.tools, label)
  if not tools_ok then
    return nil, tools_error
  end
  return validate_rules(agent.permission, label .. " permissions")
end

local function validate_hidden_agent(agent, label)
  local exact, exact_error = exact_keys(agent, { "native", "hidden", "tools", "permission" }, label)
  if not exact then
    return nil, exact_error
  end
  if agent.native ~= true or agent.hidden ~= true then
    return nil, label .. " native definition changed"
  end
  if type(agent.tools) ~= "table" then
    return nil, label .. " tools must be an object"
  end
  local expected = {}
  for _, name in ipairs(HIDDEN_TOOLS) do
    expected[name] = true
    if agent.tools[name] ~= false then
      return nil, label .. " exposes an actionable tool"
    end
  end
  for name in pairs(agent.tools) do
    if type(name) ~= "string" or not expected[name] then
      return nil, label .. " tools changed"
    end
  end
  return validate_rules(agent.permission, label .. " permissions")
end

local function primary_rules(edit_action)
  local rules = {
    {
      permission = "edit",
      pattern = "*",
      action = edit_action == "allow" and "deny" or "allow",
    },
    { permission = "edit", pattern = PROBE_PATH, action = edit_action },
  }
  for _, permission in ipairs(RISK_PERMISSIONS) do
    rules[#rules + 1] = { permission = permission, pattern = "*", action = "allow" }
    rules[#rules + 1] = { permission = permission, pattern = PROBE_PATH, action = "ask" }
  end
  for _, permission in ipairs(DENIED_PERMISSIONS) do
    rules[#rules + 1] = { permission = permission, pattern = "*", action = "ask" }
    rules[#rules + 1] = { permission = permission, pattern = PROBE_PATH, action = "deny" }
  end
  return rules
end

local function hidden_tools()
  local tools = {}
  for _, name in ipairs(HIDDEN_TOOLS) do
    tools[name] = false
  end
  return tools
end

local function compatibility_fixture()
  return {
    version = VERSION,
    help = vim.deepcopy(EXPECTED_HELP),
    names = vim.deepcopy(EXPECTED_NAMES),
    agents = {
      build = {
        native = true,
        mode = "primary",
        tools = {},
        permission = primary_rules("allow"),
      },
      plan = {
        native = true,
        mode = "primary",
        tools = {},
        permission = primary_rules("deny"),
      },
      compaction = {
        native = true,
        hidden = true,
        tools = hidden_tools(),
        permission = { { permission = "*", pattern = "*", action = "deny" } },
      },
      summary = {
        native = true,
        hidden = true,
        tools = hidden_tools(),
        permission = { { permission = "*", pattern = "*", action = "deny" } },
      },
      title = {
        native = true,
        hidden = true,
        tools = hidden_tools(),
        permission = { { permission = "*", pattern = "*", action = "deny" } },
      },
    },
  }
end

local function replace_last_action(report, agent_name, permission, action)
  local rules = report.agents[agent_name].permission
  for index = #rules, 1, -1 do
    local rule = rules[index]
    if
      (rule.permission == permission or rule.permission == "*")
      and (rule.pattern == "*" or rule.pattern == PROBE_PATH)
    then
      rule.action = action
      return
    end
  end
  error("fixture permission is missing")
end

local function mutate_compatibility(report, mutation)
  local mutations = {
    version = function()
      report.version = "1.18.19"
    end,
    agents = function()
      report.agents.title = nil
    end,
    build_edit = function()
      replace_last_action(report, "build", "edit", "deny")
    end,
    plan_edit = function()
      replace_last_action(report, "plan", "edit", "allow")
    end,
    risk = function()
      replace_last_action(report, "build", "bash", "allow")
    end,
    hidden_tools = function()
      report.agents.compaction.tools.bash = true
    end,
  }
  assert(mutations[mutation], "unknown compatibility fixture mutation")()
end

function M.version()
  return VERSION
end

function M.policy()
  return vim.deepcopy(POLICY)
end

function M.policy_json()
  return POLICY_JSON
end

function M.config()
  return vim.deepcopy(CONFIG)
end

function M.config_json()
  return CONFIG_JSON
end

function M.profile_request(identity, paths, token)
  if type(identity) ~= "table" or not valid_hex(identity.key, 32) then
    return nil, "AI identity key is invalid"
  end
  local root, root_error = canonical_path(identity.root, "AI root")
  if not root then
    return nil, root_error
  end
  if type(paths) ~= "table" then
    return nil, "AI paths must be an object"
  end
  local validated = {}
  for _, field in ipairs({
    "backend_state",
    "global_opencode_data",
    "home_agents",
    "profile_helper",
    "python",
  }) do
    local path, path_error = canonical_path(paths[field], "OpenCode " .. field)
    if not path then
      return nil, path_error
    end
    validated[field] = path
  end
  if not valid_hex(token, 32) then
    return nil, "OpenCode profile token is invalid"
  end
  return {
    schema = 1,
    token = token,
    identity_key = identity.key,
    root = root,
    backend_state = validated.backend_state,
    global_auth = validated.global_opencode_data .. "/auth.json",
    user_agents = validated.home_agents,
    repo_agents = root .. "/AGENTS.md",
    version = VERSION,
    config_json = CONFIG_JSON,
    policy_json = POLICY_JSON,
  }
end

function M.profile_reference(profile)
  local components, components_error = profile_components(profile)
  if not components then
    return nil, components_error
  end
  return {
    token = components.token,
    fingerprint = components.fingerprint,
    version = VERSION,
  }
end

function M.environment(profile, password)
  local components, components_error = profile_components(profile)
  if not components then
    return nil, components_error
  end
  if not valid_hex(password, 32) then
    return nil, "OpenCode server password is invalid"
  end
  local backend_state = components.backend_state
  return {
    OPENCODE_DISABLE_AUTOUPDATE = "true",
    OPENCODE_DISABLE_CLAUDE_CODE = "true",
    OPENCODE_DISABLE_EXTERNAL_SKILLS = "true",
    OPENCODE_DISABLE_LSP_DOWNLOAD = "true",
    OPENCODE_DISABLE_PROJECT_CONFIG = "true",
    OPENCODE_PERMISSION = POLICY_JSON,
    OPENCODE_PURE = "true",
    OPENCODE_SERVER_PASSWORD = password,
    OPENCODE_SERVER_USERNAME = "opencode",
    XDG_CACHE_HOME = backend_state .. "/xdg-cache",
    XDG_CONFIG_HOME = backend_state .. "/xdg-config",
    XDG_DATA_HOME = backend_state .. "/xdg-data",
    XDG_STATE_HOME = backend_state .. "/xdg-state",
  }
end

function M.validate_compatibility(report)
  if type(report) ~= "table" then
    return nil, "OpenCode compatibility report must be an object"
  end
  local encoded_ok, encoded = pcall(vim.json.encode, report)
  if not encoded_ok or type(encoded) ~= "string" then
    return nil, "OpenCode compatibility report is not JSON-compatible"
  end
  if #encoded > MAX_REPORT_BYTES then
    return nil, "OpenCode compatibility report exceeds the size limit"
  end

  local exact, exact_error =
    exact_keys(report, { "version", "help", "names", "agents" }, "OpenCode report")
  if not exact then
    return nil, exact_error
  end
  if report.version ~= VERSION then
    return nil, "OpenCode compatibility version is unsupported"
  end

  local help_ok, help_error =
    exact_keys(report.help, { "root", "serve", "attach" }, "OpenCode help")
  if not help_ok then
    return nil, help_error
  end
  for _, name in ipairs({ "root", "serve", "attach" }) do
    local length, length_error = array_length(report.help[name], "OpenCode " .. name .. " help")
    if not length then
      return nil, length_error
    end
    if
      length ~= #EXPECTED_HELP[name] or not vim.deep_equal(report.help[name], EXPECTED_HELP[name])
    then
      return nil, "OpenCode command form changed"
    end
  end

  local name_count, names_error = array_length(report.names, "OpenCode agent names")
  if not name_count then
    return nil, names_error
  end
  local seen = {}
  for index = 1, name_count do
    local name = report.names[index]
    if type(name) ~= "string" or name == "" or #name > 128 or has_control(name) then
      return nil, "OpenCode agent name is invalid"
    end
    if seen[name] then
      return nil, "OpenCode agent names contain a duplicate"
    end
    seen[name] = true
  end
  if name_count ~= #EXPECTED_NAMES or not vim.deep_equal(report.names, EXPECTED_NAMES) then
    return nil, "OpenCode agent set changed"
  end

  local agents_ok, agents_error = exact_keys(report.agents, EXPECTED_NAMES, "OpenCode agents")
  if not agents_ok then
    return nil, agents_error
  end
  for _, name in ipairs({ "build", "plan" }) do
    local agent_ok, agent_error = validate_primary_agent(report.agents[name], "OpenCode " .. name)
    if not agent_ok then
      return nil, agent_error
    end
  end
  for _, name in ipairs({ "compaction", "summary", "title" }) do
    local agent_ok, agent_error = validate_hidden_agent(report.agents[name], "OpenCode " .. name)
    if not agent_ok then
      return nil, agent_error
    end
  end

  if resolve_permission(report.agents.build.permission, "edit") ~= "allow" then
    return nil, "OpenCode Build edit behavior changed"
  end
  if resolve_permission(report.agents.plan.permission, "edit") ~= "deny" then
    return nil, "OpenCode Plan edit behavior changed"
  end
  for _, name in ipairs({ "build", "plan" }) do
    local rules = report.agents[name].permission
    for _, permission in ipairs(RISK_PERMISSIONS) do
      if resolve_permission(rules, permission) ~= "ask" then
        return nil, "OpenCode approval behavior changed"
      end
    end
    for _, permission in ipairs(DENIED_PERMISSIONS) do
      if resolve_permission(rules, permission) ~= "deny" then
        return nil, "OpenCode delegation behavior changed"
      end
    end
  end
  return true
end

M._test = {
  compatibility_fixture = compatibility_fixture,
  mutate_compatibility = mutate_compatibility,
}

return M
