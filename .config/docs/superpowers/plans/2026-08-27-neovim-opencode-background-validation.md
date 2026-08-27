# Neovim OpenCode Background Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the strict managed OpenCode compatibility gate while running its twelve Bubblewrap probes asynchronously, accepting only three audited quiescent lock forms, and exposing one deduplicated content-free opening intent.

**Architecture:** A focused `opencode_validation.lua` controller owns the executable-keyed state machine, fixed command sequence, sanitized report parsing, observers, deadlines, and one queued identity token.
The existing backend registry retains executable validation, private probe trees, Bubblewrap construction, streamed output bounds, artifact inspection, and guarded cleanup, but gains an asynchronous callback path that never calls `wait()` during ordinary Neovim use.
The OpenCode adapter consumes immediate controller snapshots and refuses launch unless the controller has a current successful report.

**Tech Stack:** Neovim 0.12 Lua, `vim.system`, `vim.uv`, Bubblewrap 0.11 or newer, OpenCode `1.18.18`, Stylua, headless Neovim tests, POSIX shell, and the existing Python standard-library harnesses.

## Global Constraints

- Work only in `/tmp/dotfiles-nvim-ai-cli-companion` on branch `agent/nvim-ai-cli-companion` from the frozen implementation parent `e75817f9beabe5676a10d5f1084919907be16cd7` and approved design commit `d7c4b401415758b1d6bf7cea20023fd24e669ebd`.
- Treat `.config/docs/superpowers/specs/2026-08-27-neovim-opencode-background-validation-design.md` as the controlling specification when an older plan conflicts with this plan.
- Preserve the strict compatibility gate before every managed OpenCode launch.
- Support only the canonical installed OpenCode executable whose normalized version is exactly `1.18.18`.
- Keep setup passive and do not resolve a project, create AI state, run a compatibility probe, or launch a process during module load or setup.
- Run the twelve compatibility commands in their fixed order and never run two OpenCode or Bubblewrap probes concurrently.
- Use an absolute five-second deadline for each compatibility command and a sixty-second execution ceiling for the twelve-command sequence.
- Use streaming stdout and stderr callbacks with the existing one-mebibyte stdout cap and 65536-byte stderr cap.
- Never call `SystemObj:wait()` on the Neovim thread except for the one exit-only drain bounded to at most 2000 milliseconds after `VimLeavePre` has committed to shutdown.
- Keep `--unshare-net`, the read-only root, private `/tmp`, the exact synthetic home and XDG mounts, the exact clear environment, and every current executable revalidation.
- Accept only an absent lock root, an empty current-user-owned mode-0700 lock root, or the complete audited fixed lock directory with exact mode-0600 `heartbeat` and `meta.json` files.
- Require two identical allowed lock snapshots separated by 50 milliseconds and stop settling after 1000 milliseconds.
- Treat a strict partial audited lock as transient only during settling, and reject every unknown name, extra entry, symlink, special file, unsafe owner or mode, invalid content, oversize, replacement race, or traversal error immediately.
- Do not weaken any non-lock artifact, SQLite, log, bootstrap, repository, cache, configuration, ownership, mode, type, content, or side-effect check.
- Keep at most one in-flight validation for one stable canonical executable metadata identity and at most one queued content-free companion identity.
- Retain no queued prompt text, visual selection, cursor location, context path, context bytes, credentials, raw stdout, raw stderr, or private artifact content.
- Cache only a fully successful sanitized report keyed by canonical executable path and the complete existing metadata identity.
- Do not cache a failure, retry automatically, fall back to an unconfined command, or contact a provider.
- Clear the queued opening on failure, cancellation, close, backend switch, shutdown, or executable drift.
- Keep Codex, Claude, managed profile construction, credential filtering, launcher confinement, and provider behavior outside this repair unchanged.
- Set `NVIM_LOG_FILE=/dev/null` for every headless Neovim command.
- Run the real managed-Lua OpenCode gate exactly once without retry after deterministic tests pass.
- Run the real managed-Lua gate and the hostile-HOME shell harness serially, never concurrently.
- Use exact current-user-owned mode-0700 test roots, prove their processes are gone, inspect them before cleanup, and leave a root intact if process exit cannot be proven.
- Stop implementation at an uncommitted candidate for fresh specification and quality reviews.
- Do not stage or commit implementation bytes until Linear grants a separate exact Git-metadata lease after both reviews pass.
- Do not create another ordinary Linear issue for this repair.

---

## File Map

### Focused compatibility controller

- Create `.config/nvim/lua/ai/backends/opencode_validation.lua`.
  This module owns the fixed twelve-command description, result parsing, state machine, sixty-second ceiling, observers, success cache, cancellation generation, and one queued identity token.
- Create `.config/nvim/tests/ai_opencode_validation.lua`.
  This deterministic suite owns UI responsiveness, sequencing, deadlines, deduplication, queuing, cancellation, late callbacks, cache invalidation, bounded notifications, and controller shutdown.

### Existing hardened probe boundary

- Modify `.config/nvim/lua/ai/backends/init.lua` around `bounded_system`, `read_only_probe`, the artifact inspector, the synchronous `opencode_compatibility` block, runtime dependencies, registry construction, public methods, and `_test` exports.
  This file continues to own exact Bubblewrap construction, private probe roots, file-descriptor-bound artifact validation, executable metadata, runtime dependency wiring, and the registry facade.
- Modify `.config/nvim/tests/ai_opencode_managed.lua` around the process-boundary tests, compatibility tests, artifact fixtures, lock mutations, and final real installed-binary gate.
  This suite owns the exact OpenCode environment and argv, async stream bounds, lock-form security, artifact regression coverage, cleanup, and the one real provider-free twelve-command sequence.

### Adapter-facing health and launch safety

- Modify `.config/nvim/lua/ai/backends/opencode.lua` in `build()` and `adapter:health()`.
  The adapter reads compatibility state without starting validation and refuses profile preparation or launch unless the current executable has a ready sanitized report.
- Modify `.config/nvim/tests/ai_backends.lua` in the injected registry fixture, OpenCode launch assertions, health assertions, and failure matrix.
  This suite owns passive registry construction, immediate health states, no synchronous gate invocation, ready-only capabilities, authentication ordering, and launch refusal before readiness.

### Required unchanged regressions

- Verify `.config/nvim/tests/nvim-ai-opencode-compat.sh` without changing it unless a focused failing assertion proves that the approved background-validation contract requires a harness correction.
- Verify `.config/nvim/tests/nvim_ai_opencode_profile.py`, `.config/nvim/tests/nvim_ai_launch.py`, `.config/nvim/tests/ai_sandbox.lua`, and `.config/nvim/tests/nvim-ai-sandbox.sh` without changing them.
- Do not modify the frozen approved design specification during implementation.

## Shared Interfaces

Use these exact trusted Lua shapes across all tasks:

```lua
---@class AiOpenCodeExecutableIdentity
---@field installed boolean
---@field executable string
---@field metadata string

---@class AiOpenCodeCompatibilitySnapshot
---@field state "not_checked"|"checking"|"ready"|"failed"
---@field installed boolean
---@field executable string
---@field version string
---@field category string
---@field queued boolean

---@class AiOpenCodeCompatibilityRequest
---@field reason "picker"|"open"
---@field identity_key? string

---@class AiOpenCodeProbeCommand
---@field name string
---@field arguments string[]
---@field semantic boolean

---@class AiOpenCodeProbeHandle
---@field cancel fun(self: AiOpenCodeProbeHandle, reason: string)
---@field shutdown_drain fun(self: AiOpenCodeProbeHandle, timeout_ms: integer): boolean
```

`opencode_validation.new(deps) -> controller` consumes these exact dependency methods:

```lua
deps.identify() -> AiOpenCodeExecutableIdentity
deps.start_probe(identity, command, on_complete) -> AiOpenCodeProbeHandle|nil, string|nil
deps.now() -> integer
deps.defer(callback, delay_ms) -> timer_handle
deps.schedule(callback)
deps.notify(message, level)
deps.warn_level -> integer
```

`on_complete(result, category)` is called exactly once after the owned process has exited and the exact private tree has either been safely cleaned or deliberately retained.
`result` is a bounded `{ code, signal, stdout, stderr, stdout_overflow, stderr_overflow, system_error }` table only on a completed probe boundary.
`category` is empty on success or exactly one of `unavailable`, `timeout`, `output-overflow`, `executable-drift`, `probe-failure`, `artifact-rejection`, `parse-failure`, `cancellation`, or `cleanup-failure`.

The controller produces these exact methods:

```lua
controller:snapshot() -> AiOpenCodeCompatibilitySnapshot
controller:report() -> table|nil
controller:ensure(request: AiOpenCodeCompatibilityRequest) -> AiOpenCodeCompatibilitySnapshot|nil, string|nil
controller:take_open(identity_key: string) -> boolean
controller:cancel(reason: "close"|"backend-switch"|"shutdown"|"executable-drift")
controller:subscribe(callback) -> unsubscribe|nil, string|nil
controller:shutdown(exit_committed: boolean) -> boolean
controller:debug_state() -> table
```

The backend registry exposes the controller without exposing private metadata or probe output:

```lua
registry:opencode_compatibility() -> AiOpenCodeCompatibilitySnapshot
registry:ensure_opencode_compatibility(request) -> AiOpenCodeCompatibilitySnapshot|nil, string|nil
registry:take_opencode_open(identity_key) -> boolean
registry:cancel_opencode_compatibility(reason)
registry:subscribe_opencode_compatibility(callback) -> unsubscribe|nil, string|nil
registry:shutdown(exit_committed: boolean) -> boolean
```

The future picker calls `ensure_opencode_compatibility({ reason = "picker" })` only from `not_checked`.
An explicit OpenCode open or prompt calls `ensure_opencode_compatibility({ reason = "open", identity_key = identity.key })`.
The future coordinator consumes `take_opencode_open(identity.key)` after a `ready` notification and then re-enters the ordinary OpenCode opening transaction without retained prompt or context data.
The future close and backend-switch paths call cancellation, ordinary teardown calls `shutdown(false)`, and `VimLeavePre` alone calls `shutdown(true)`.
The future status and `:checkhealth nvim-ai` paths call only `opencode_compatibility()` and never call `ensure_opencode_compatibility()`.

### Task 1: Isolate the fixed command contract and sanitized parser

**Files:**

- Create: `.config/nvim/lua/ai/backends/opencode_validation.lua`
- Create: `.config/nvim/tests/ai_opencode_validation.lua`
- Modify: `.config/nvim/lua/ai/backends/init.lua:1441-1750`
- Inspect: `.config/nvim/tests/ai_opencode_managed.lua:1482-1835`

**Interfaces:**

- Consumes: the existing exact `valid_probe_result()` behavior and `managed.validate_compatibility(report)`.
- Produces: `validation.commands() -> AiOpenCodeProbeCommand[]`, the internal `new_parser()` incremental parser, the temporary production entry `validation.parse_results(results) -> report|nil, string|nil`, and matching `_test` parser exports.

- [ ] **Step 1: Write the failing command-order and parser tests**

Create `.config/nvim/tests/ai_opencode_validation.lua` with the local `eq()` helper used by the other AI suites, require `ai.backends.opencode_validation`, build bounded result fixtures from `managed._test.compatibility_fixture()`, and assert this exact command list:

```lua
local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local managed = require("ai.backends.opencode_managed")
local validation = require("ai.backends.opencode_validation")

eq(validation.commands(), {
  { name = "version", arguments = { "--version" }, semantic = false },
  { name = "root_help", arguments = { "--help" }, semantic = false },
  { name = "serve_help", arguments = { "serve", "--help" }, semantic = false },
  { name = "attach_help", arguments = { "attach", "--help" }, semantic = false },
  { name = "names", arguments = { "--pure", "agent", "list" }, semantic = true },
  { name = "build", arguments = { "--pure", "debug", "agent", "build" }, semantic = true },
  { name = "plan", arguments = { "--pure", "debug", "agent", "plan" }, semantic = true },
  { name = "compaction", arguments = { "--pure", "debug", "agent", "compaction" }, semantic = true },
  { name = "summary", arguments = { "--pure", "debug", "agent", "summary" }, semantic = true },
  { name = "title", arguments = { "--pure", "debug", "agent", "title" }, semantic = true },
  { name = "general", arguments = { "--pure", "debug", "agent", "general" }, semantic = true },
  { name = "explore", arguments = { "--pure", "debug", "agent", "explore" }, semantic = true },
}, "fixed OpenCode validation order")

local primary_tools = {
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

local function fixture_results()
  local report = managed._test.compatibility_fixture()
  local results = {
    version = { code = 0, signal = 0, stdout = "1.18.18\n", stderr = "" },
    root_help = { code = 0, signal = 0, stdout = "", stderr = "--pure serve attach" },
    serve_help = { code = 0, signal = 0, stdout = "", stderr = "--hostname --port" },
    attach_help = {
      code = 0,
      signal = 0,
      stdout = "",
      stderr = "--dir --session OPENCODE_SERVER_PASSWORD",
    },
    names = {
      code = 0,
      signal = 0,
      stdout = table.concat({
        "build (primary)",
        "compaction (subagent)",
        "plan (primary)",
        "summary (subagent)",
        "title (subagent)",
      }, "\n") .. "\n",
      stderr = "",
    },
  }
  for _, name in ipairs({ "build", "plan", "compaction", "summary", "title" }) do
    local agent = vim.deepcopy(report.agents[name])
    if name == "build" or name == "plan" then
      agent.tools = vim.deepcopy(primary_tools)
    end
    results[name] = {
      code = 0,
      signal = 0,
      stdout = vim.json.encode(agent) .. "\n",
      stderr = "",
    }
  end
  for _, name in ipairs({ "general", "explore" }) do
    results[name] = {
      code = 1,
      signal = 0,
      stdout = "",
      stderr = "Agent "
        .. name
        .. " not found, run 'opencode agent list' to get an agent list\n",
    }
  end
  return results, report
end
```

Assert that `parse_results(fixture_results())` returns the audited sanitized report and that mutations for a prefixed version, missing help flag, duplicate agent name, malformed agent JSON, changed primary tools, unexpected disabled agent, forbidden side-effect text, overflow marker, nonzero signal, oversized stdout, and oversized stderr all return `nil, "parse-failure"` without the canary bytes appearing in the category.
Drive `_test.new_parser()` one command at a time, mutate and then drop each source result after `accept()`, and prove through `debug_state()` that the parser retains only bounded sanitized counts and fields, never stdout, stderr, or a raw result table.
End the Task 1 test with exact line `AI OpenCode background validation parser assertions: ok`.

- [ ] **Step 2: Run the focused test and verify the missing module failure**

Run:

```bash
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exit nonzero with `module 'ai.backends.opencode_validation' not found`.

- [ ] **Step 3: Create the fixed command table and pure parser**

Create `.config/nvim/lua/ai/backends/opencode_validation.lua` with immutable-copy helpers and the exact command table shown in Step 1.
Move the result-validation portion of the existing `opencode_compatibility()` function into an incremental parser that consumes and discards each command's bounded streams before the next command starts.
Keep `parse_results(results)` only as the pure test and temporary synchronous-call adapter over that same parser.
Use this complete parser implementation:

```lua
local MAX_HELP_BYTES = 65536
local MAX_REPORT_BYTES = 1024 * 1024
local FORBIDDEN_EVIDENCE = {
  "installing configuration dependenc",
  "downloading plugin",
  "loading plugin",
  "checking for update",
  "downloading lsp",
  "network request",
}
local HELP_REQUIREMENTS = {
  root_help = { "--pure", "serve", "attach" },
  serve_help = { "--hostname", "--port" },
  attach_help = { "--dir", "--session", "OPENCODE_SERVER_PASSWORD" },
}
local AGENT_COMMANDS = {
  build = true,
  plan = true,
  compaction = true,
  summary = true,
  title = true,
}
local OPENCODE_PRIMARY_TOOLS = {
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

local function valid_result(result)
  return type(result) == "table"
    and type(result.code) == "number"
    and type(result.signal) == "number"
    and result.signal == 0
    and type(result.stdout) == "string"
    and type(result.stderr) == "string"
    and result.stdout_overflow ~= true
    and result.stderr_overflow ~= true
    and result.system_error ~= true
    and #result.stdout <= MAX_REPORT_BYTES
    and #result.stderr <= MAX_HELP_BYTES
end

local function has_forbidden_evidence(result)
  local output = (result.stdout .. "\n" .. result.stderr):lower()
  for _, evidence in ipairs(FORBIDDEN_EVIDENCE) do
    if output:find(evidence, 1, true) then
      return true
    end
  end
  return false
end

local function parse_names(result)
  if result.code ~= 0 or result.stderr ~= "" or #result.stdout > MAX_HELP_BYTES then
    return nil
  end
  local names = {}
  local seen = {}
  for line in (result.stdout:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      local name = line:match("^([%w_-]+) %([%w_-]+%)$")
      if not name or seen[name] then
        return nil
      end
      seen[name] = true
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

local function parse_agent(name, result)
  if result.code ~= 0 or result.stderr ~= "" then
    return nil
  end
  local decoded_ok, decoded = pcall(vim.json.decode, result.stdout)
  if not decoded_ok or type(decoded) ~= "table" then
    return nil
  end
  local agent
  if name == "build" or name == "plan" then
    if not vim.deep_equal(decoded.tools, OPENCODE_PRIMARY_TOOLS) then
      return nil
    end
    agent = {
      native = decoded.native,
      mode = decoded.mode,
      tools = {},
      permission = decoded.permission,
    }
  else
    agent = {
      native = decoded.native,
      hidden = decoded.hidden,
      tools = decoded.tools,
      permission = decoded.permission,
    }
  end
  local encoded_ok, encoded = pcall(vim.json.encode, agent)
  if not encoded_ok or type(encoded) ~= "string" or #encoded > MAX_REPORT_BYTES then
    return nil
  end
  return agent
end

local function valid_disabled(name, result)
  local expected = "Agent "
    .. name
    .. " not found, run 'opencode agent list' to get an agent list"
  local output = result.stderr ~= "" and result.stderr or result.stdout
  return result.code ~= 0
    and not (result.stderr ~= "" and result.stdout ~= "")
    and (output == expected or output == expected .. "\n")
end

local function new_parser()
  local state = {
    index = 0,
    version = false,
    names = nil,
    agents = {},
    finished = false,
  }
  local parser = {}

  function parser:accept(command, result)
    local expected = COMMANDS[state.index + 1]
    if
      state.finished
      or not expected
      or not vim.deep_equal(command, expected)
      or not valid_result(result)
      or has_forbidden_evidence(result)
    then
      return nil, "parse-failure"
    end

    local name = expected.name
    if name == "version" then
      if
        result.code ~= 0
        or result.stderr ~= ""
        or (result.stdout ~= "1.18.18" and result.stdout ~= "1.18.18\n")
      then
        return nil, "parse-failure"
      end
      state.version = true
    elseif HELP_REQUIREMENTS[name] then
      if result.code ~= 0 or result.stdout ~= "" or result.stderr == "" then
        return nil, "parse-failure"
      end
      for _, requirement in ipairs(HELP_REQUIREMENTS[name]) do
        if not result.stderr:find(requirement, 1, true) then
          return nil, "parse-failure"
        end
      end
    elseif name == "names" then
      state.names = parse_names(result)
      if not state.names then
        return nil, "parse-failure"
      end
    elseif AGENT_COMMANDS[name] then
      state.agents[name] = parse_agent(name, result)
      if not state.agents[name] then
        return nil, "parse-failure"
      end
    elseif not valid_disabled(name, result) then
      return nil, "parse-failure"
    end
    state.index = state.index + 1
    return true
  end

  function parser:finish()
    if state.finished or state.index ~= #COMMANDS or state.version ~= true then
      return nil, "parse-failure"
    end
    local report = {
      version = "1.18.18",
      help = {
        root = { "--pure", "serve", "attach" },
        serve = { "--hostname", "--port" },
        attach = { "--dir", "--session", "OPENCODE_SERVER_PASSWORD" },
      },
      names = vim.deepcopy(state.names),
      agents = vim.deepcopy(state.agents),
    }
    local managed = require("ai.backends.opencode_managed")
    local compatible_ok, compatible = pcall(managed.validate_compatibility, report)
    if not compatible_ok or not compatible then
      return nil, "parse-failure"
    end
    state.finished = true
    state.names = nil
    state.agents = {}
    return vim.deepcopy(report)
  end

  function parser:debug_state()
    return {
      index = state.index,
      version = state.version,
      name_count = type(state.names) == "table" and #state.names or 0,
      agent_count = vim.tbl_count(state.agents),
      finished = state.finished,
    }
  end

  return parser
end

local function parse_results(results)
  if type(results) ~= "table" then
    return nil, "parse-failure"
  end
  local parser = new_parser()
  for _, command in ipairs(COMMANDS) do
    local accepted, category = parser:accept(command, results[command.name])
    if not accepted then
      return nil, category
    end
  end
  return parser:finish()
end

function M.commands()
  return vim.deepcopy(COMMANDS)
end

M.parse_results = parse_results
M._test = {
  new_parser = new_parser,
  parse_results = parse_results,
}
```

- [ ] **Step 4: Replace the old inline parser call site**

In `init.lua`, require the new module only inside the OpenCode compatibility path and replace the removed inline parser block with:

```lua
local validation = require("ai.backends.opencode_validation")
local report, parse_error = validation.parse_results(results)
if not report then
  return nil, parse_error
end
```

Keep the executable revalidation, exact metadata comparison, success-cache write, and return after this block for now.
Do not change the synchronous control flow until Task 4 has a failing responsiveness test.

- [ ] **Step 5: Run the pure parser tests without a real process**

Run:

```bash
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exit `0` with exact line `AI OpenCode background validation parser assertions: ok` and without starting OpenCode or Bubblewrap.
Do not run `ai_opencode_managed.lua` yet because its frozen form contains several real OpenCode probes that Task 6 must consolidate into one sequence.

- [ ] **Step 6: Record an uncommitted checkpoint**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check
git -C /tmp/dotfiles-nvim-ai-cli-companion status --short
```

Expected: `diff --check` is silent, only the six authorized implementation paths plus this already committed plan path can eventually appear, and no implementation byte is staged or committed.

### Task 2: Build the executable-keyed asynchronous controller

**Files:**

- Modify: `.config/nvim/lua/ai/backends/opencode_validation.lua`
- Modify: `.config/nvim/tests/ai_opencode_validation.lua`

**Interfaces:**

- Consumes: `validation.commands()`, the module-local `new_parser()`, and `validation._test.parse_results(results)` from Task 1.
- Produces: every `controller` method and snapshot field listed in Shared Interfaces.

- [ ] **Step 1: Add the end-user responsiveness reproduction**

Append a deterministic harness that stores each `start_probe` completion instead of completing it, advances a real Neovim timer, and forbids any process wait:

```lua
local pending = {}
local starts = {}
local wait_calls = 0
local notifications = {}
local metadata = "1:2:493:0:3:4:5:6:7"

local controller = validation._test.new({
  identify = function()
    return { installed = true, executable = "/usr/bin/opencode", metadata = metadata }
  end,
  start_probe = function(identity, command, complete)
    starts[#starts + 1] = { identity = vim.deepcopy(identity), command = vim.deepcopy(command) }
    pending[#pending + 1] = complete
    return {
      cancel = function() end,
      shutdown_drain = function()
        wait_calls = wait_calls + 1
        return true
      end,
    }
  end,
  now = function()
    return vim.uv.now()
  end,
  defer = vim.defer_fn,
  schedule = vim.schedule,
  notify = function(message)
    notifications[#notifications + 1] = message
  end,
  warn_level = vim.log.levels.WARN,
})

local timer_progressed = false
vim.defer_fn(function()
  timer_progressed = true
end, 10)

eq(controller:ensure({ reason = "open", identity_key = string.rep("a", 32) }).state, "checking", "explicit request starts checking")
assert(vim.wait(250, function()
  return timer_progressed
end, 5), "Neovim timer did not progress while validation remained pending")
eq(controller:snapshot().state, "checking", "delayed probe remains pending")
eq(#starts, 1, "only the first probe starts")
eq(wait_calls, 0, "ordinary validation never enters the exit-only drain")
```

- [ ] **Step 2: Add state, sequencing, queue, and cache tests**

Extend the harness with exact assertions for these transitions:

```lua
eq(validation._test.new_idle_snapshot(), {
  state = "not_checked",
  installed = false,
  executable = "",
  version = "",
  category = "",
  queued = false,
}, "passive initial snapshot")

controller:ensure({ reason = "open", identity_key = string.rep("a", 32) })
controller:ensure({ reason = "open", identity_key = string.rep("a", 32) })
eq(#starts, 1, "repeated OpenCode requests share one sequence")
eq(controller:snapshot().queued, true, "one content-free opening is queued")

local raw_results, expected_report = fixture_results()
for index, command in ipairs(validation.commands()) do
  eq(#pending, 1, command.name .. " is the sole pending command")
  local complete = table.remove(pending, 1)
  complete(vim.deepcopy(raw_results[command.name]), "")
  assert(vim.wait(250, function()
    return index == #validation.commands()
        and controller:snapshot().state == "ready"
      or #starts == index + 1
  end, 5), command.name .. " completion did not advance the sequence")
end
eq(controller:report(), expected_report, "ready report is sanitized")
eq(controller:take_open(string.rep("a", 32)), true, "queued opening is consumed once")
eq(controller:take_open(string.rep("a", 32)), false, "queued opening cannot be replayed")
```

Assert that `starts` has the same fixed order as `validation.commands()`, mutate the first table returned by `report()`, and prove that a second call returns the unmodified report.
A second `ensure({ reason = "picker" })` must start no probe for unchanged metadata.
Change only `metadata`, call `snapshot()`, and require `not_checked`, an empty report, no queued opening, and a new twelve-command sequence on the next explicit request.
Return `nil, "probe-failure"` from one completion twice across two explicit requests and require `failed`, no queued opening, one bounded notification per failed attempt, no automatic retry, and no successful report.
Pass an otherwise valid open request with each extra key `prompt`, `selection`, `line`, `column`, `context_file`, or `credentials` and require a bounded request error, no validation start, and no retained value in `debug_state()`.
While a command is active, change `identify()` to the unavailable identity and issue another explicit request.
Require the active handle to be canceled for executable drift, keep the public state non-ready until its callback proves process exit and cleanup, and prove that the new request cannot replace the cleared queue or publish an early `unavailable` failure.

- [ ] **Step 3: Add cancellation and stale-callback tests**

Use generation-tagged fake handles and assert all of these exact cases:

```lua
local function new_controller_fixture()
  local fixture = {
    metadata = "1:2:493:0:3:4:5:6:7",
    pending = {},
    starts = {},
    cancel_reasons = {},
  }
  fixture.controller = validation._test.new({
    identify = function()
      return {
        installed = true,
        executable = "/usr/bin/opencode",
        metadata = fixture.metadata,
      }
    end,
    start_probe = function(identity, command, complete)
      fixture.starts[#fixture.starts + 1] = {
        identity = vim.deepcopy(identity),
        command = vim.deepcopy(command),
      }
      fixture.pending[#fixture.pending + 1] = complete
      return {
        cancel = function(_, reason)
          fixture.cancel_reasons[#fixture.cancel_reasons + 1] = reason
        end,
        shutdown_drain = function()
          return true
        end,
      }
    end,
    now = vim.uv.now,
    defer = vim.defer_fn,
    schedule = vim.schedule,
    notify = function() end,
    warn_level = vim.log.levels.WARN,
  })
  function fixture:complete(result, category)
    local complete = table.remove(self.pending, 1)
    assert(type(complete) == "function", "fixture has no pending probe")
    complete(result, category)
  end
  return fixture
end

local function cancellation_case(reason)
  local fixture = new_controller_fixture()
  assert(fixture.controller:ensure({
    reason = "open",
    identity_key = string.rep("a", 32),
  }))
  fixture.controller:cancel(reason)
  eq(fixture.cancel_reasons, { reason }, reason .. " cancels one active probe")
  eq(fixture.controller:snapshot().queued, false, reason .. " clears the queued opening")
  fixture:complete(nil, reason == "executable-drift" and "executable-drift" or "cancellation")
  vim.wait(100, function()
    return fixture.controller:snapshot().state ~= "checking"
  end, 5)
  assert(fixture.controller:snapshot().state ~= "ready", reason .. " cannot publish readiness")
end

for _, reason in ipairs({ "close", "backend-switch", "shutdown", "executable-drift" }) do
  cancellation_case(reason)
end
```

For `close` and `backend-switch`, complete the canceled handle with `nil, "cancellation"` and require `not_checked` without a notification.
For executable drift, change the metadata before `snapshot()`, require cancellation, complete the old callback, and prove that it cannot publish `ready` or revive the queue.
For a cleanup failure after cancellation, complete with `nil, "cleanup-failure"` and require `failed` with the exact category `cleanup-failure`.
Register two observers, unsubscribe one, and prove that only the live observer receives fresh deep-copied snapshots.
Attempt a thirty-third observer and require a bounded generic error so observer retention stays bounded.

- [ ] **Step 4: Add five-second and sixty-second deadline tests**

Inject `now()` and `defer()` fakes that record timer callbacks.
Assert that the controller creates exactly one `60000` millisecond sequence timer, does not create per-command timers itself, stops the sequence before launching a thirteenth command, cancels the active handle when the total timer fires, publishes `failed` with category `timeout` only after the probe callback confirms cleanup, and never retries.
Per-command `5000` millisecond enforcement belongs to Task 4's process boundary and must not be duplicated in the controller.

- [ ] **Step 5: Implement the controller state machine**

Add `new(deps)` and keep all mutable state inside one returned controller.
Use this complete state-machine implementation, with `parse_results` and `COMMANDS` from Task 1 in the same module:

```lua
local MAX_OBSERVERS = 32
local SEQUENCE_TIMEOUT_MS = 60000
local VALID_IDENTITY_KEY = "^[0-9a-f]+$"
local VALID_CANCEL_REASON = {
  close = true,
  ["backend-switch"] = true,
  shutdown = true,
  ["executable-drift"] = true,
}
local VALID_FAILURE = {
  unavailable = true,
  timeout = true,
  ["output-overflow"] = true,
  ["executable-drift"] = true,
  ["probe-failure"] = true,
  ["artifact-rejection"] = true,
  ["parse-failure"] = true,
  cancellation = true,
  ["cleanup-failure"] = true,
}

local function idle_snapshot()
  return {
    state = "not_checked",
    installed = false,
    executable = "",
    version = "",
    category = "",
    queued = false,
  }
end

local function valid_identity(identity)
  return type(identity) == "table"
    and type(identity.installed) == "boolean"
    and type(identity.executable) == "string"
    and type(identity.metadata) == "string"
    and ((not identity.installed and identity.executable == "" and identity.metadata == "")
      or (identity.installed and identity.executable:sub(1, 1) == "/" and identity.metadata ~= ""))
end

local function same_identity(left, right)
  return valid_identity(left)
    and valid_identity(right)
    and left.installed == right.installed
    and left.executable == right.executable
    and left.metadata == right.metadata
end

local function stop_timer(timer)
  if not timer then
    return
  end
  if type(timer.stop) == "function" then
    pcall(timer.stop, timer)
  end
  local closing = false
  if type(timer.is_closing) == "function" then
    local ok, value = pcall(timer.is_closing, timer)
    closing = ok and value == true
  end
  if not closing and type(timer.close) == "function" then
    pcall(timer.close, timer)
  end
end

local function new(deps)
  assert(type(deps) == "table", "OpenCode validation dependencies are required")
  for _, name in ipairs({ "identify", "start_probe", "now", "defer", "schedule", "notify" }) do
    assert(type(deps[name]) == "function", "OpenCode validation dependency is invalid: " .. name)
  end
  local state = {
    phase = "unknown",
    identity = nil,
    parser = nil,
    report = nil,
    category = "",
    generation = 0,
    active = nil,
    sequence_timer = nil,
    queued_identity = nil,
    observers = {},
    observer_count = 0,
    next_observer = 0,
    stopped = false,
    cancelling = nil,
    command_index = 0,
    sequence_started_at = 0,
  }
  local controller = {}
  local start_next

  local function current_identity()
    local ok, identity = pcall(deps.identify)
    if not ok or not valid_identity(identity) then
      return { installed = false, executable = "", metadata = "" }
    end
    return vim.deepcopy(identity)
  end

  local function raw_snapshot()
    local identity = state.identity or { installed = false, executable = "", metadata = "" }
    return {
      state = state.phase == "unknown" and "not_checked" or state.phase,
      installed = identity.installed,
      executable = identity.executable,
      version = state.phase == "ready" and "1.18.18" or "",
      category = state.phase == "failed" and state.category or "",
      queued = state.queued_identity ~= nil,
    }
  end

  local function publish(notify_failure)
    local published = raw_snapshot()
    local generation = state.generation
    for key, callback in pairs(state.observers) do
      local copy = vim.deepcopy(published)
      deps.schedule(function()
        if
          not state.stopped
          and generation == state.generation
          and state.observers[key] == callback
        then
          pcall(callback, copy)
        end
      end)
    end
    if notify_failure and published.state == "failed" then
      local category = VALID_FAILURE[published.category] and published.category or "probe-failure"
      deps.schedule(function()
        if not state.stopped and generation == state.generation then
          pcall(
            deps.notify,
            "managed OpenCode validation failed: " .. category,
            deps.warn_level
          )
        end
      end)
    end
  end

  local function clear_sequence_timer()
    stop_timer(state.sequence_timer)
    state.sequence_timer = nil
  end

  local function reset(identity)
    clear_sequence_timer()
    state.generation = state.generation + 1
    state.phase = "unknown"
    state.identity = vim.deepcopy(identity)
    state.parser = nil
    state.report = nil
    state.category = ""
    state.active = nil
    state.cancelling = nil
    state.command_index = 0
    state.sequence_started_at = 0
    state.queued_identity = nil
  end

  local function fail(category)
    clear_sequence_timer()
    state.phase = "failed"
    state.parser = nil
    state.report = nil
    state.category = VALID_FAILURE[category] and category or "probe-failure"
    state.active = nil
    state.cancelling = nil
    state.command_index = 0
    state.sequence_started_at = 0
    state.queued_identity = nil
    publish(true)
  end

  local function cancel_active(outcome, category, identity)
    state.queued_identity = nil
    state.cancelling = {
      outcome = outcome,
      category = category,
      identity = vim.deepcopy(identity or state.identity),
    }
    publish(false)
    local slot = state.active
    if slot then
      slot.cancel_reason = category
      if slot.handle and type(slot.handle.cancel) == "function" then
        pcall(slot.handle.cancel, slot.handle, category)
      end
      return
    end
    if outcome == "failed" then
      fail(category)
    else
      reset(identity or current_identity())
      publish(false)
    end
  end

  local function reconcile_identity()
    local identity = current_identity()
    if not state.identity then
      state.identity = vim.deepcopy(identity)
      return identity
    end
    if same_identity(identity, state.identity) then
      return identity
    end
    if state.phase == "checking" and not state.cancelling then
      cancel_active("unknown", "executable-drift", identity)
    else
      reset(identity)
      publish(false)
    end
    return identity
  end

  local function complete_probe(slot, result, category)
    if
      state.stopped
      or state.generation ~= slot.generation
      or state.active ~= slot
    then
      return
    end
    state.active = nil

    if state.cancelling then
      local cancellation = state.cancelling
      if category == "cleanup-failure" or category == "artifact-rejection" then
        fail(category)
      elseif cancellation.outcome == "failed" then
        fail(cancellation.category)
      else
        reset(cancellation.identity)
        publish(false)
      end
      return
    end

    if category ~= nil and category ~= "" then
      fail(category)
      return
    end
    if type(result) ~= "table" then
      fail("probe-failure")
      return
    end
    local parser = state.parser
    if type(parser) ~= "table" or type(parser.accept) ~= "function" then
      fail("parse-failure")
      return
    end
    local accept_ok, accepted = pcall(parser.accept, parser, slot.command, result)
    if not accept_ok or not accepted then
      fail("parse-failure")
      return
    end
    state.command_index = state.command_index + 1
    start_next()
  end

  local function finish_success()
    local parser = state.parser
    if type(parser) ~= "table" or type(parser.finish) ~= "function" then
      fail("parse-failure")
      return
    end
    local parse_ok, report = pcall(parser.finish, parser)
    if not parse_ok or not report then
      fail("parse-failure")
      return
    end
    local identity = current_identity()
    if not same_identity(identity, state.identity) then
      cancel_active("unknown", "executable-drift", identity)
      return
    end
    clear_sequence_timer()
    state.phase = "ready"
    state.parser = nil
    state.report = vim.deepcopy(report)
    state.category = ""
    state.active = nil
    state.cancelling = nil
    state.command_index = 0
    state.sequence_started_at = 0
    publish(false)
  end

  start_next = function()
    if state.stopped or state.phase ~= "checking" or state.cancelling then
      return
    end
    if deps.now() - state.sequence_started_at >= SEQUENCE_TIMEOUT_MS then
      cancel_active("failed", "timeout", state.identity)
      return
    end
    local identity = current_identity()
    if not same_identity(identity, state.identity) then
      cancel_active("unknown", "executable-drift", identity)
      return
    end
    local command = COMMANDS[state.command_index + 1]
    if not command then
      finish_success()
      return
    end

    local slot = {
      generation = state.generation,
      command = vim.deepcopy(command),
      handle = nil,
      cancel_reason = nil,
    }
    state.active = slot
    local ok, handle, start_error = pcall(
      deps.start_probe,
      vim.deepcopy(state.identity),
      vim.deepcopy(command),
      function(result, category)
        deps.schedule(function()
          complete_probe(slot, result, category)
        end)
      end
    )
    if
      ok
      and type(handle) == "table"
      and type(handle.cancel) == "function"
      and type(handle.shutdown_drain) == "function"
    then
      if state.active == slot then
        slot.handle = handle
        if slot.cancel_reason and type(handle.cancel) == "function" then
          pcall(handle.cancel, handle, slot.cancel_reason)
        end
      end
      return
    end
    local category = ok and start_error or handle
    deps.schedule(function()
      complete_probe(slot, nil, VALID_FAILURE[category] and category or "probe-failure")
    end)
  end

  local function start_sequence(identity)
    state.generation = state.generation + 1
    state.phase = "checking"
    state.identity = vim.deepcopy(identity)
    state.parser = new_parser()
    state.report = nil
    state.category = ""
    state.active = nil
    state.cancelling = nil
    state.command_index = 0
    state.sequence_started_at = deps.now()
    local generation = state.generation
    state.sequence_timer = deps.defer(function()
      deps.schedule(function()
        if
          not state.stopped
          and state.phase == "checking"
          and state.generation == generation
          and not state.cancelling
        then
          cancel_active("failed", "timeout", state.identity)
        end
      end)
    end, SEQUENCE_TIMEOUT_MS)
    publish(false)
    start_next()
  end

  function controller:snapshot()
    if state.stopped then
      return idle_snapshot()
    end
    reconcile_identity()
    return vim.deepcopy(raw_snapshot())
  end

  function controller:report()
    if state.stopped then
      return nil
    end
    reconcile_identity()
    return state.phase == "ready" and vim.deepcopy(state.report) or nil
  end

  function controller:ensure(request)
    if
      state.stopped
      or type(request) ~= "table"
      or (request.reason ~= "picker" and request.reason ~= "open")
      or (request.reason == "picker"
        and (request.identity_key ~= nil or vim.tbl_count(request) ~= 1))
      or (request.reason == "open"
        and (vim.tbl_count(request) ~= 2
          or type(request.identity_key) ~= "string"
          or #request.identity_key ~= 32
          or request.identity_key:match(VALID_IDENTITY_KEY) == nil))
    then
      return nil, "managed OpenCode compatibility request is invalid"
    end

    local identity = reconcile_identity()
    if state.cancelling then
      return vim.deepcopy(raw_snapshot())
    end
    if not identity.installed then
      if
        request.reason == "picker"
        and state.phase == "failed"
        and state.category == "unavailable"
      then
        return vim.deepcopy(raw_snapshot())
      end
      fail("unavailable")
      return self:snapshot()
    end
    if request.reason == "open" then
      if state.queued_identity and state.queued_identity ~= request.identity_key then
        return nil, "managed OpenCode opening identity changed"
      end
      state.queued_identity = request.identity_key
    end

    if state.phase == "unknown" or (state.phase == "failed" and request.reason == "open") then
      start_sequence(identity)
    elseif state.phase == "ready" and request.reason == "open" then
      publish(false)
    end
    return vim.deepcopy(raw_snapshot())
  end

  function controller:take_open(identity_key)
    if
      state.stopped
      or state.phase ~= "ready"
      or type(identity_key) ~= "string"
      or #identity_key ~= 32
      or identity_key:match(VALID_IDENTITY_KEY) == nil
      or state.queued_identity ~= identity_key
    then
      return false
    end
    reconcile_identity()
    if state.phase ~= "ready" or state.queued_identity ~= identity_key then
      return false
    end
    state.queued_identity = nil
    publish(false)
    return true
  end

  function controller:cancel(reason)
    if state.stopped or not VALID_CANCEL_REASON[reason] then
      return
    end
    if reason == "shutdown" then
      self:shutdown(false)
      return
    end
    state.queued_identity = nil
    if state.phase == "checking" and not state.cancelling then
      local identity = reason == "executable-drift" and current_identity() or state.identity
      cancel_active("unknown", reason, identity)
    else
      publish(false)
    end
  end

  function controller:subscribe(callback)
    if state.stopped or type(callback) ~= "function" or state.observer_count >= MAX_OBSERVERS then
      return nil, "managed OpenCode compatibility observer is unavailable"
    end
    state.next_observer = state.next_observer + 1
    local key = state.next_observer
    state.observers[key] = callback
    state.observer_count = state.observer_count + 1
    local subscribed = true
    return function()
      if subscribed and state.observers[key] then
        subscribed = false
        state.observers[key] = nil
        state.observer_count = state.observer_count - 1
      end
    end
  end

  function controller:shutdown(exit_committed)
    assert(type(exit_committed) == "boolean", "shutdown phase must be explicit")
    if state.stopped then
      return true
    end
    state.stopped = true
    state.queued_identity = nil
    clear_sequence_timer()
    state.observers = {}
    state.observer_count = 0
    state.generation = state.generation + 1
    local slot = state.active
    state.active = nil
    if not slot or not slot.handle then
      return true
    end
    pcall(slot.handle.cancel, slot.handle, "shutdown")
    if not exit_committed then
      return true
    end
    local ok, drained = pcall(slot.handle.shutdown_drain, slot.handle, 2000)
    return ok and drained == true
  end

  function controller:debug_state()
    return {
      phase = state.phase,
      generation = state.generation,
      command_index = state.command_index,
      sequence_started_at = state.sequence_started_at,
      has_identity = state.identity ~= nil,
      has_report = state.report ~= nil,
      has_parser = state.parser ~= nil,
      has_active = state.active ~= nil,
      has_timer = state.sequence_timer ~= nil,
      observer_count = state.observer_count,
      queued = state.queued_identity ~= nil,
      stopped = state.stopped,
      cancelling = state.cancelling ~= nil,
    }
  end

  return controller
end

M.new = new
M._test = {
  new = new,
  new_idle_snapshot = idle_snapshot,
  new_parser = new_parser,
  parse_results = parse_results,
}
```
The internal phases are exactly `unknown`, `checking`, `ready`, and `failed`; expose `unknown` as `not_checked` and the other three names unchanged.
Call `identify()` before the first probe, before each later probe, and before publishing or returning a ready result.
Keep the queue as only one validated 32-character lowercase hexadecimal identity key.
Feed each completed bounded result directly to `parser:accept()` and drop the result before starting the next command; controller state must never contain stdout, stderr, a result table, or a list of raw command outputs.
Schedule observer calls and notifications on the main loop, deep-copy every published snapshot, and include only the generic category in failure notifications.
Replace the Task 1 parser-only success marker with exact final line `AI OpenCode background validation assertions: ok` after all controller assertions.

- [ ] **Step 6: Run the controller tests**

Run:

```bash
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exit `0`, no provider process starts, every fake sequence is serial, and the file prints exactly `AI OpenCode background validation assertions: ok`.

- [ ] **Step 7: Record an uncommitted checkpoint**

Run `git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check` and `git -C /tmp/dotfiles-nvim-ai-cli-companion status --short`.
Expected: no whitespace errors and no staged implementation bytes.

### Task 3: Classify and settle the audited lock subtree

**Files:**

- Modify: `.config/nvim/lua/ai/backends/init.lua:1356-1420`
- Modify: `.config/nvim/tests/ai_opencode_managed.lua:2236-2783`
- Modify: `.config/nvim/tests/ai_opencode_validation.lua`

**Interfaces:**

- Consumes: the current descriptor-bound `directory_entries()`, `read_probe_file()`, `valid_probe_lock_metadata()`, `same_probe_file()`, and non-lock artifact validators.
- Produces: `inspect_opencode_probe_lock(tree, overrides) -> classification|nil, category|nil` and `settle_opencode_probe_lock(tree, initial, overrides, callback) -> cancel`.

- [ ] **Step 1: Add exact lock-form fixture helpers**

In `ai_opencode_managed.lua`, create one guarded mode-0700 fixture tree and helper operations that produce these exact forms under `tree.state .. "/opencode"`:

```lua
local fixed_lock = "0a009c556ac8352fed53ef8323a3a97270935d30.lock"

local function valid_lock_metadata()
  return table.concat({
    "{",
    '  "token": "00112233-4455-4677-8899-aabbccddeeff",',
    '  "pid": 2,',
    string.format('  "hostname": %s,', vim.json.encode(assert(vim.uv.os_gethostname()))),
    '  "createdAt": "2026-08-27T12:00:00.000Z"',
    "}",
  }, "\n")
end
```

The helpers must create directories with mode `0700`, files with mode `0600`, use exclusive file creation, fsync written bytes, validate the exact owner, and remove only paths beneath the fixture root after proving no owned process remains.

- [ ] **Step 2: Write failing classifier tests for the three allowed forms**

Call the new classifier and require these exact normalized results:

```lua
eq(inspect_lock(absent_tree), {
  disposition = "quiescent",
  fingerprint = "absent",
}, "absent lock form")

eq(inspect_lock(empty_root_tree), {
  disposition = "quiescent",
  fingerprint = "empty",
}, "empty lock-root form")

local full = assert(inspect_lock(full_tree))
eq(full.disposition, "quiescent", "full lock form")
assert(full.fingerprint:match("^full:[0-9a-f]+$") and #full.fingerprint == 69)
```

Require `disposition = "transient"` for the fixed lock directory with neither file, only `heartbeat`, or only `meta.json`.
Require immediate `nil, "probe-lock-tree"` or the existing narrower safe lock category for an unknown root entry, unknown fixed-directory entry, symlink, FIFO, wrong owner, wrong directory mode, wrong file mode, nonempty heartbeat, malformed metadata, oversized metadata, replacement race, descriptor traversal failure, or more than the existing entry cap.

- [ ] **Step 3: Write failing two-snapshot settling tests**

Inject a classifier sequence and fake `now` and `defer` functions into `settle_opencode_probe_lock()`.
Cover these exact traces:

```text
absent -> 50 ms -> absent -> accepted
empty -> 50 ms -> full:A -> 100 ms -> full:A -> accepted
partial-heartbeat -> 50 ms -> full:A -> 100 ms -> full:A -> accepted
partial-meta -> every 50 ms through 1000 ms -> probe-lock-tree
absent -> 50 ms -> unknown entry -> immediate probe-lock-tree
full:A -> 50 ms -> full:B -> 100 ms -> full:B -> accepted
full:A -> timer callback after 1000 ms -> probe-lock-tree without acceptance
```

Assert that cancellation closes the pending settle timer, invokes the callback at most once, and cannot accept a late timer callback.

- [ ] **Step 4: Split lock validation from unchanged non-lock validation**

Change `inspect_opencode_probe_artifacts()` so nonsemantic commands still require an exact empty state directory and return immediately.
For semantic commands, validate all existing data, cache, configuration, log, repository, SQLite, ownership, mode, content, and replacement checks once, then call `inspect_opencode_probe_lock()`.
Use this complete classifier implementation:

```lua
local function inspect_opencode_probe_lock(tree, overrides)
  local filesystem = probe_artifact_filesystem(overrides)
  local state = tree.state .. "/opencode"
  local state_entries = directory_entries(state, filesystem)
  if not state_entries then
    return nil, "probe-lock-tree"
  end
  if #state_entries == 0 then
    return { disposition = "quiescent", fingerprint = "absent" }
  end
  if not vim.deep_equal(state_entries, { "locks" }) then
    return nil, "probe-lock-tree"
  end

  local lock_root = state .. "/locks"
  local root_entries = directory_entries(lock_root, filesystem)
  if not root_entries then
    return nil, "probe-lock-tree"
  end
  if #root_entries == 0 then
    return { disposition = "quiescent", fingerprint = "empty" }
  end
  if not vim.deep_equal(root_entries, { OPENCODE_PROBE_LOCK }) then
    return nil, "probe-lock-tree"
  end

  local lock = lock_root .. "/" .. OPENCODE_PROBE_LOCK
  local lock_entries = directory_entries(lock, filesystem)
  if not lock_entries then
    return nil, "probe-lock-tree"
  end
  local allowed = {
    heartbeat = true,
    ["meta.json"] = true,
  }
  for _, name in ipairs(lock_entries) do
    if not allowed[name] then
      return nil, "probe-lock-tree"
    end
  end

  local has_heartbeat = vim.tbl_contains(lock_entries, "heartbeat")
  local has_metadata = vim.tbl_contains(lock_entries, "meta.json")
  if has_heartbeat then
    local heartbeat = read_probe_file(lock .. "/heartbeat", 0, filesystem)
    if heartbeat ~= "" then
      return nil, "probe-heartbeat"
    end
  end
  local metadata
  if has_metadata then
    metadata = read_probe_file(lock .. "/meta.json", 512, filesystem)
    if not metadata or not valid_probe_lock_metadata(metadata, filesystem) then
      return nil, "probe-lock-metadata"
    end
  end

  if has_heartbeat and has_metadata and #lock_entries == 2 then
    local digest = filesystem.sha256(metadata)
    if type(digest) ~= "string" or #digest ~= 64 or digest:find("[^0-9a-f]") then
      return nil, "probe-lock-metadata"
    end
    return { disposition = "quiescent", fingerprint = "full:" .. digest }
  end

  local partial = #lock_entries == 0 and "empty-directory"
    or (has_heartbeat and "heartbeat" or "metadata")
  return { disposition = "transient", fingerprint = "partial:" .. partial }
end
```

Compute the full fingerprint from the exact validated metadata bytes with the existing injected SHA-256 function.
Do not include a path, hostname, UUID, timestamp, PID, or artifact bytes in the returned fingerprint or category.
Return the existing bounded safe category on rejection.
Replace the state-directory and former full-lock portion of `inspect_opencode_probe_artifacts()` with this exact flow after all common XDG roots have been validated:

```lua
if not semantic then
  if not exact_probe_directory(state, {}, filesystem) then
    return nil, "probe-artifact-tree"
  end
  return { disposition = "quiescent", fingerprint = "nonsemantic" }
end

local lock_snapshot, lock_error = inspect_opencode_probe_lock(tree, overrides)
if not lock_snapshot then
  return nil, lock_error
end

local log = read_probe_file(data .. "/log/opencode.log", 994, filesystem)
local database = read_probe_file(data .. "/opencode.db", 4096, filesystem)
local shared_memory = read_probe_file(data .. "/opencode.db-shm", 32768, filesystem)
local write_ahead_log = read_probe_file(data .. "/opencode.db-wal", 259592, filesystem)
local log_ok, log_error = valid_probe_log(log, filesystem)
if not log_ok then
  return nil, log_error
end
if not database or not shared_memory or not write_ahead_log then
  return nil, "probe-sqlite-file-boundary"
end
local sqlite_ok, sqlite_error =
  valid_probe_sqlite_files(database, shared_memory, write_ahead_log, filesystem)
if not sqlite_ok then
  return nil, sqlite_error
end
return lock_snapshot
```

Retain the current exact data, log, repository, cache, and state-parent directory checks before this block, but remove their assumption that `state` must contain a full fixed lock.

- [ ] **Step 5: Implement nonblocking lock settling**

Use this complete implementation with a matching private `stop_timer()` helper in `init.lua`:

```lua
local function settle_opencode_probe_lock(tree, initial, overrides, callback)
  local options = overrides or {}
  local now = options.now or vim.uv.now
  local defer = options.defer or vim.defer_fn
  local inspect = options.inspect_lock or inspect_opencode_probe_lock
  local started_at = now()
  local candidate = initial.disposition == "quiescent" and initial.fingerprint or nil
  local active = true
  local timer

  local function finish(accepted, category, snapshot)
    if not active then
      return
    end
    active = false
    stop_timer(timer)
    timer = nil
    callback(accepted, category, snapshot)
  end

  local function step()
    if not active then
      return
    end
    local elapsed = now() - started_at
    if elapsed > 1000 then
      finish(nil, "probe-lock-tree")
      return
    end
    local snapshot, category = inspect(tree, options.filesystem)
    if not snapshot then
      finish(nil, category or "probe-lock-tree")
      return
    end
    if snapshot.disposition == "quiescent" then
      if candidate == snapshot.fingerprint then
        finish(true, nil, snapshot)
        return
      end
      candidate = snapshot.fingerprint
    else
      candidate = nil
    end
    if elapsed >= 1000 then
      finish(nil, "probe-lock-tree")
      return
    end
    timer = defer(step, 50)
  end

  timer = defer(step, 50)
  return function()
    finish(nil, "cancellation")
  end
end
```

The first quiescent snapshot is a candidate, never a success by itself.
The only accepting branch compares two consecutive quiescent fingerprints.

- [ ] **Step 6: Run deterministic lock tests**

Run:

```bash
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exit `0`; absent, empty, and full locks pass only after two identical snapshots; strict partial locks never pass as a final form; every unsafe lock mutation fails immediately.
The complete existing non-lock mutation matrix runs after Task 6 has reduced the real OpenCode work to one sequence.

- [ ] **Step 7: Record an uncommitted checkpoint**

Run `git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check` and confirm no implementation path is staged.

### Task 4: Replace the blocking OpenCode process path with callbacks

**Files:**

- Modify: `.config/nvim/lua/ai/backends/init.lua:268-623,839-907,1422-1750,1974-2087,2088-2452`
- Modify: `.config/nvim/tests/ai_opencode_managed.lua:984-1470,1482-2215`
- Modify: `.config/nvim/tests/ai_opencode_validation.lua`

**Interfaces:**

- Consumes: `validation.new(deps)`, the exact fixed command objects, the lock classifier and settler, private tree creation, guarded cleanup, and existing output bounds.
- Produces: `bounded_system_async(argv, options, limits, on_complete, overrides) -> handle`, `start_opencode_probe(identity, command, on_complete, overrides) -> AiOpenCodeProbeHandle|nil, string|nil`, and a lazily constructed production validation controller.

- [ ] **Step 1: Write the failing asynchronous stream-boundary tests**

Add fake `vim.system` cases that return a handle whose `wait()` raises `wait-secret-canary` and whose completion callback is retained by the test.
Require the starter to return before completion, the event-loop timer from Task 2 to advance, `wait()` to remain unused, and completion to occur only after the fake exit callback.
Add early and late stdout overflow, stderr overflow, stream callback error, invalid callback data, spawn exception, timeout result `{ code = 124, signal = 15 }`, signaled exit, duplicate completion, cancel-before-handle-assignment, and callback exception cases.
Require one hard kill request for overflow, bounded empty returned streams on every boundary failure, no canary in any category, and one completion callback.

- [ ] **Step 2: Write failing probe ownership and cleanup tests**

Inject private-tree creation, artifact inspection, lock settling, deletion, lstat, scheduler, and process functions.
Assert these exact lifecycle rules:

```text
create -> spawn -> exit -> inspect non-lock -> settle lock -> cleanup -> complete
create -> spawn error -> inspect safe tree -> cleanup -> complete probe-failure
create -> overflow -> kill -> exit -> inspect -> cleanup -> complete output-overflow
create -> timeout -> exit -> inspect -> cleanup -> complete timeout
create -> cancel -> kill -> exit -> inspect -> cleanup -> complete cancellation
create -> exit -> artifact reject -> cleanup -> complete artifact-rejection
create -> exit -> cleanup failure -> complete cleanup-failure
```

Prove that a root is never deleted before process exit is confirmed.
Prove that cleanup executes exactly once despite duplicate exit, timer, cancellation, or late callbacks.
Before every recursive deletion, require the exact command-owned root path to remain absolute and normalized and require its current `lstat` to be a nonsymlink directory owned by the current user with mode `0700`.
Inject a changed root path, symlink, regular file, wrong owner, wrong mode, normalization escape, and pre-delete `lstat` exception; require refusal without invoking the recursive delete function.
Inject each post-delete result other than exact `ENOENT` and require a hard cleanup failure after the sole guarded delete call.
For `shutdown_drain(2000)`, require the sole permitted `wait(2000)` call, guarded cleanup only after a valid completed result, and root retention when `wait()` raises or returns an invalid result.

- [ ] **Step 3: Extract one exact Bubblewrap invocation builder**

Refactor the current `read_only_probe()` argv and environment validation into a private `prepare_read_only_probe(executable, arguments, probe, timeout_ms)` function.
It returns only this internal shape:

```lua
{
  argv = argv,
  options = {
    text = true,
    timeout = timeout_ms,
    clear_env = true,
    env = environment,
  },
}
```

Keep the existing generic `read_only_probe()` on the synchronous `bounded_system()` path with its exact `2000` millisecond timeout for Codex and Claude.
Use the shared builder from the asynchronous OpenCode path with exactly `5000` milliseconds.
Do not admit a caller-provided timeout, environment entry, mount destination, working directory, or Bubblewrap flag outside the already validated fields.

- [ ] **Step 4: Implement `bounded_system_async()` without ordinary waits**

Use this complete implementation and retain the same bounded integer validation as `bounded_system()` in its validation branch:

```lua
local function bounded_system_async(argv, options, limits, on_complete, overrides)
  local async = overrides or {}
  local valid_cancel = {
    close = true,
    ["backend-switch"] = true,
    shutdown = true,
    ["executable-drift"] = true,
    timeout = true,
    cancellation = true,
  }
  local system = async.system or vim.system
  local schedule = async.schedule or vim.schedule
  local stdout_chunks = {}
  local stderr_chunks = {}
  local lengths = { stdout = 0, stderr = 0 }
  local overflow = { stdout = false, stderr = false }
  local process
  local process_started = false
  local process_exited = false
  local delivered = false
  local final_result
  local stop_requested = false
  local kill_attempted = false
  local system_error = false
  local cancellation
  local handle = {}

  local function failed_result()
    return {
      code = 126,
      signal = 0,
      stdout = "",
      stderr = "",
      stdout_overflow = overflow.stdout,
      stderr_overflow = overflow.stderr,
      system_error = system_error,
      cancellation = cancellation,
      process_started = process_started,
      process_exited = process_exited,
    }
  end

  local function kill_once()
    stop_requested = true
    if kill_attempted or process_exited or not process then
      return
    end
    kill_attempted = true
    local ok = pcall(process.kill, process, "sigkill")
    if not ok then
      system_error = true
    end
  end

  local function capture(stream)
    local chunks = stream == "stdout" and stdout_chunks or stderr_chunks
    return function(err, data)
      local ok = pcall(function()
        if err ~= nil or (data ~= nil and type(data) ~= "string") then
          system_error = true
          kill_once()
          return
        end
        if data == nil or data == "" or delivered or overflow.stdout or overflow.stderr then
          return
        end
        local remaining = limits[stream] - lengths[stream]
        if #data > remaining then
          if remaining > 0 then
            chunks[#chunks + 1] = data:sub(1, remaining)
          end
          lengths[stream] = limits[stream]
          overflow[stream] = true
          kill_once()
          return
        end
        chunks[#chunks + 1] = data
        lengths[stream] = lengths[stream] + #data
      end)
      if not ok then
        system_error = true
        kill_once()
      end
    end
  end

  local function deliver(completed)
    if delivered then
      return final_result
    end
    delivered = true
    local result
    if
      system_error
      or overflow.stdout
      or overflow.stderr
      or type(completed) ~= "table"
      or type(completed.code) ~= "number"
      or type(completed.signal) ~= "number"
    then
      result = failed_result()
    else
      result = {
        code = completed.code,
        signal = completed.signal,
        stdout = table.concat(stdout_chunks),
        stderr = table.concat(stderr_chunks),
        stdout_overflow = false,
        stderr_overflow = false,
        system_error = false,
        cancellation = cancellation,
        process_started = process_started,
        process_exited = process_exited,
      }
    end
    stdout_chunks = {}
    stderr_chunks = {}
    final_result = result
    schedule(function()
      pcall(on_complete, result)
    end)
    return result
  end

  local function exited(completed)
    process_exited = type(completed) == "table"
      and type(completed.code) == "number"
      and type(completed.signal) == "number"
    deliver(completed)
  end

  function handle:cancel(reason)
    cancellation = valid_cancel[reason] and reason or "cancellation"
    kill_once()
  end

  function handle:shutdown_drain(timeout_ms)
    assert(timeout_ms == 2000, "OpenCode shutdown drain must be exactly 2000 ms")
    if process_exited then
      return true, final_result
    end
    if not process or type(process.wait) ~= "function" then
      return false
    end
    kill_once()
    local ok, completed = pcall(process.wait, process, timeout_ms)
    if
      not ok
      or type(completed) ~= "table"
      or type(completed.code) ~= "number"
      or type(completed.signal) ~= "number"
    then
      return false
    end
    process_exited = true
    local result = deliver(completed)
    return true, result
  end

  local options_ok, system_options = pcall(vim.deepcopy, options)
  if
    type(argv) ~= "table"
    or not vim.islist(argv)
    or not options_ok
    or type(system_options) ~= "table"
    or type(limits) ~= "table"
    or type(limits.stdout) ~= "number"
    or type(limits.stderr) ~= "number"
    or type(on_complete) ~= "function"
    or type(system) ~= "function"
    or type(schedule) ~= "function"
  then
    system_error = true
    deliver(nil)
    return handle
  end

  system_options.stdout = capture("stdout")
  system_options.stderr = capture("stderr")
  local spawn_ok, spawned = pcall(system, argv, system_options, exited)
  if spawn_ok and type(spawned) == "table" then
    process = spawned
    process_started = true
  end
  if not spawn_ok or type(spawned) ~= "table" or type(spawned.kill) ~= "function" then
    system_error = true
    deliver(nil)
    return handle
  end
  if stop_requested then
    kill_once()
  end
  return handle
end
```

Keep integer, nonnegative, and floor validation for both limits from the existing runner.
The only `process.wait` call in this function is the exact exit-only drain shown above.

- [ ] **Step 5: Implement one-command OpenCode ownership**

`start_opencode_probe()` must revalidate the exact canonical executable, compare its complete metadata identity, create one private tree, build only the exact managed environment and mounts, and start the async bounded process.
First harden the owned-root cleanup helper so it refuses any path that is not the exact still-private command root before deletion:

```lua
local function cleanup_owned_probe_tree(root, remove, lstat, getuid)
  local normalize_ok, normalized = false, nil
  if type(root) == "string" then
    normalize_ok, normalized = pcall(vim.fs.normalize, root)
  end
  if
    type(root) ~= "string"
    or root == ""
    or root:sub(1, 1) ~= "/"
    or root == "/"
    or has_control(root)
    or not normalize_ok
    or normalized ~= root
    or type(remove) ~= "function"
    or type(lstat) ~= "function"
    or type(getuid) ~= "function"
  then
    return false
  end
  local before_ok, before = pcall(lstat, root)
  local uid_ok, uid = pcall(getuid)
  if
    not before_ok
    or not uid_ok
    or type(uid) ~= "number"
    or type(before) ~= "table"
    or before.type ~= "directory"
    or type(before.uid) ~= "number"
    or before.uid ~= uid
    or type(before.mode) ~= "number"
    or bit.band(before.mode, 511) ~= 448
  then
    return false
  end
  local remove_ok, status = pcall(remove, root, "rf")
  if not remove_ok or status ~= 0 then
    return false
  end
  local lstat_ok, stat, _, code = pcall(lstat, root)
  return lstat_ok and stat == nil and code == "ENOENT"
end
```

Pass the current-user dependency explicitly at every production and test call site.
The owning closure must pass only its unchanged `tree.root`; never accept an artifact-derived path as the cleanup target.
Change `create_opencode_probe_tree()` to return `nil, "probe-failure"` when partial creation was cleaned successfully and `nil, "cleanup-failure"` when that guarded cleanup could not be proved, so the skeleton never depends on or exposes its former diagnostic text.
Use this complete ownership skeleton, including the exact `probe_options` table:

```lua
local function start_opencode_probe(identity, command, on_complete, overrides)
  local options = overrides or {}
  local revalidate = options.revalidate or require("ai.tools").revalidate
  local stat = options.stat or vim.uv.fs_lstat
  local create_tree = options.create_tree or create_opencode_probe_tree
  local cleanup_tree = options.cleanup_tree or cleanup_owned_probe_tree
  local inspect_artifacts = options.inspect_artifacts or inspect_opencode_probe_artifacts
  local settle_lock = options.settle_lock or settle_opencode_probe_lock
  local schedule = options.schedule or vim.schedule
  local observe = options.observe_probe
  local delete = options.delete or vim.fn.delete
  local lstat = options.lstat or vim.uv.fs_lstat
  local getuid = options.getuid or vim.uv.getuid
  local now = options.now or vim.uv.now
  local finished = false
  local cancellation_requested = false
  local cancel_settle
  local runner
  local tree
  local public = {}

  if
    type(identity) ~= "table"
    or identity.installed ~= true
    or type(identity.executable) ~= "string"
    or type(identity.metadata) ~= "string"
    or type(command) ~= "table"
    or type(command.name) ~= "string"
    or type(command.arguments) ~= "table"
    or type(command.semantic) ~= "boolean"
    or type(on_complete) ~= "function"
  then
    return nil, "probe-failure"
  end
  local expected_command
  for _, expected in ipairs(require("ai.backends.opencode_validation").commands()) do
    if expected.name == command.name then
      expected_command = expected
      break
    end
  end
  if not expected_command or not vim.deep_equal(command, expected_command) then
    return nil, "probe-failure"
  end
  local clock_ok, started_at = pcall(now)
  if not clock_ok or type(started_at) ~= "number" then
    return nil, "probe-failure"
  end

  local valid_ok, valid = pcall(revalidate, identity.executable)
  local stat_ok, current_stat = pcall(stat, identity.executable)
  local current_metadata = stat_ok and executable_metadata(current_stat) or nil
  if not valid_ok or not valid or not stat_ok or current_metadata ~= identity.metadata then
    return nil, "executable-drift"
  end
  local tree_ok, created_tree, create_error = pcall(create_tree)
  tree = tree_ok and created_tree or nil
  if not tree then
    return nil,
      tree_ok and create_error == "cleanup-failure" and "cleanup-failure"
        or "probe-failure"
  end
  if type(tree) ~= "table" then
    return nil, "cleanup-failure"
  end
  local exact_children = {
    home = "/home",
    config = "/xdg-config",
    config_opencode = "/xdg-config/opencode",
    bootstrap = "/xdg-config/opencode/.gitignore",
    data = "/xdg-data",
    cache = "/xdg-cache",
    state = "/xdg-state",
  }
  local root_private_ok, root_private = pcall(private_directory, tree.root, lstat, getuid)
  local normalize_ok, normalized_root = false, nil
  if type(tree.root) == "string" then
    normalize_ok, normalized_root = pcall(vim.fs.normalize, tree.root)
  end
  if
    type(tree.root) ~= "string"
    or tree.root:sub(1, 1) ~= "/"
    or tree.root == "/"
    or has_control(tree.root)
    or not root_private_ok
    or root_private ~= true
    or not normalize_ok
    or normalized_root ~= tree.root
  then
    return nil, "cleanup-failure"
  end
  for field, suffix in pairs(exact_children) do
    if tree[field] ~= tree.root .. suffix then
      return nil, "cleanup-failure"
    end
  end
  local function clean_tree()
    local ok, cleaned = pcall(cleanup_tree, tree.root, delete, lstat, getuid)
    return ok and cleaned == true
  end

  local probe_options = {
    resolve = options.resolve or require("ai.tools").resolve,
    revalidate = revalidate,
    lstat = lstat,
    getuid = getuid,
    environment = opencode_probe_environment(),
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
  }

  local invocation_ok, invocation = pcall(
    prepare_read_only_probe,
    identity.executable,
    command.arguments,
    probe_options,
    5000
  )
  if not invocation_ok or type(invocation) ~= "table" then
    local cleaned = clean_tree()
    return nil, cleaned and "probe-failure" or "cleanup-failure"
  end

  local function safe_observe(result, accepted, category)
    if type(observe) ~= "function" then
      return
    end
    local copy_ok, tree_copy = pcall(vim.deepcopy, tree)
    local category_ok, safe_category = pcall(safe_probe_artifact_category, category)
    if not copy_ok or not category_ok then
      return
    end
    local finished_ok, finished_at = pcall(now)
    local duration = finished_ok and type(finished_at) == "number"
        and math.max(0, math.min(10000, finished_at - started_at))
      or nil
    pcall(observe, command.name, tree_copy, {
      artifact_accepted = accepted == true,
      artifact_category = safe_category,
      code = type(result) == "table" and result.code or nil,
      signal = type(result) == "table" and result.signal or nil,
      stdout_bytes = type(result) == "table" and type(result.stdout) == "string"
          and #result.stdout
        or nil,
      stderr_bytes = type(result) == "table" and type(result.stderr) == "string"
          and #result.stderr
        or nil,
      stdout_overflow = type(result) == "table" and result.stdout_overflow == true,
      stderr_overflow = type(result) == "table" and result.stderr_overflow == true,
      system_error = type(result) == "table" and result.system_error == true,
      duration_ms = duration,
    })
  end

  local function result_category(result, artifacts_accepted, artifact_category, cleanup_succeeded)
    local exit_proven = type(result) == "table"
      and (result.process_started ~= true or result.process_exited == true)
    if not exit_proven then
      return "cleanup-failure"
    end
    if cancellation_requested and artifact_category == "cancellation" then
      return "cancellation"
    end
    if not artifacts_accepted then
      return "artifact-rejection"
    end
    if not cleanup_succeeded then
      return "cleanup-failure"
    end
    if cancellation_requested or result.cancellation ~= nil then
      return "cancellation"
    end
    if result.code == 124 then
      return "timeout"
    end
    if result.stdout_overflow or result.stderr_overflow then
      return "output-overflow"
    end
    if result.system_error or not valid_probe_result(result) then
      return "probe-failure"
    end
    return ""
  end

  local function finalize(result, artifacts_accepted, artifact_category)
    if finished then
      return
    end
    finished = true
    safe_observe(result, artifacts_accepted, artifact_category)
    local exit_proven = type(result) == "table"
      and (result.process_started ~= true or result.process_exited == true)
    local cleaned = exit_proven and clean_tree() or false
    local category = result_category(result, artifacts_accepted, artifact_category, cleaned)
    pcall(on_complete, category == "" and result or nil, category)
  end

  local function after_process(result)
    if finished then
      return
    end
    local exit_proven = type(result) == "table"
      and (result.process_started ~= true or result.process_exited == true)
    if not exit_proven then
      finalize(result, false, "process-exit-unproven")
      return
    end
    local inspect_ok, initial, artifact_category = pcall(
      inspect_artifacts,
      tree,
      command.semantic
    )
    if not inspect_ok or not initial then
      finalize(result, false, artifact_category or "probe-artifact-tree")
      return
    end
    if not command.semantic then
      finalize(result, true, "accepted")
      return
    end
    local settle_ok, settle_cancel = pcall(
      settle_lock,
      tree,
      initial,
      {
        now = now,
        defer = options.defer or vim.defer_fn,
        filesystem = options.filesystem,
        inspect_lock = options.inspect_lock,
      },
      function(accepted, category)
        cancel_settle = nil
        finalize(result, accepted == true, category or "accepted")
      end
    )
    if finished then
      return
    end
    if not settle_ok or type(settle_cancel) ~= "function" then
      finalize(result, false, "probe-lock-tree")
      return
    end
    cancel_settle = settle_cancel
  end

  runner = bounded_system_async(
    invocation.argv,
    invocation.options,
    { stdout = MAX_COMPATIBILITY_REPORT_BYTES, stderr = MAX_HELP_BYTES },
    after_process,
    { system = options.system, schedule = schedule }
  )

  function public:cancel(reason)
    cancellation_requested = true
    if cancel_settle then
      local cancel = cancel_settle
      cancel_settle = nil
      pcall(cancel)
    end
    if runner then
      pcall(runner.cancel, runner, reason)
    end
  end

  function public:shutdown_drain(timeout_ms)
    cancellation_requested = true
    if runner then
      pcall(runner.cancel, runner, "shutdown")
    end
    local ok, exited, result = pcall(runner.shutdown_drain, runner, timeout_ms)
    if not ok or exited ~= true then
      return false
    end
    if cancel_settle then
      local cancel = cancel_settle
      cancel_settle = nil
      pcall(cancel)
    end
    if not finished then
      local inspect_ok, inspected = pcall(inspect_artifacts, tree, command.semantic)
      local accepted = inspect_ok and inspected ~= nil
      safe_observe(result, accepted, accepted and "shutdown" or "artifact-rejection")
      local cleaned = clean_tree()
      finished = true
      return cleaned == true
    end
    return true
  end

  return public
end
```

The production controller never supplies `observe_probe`.
The managed test's injected observer may receive the exact already-exited command tree only during this ownership callback so it can copy one inspected fixture before cleanup; that path must never enter controller state, public snapshots, notifications, status, health, or recorded evidence.
Its observation table contains only a bounded duration, bounded byte counts, numeric code and signal, overflow booleans, artifact acceptance, and a safe category, while the command name remains the separate first argument.
Never pass raw streams or artifact contents to the observer.

- [ ] **Step 6: Wire the controller lazily into the registry**

Delete the production synchronous `opencode_compatibility()` sequence and `OPENCODE_COMPATIBILITY_CACHE` after all its parsing and cache assertions have moved to the controller tests.
Delete the temporary `M.parse_results` production export with that synchronous call site, while retaining `_test.parse_results` and the module-local incremental parser used by the controller.
Keep `executable_metadata()` and use it in a new lazy identity dependency:

```lua
local function opencode_identity(services, deps)
  local executable = services.resolve_executable("opencode")
  if not executable then
    return { installed = false, executable = "", metadata = "" }
  end
  local metadata = executable_metadata(deps.stat(executable))
  if not metadata then
    return { installed = false, executable = "", metadata = "" }
  end
  return { installed = true, executable = executable, metadata = metadata }
end
```

Construct the controller only when an OpenCode compatibility registry method is first called.
Inject `vim.uv.now`, `vim.defer_fn`, `vim.schedule`, `vim.notify`, `vim.log.levels.WARN`, and the production `start_opencode_probe` at that point.
Registry construction, `names()`, and `get()` must still start no process and create no tree.
Expose this exact test factory without starting validation:

```lua
local function new_opencode_validation(overrides)
  local options = overrides or {}
  local tools = require("ai.tools")
  local function identify()
    local executable = options.executable or tools.resolve("opencode")
    if not executable then
      return { installed = false, executable = "", metadata = "" }
    end
    local canonical = canonical_path(executable, "OpenCode executable", false)
    local valid_ok, valid = canonical and pcall(options.revalidate or tools.revalidate, canonical)
    local stat_ok, stat = canonical and pcall(options.stat or vim.uv.fs_lstat, canonical)
    local metadata = stat_ok and executable_metadata(stat) or nil
    if not canonical or not valid_ok or not valid or not metadata then
      return { installed = false, executable = "", metadata = "" }
    end
    return { installed = true, executable = canonical, metadata = metadata }
  end

  return require("ai.backends.opencode_validation").new({
    identify = identify,
    start_probe = function(identity, command, complete)
      return start_opencode_probe(identity, command, complete, options)
    end,
    now = options.now or vim.uv.now,
    defer = options.defer or vim.defer_fn,
    schedule = options.schedule or vim.schedule,
    notify = options.notify or vim.notify,
    warn_level = options.warn_level or vim.log.levels.WARN,
  })
end
```

Add `bounded_system_async`, `inspect_opencode_probe_lock`, `new_opencode_validation`, `settle_opencode_probe_lock`, and `start_opencode_probe` to `M._test` beside the retained exact test exports.

- [ ] **Step 7: Run deterministic process and controller tests**

Run the focused headless suite from Task 3.
Expected: it exits `0`, the delayed fake process leaves the event loop responsive, ordinary paths record zero waits, and every fake private root is either safely removed or explicitly retained after an unproven exit.

- [ ] **Step 8: Inspect the uncommitted process boundary**

Run:

```bash
rg -n "\.wait\(" \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/init.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode_validation.lua
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check
```

Expected: every production `wait(` match is inside the exact exit-only `shutdown_drain(2000)` implementation or an unchanged non-OpenCode synchronous helper, no OpenCode ordinary callback reaches it, and `diff --check` is silent.

### Task 5: Make adapter health immediate and launch readiness strict

**Files:**

- Modify: `.config/nvim/lua/ai/backends/init.lua:2088-2452`
- Modify: `.config/nvim/lua/ai/backends/opencode.lua:95-165,221-276`
- Modify: `.config/nvim/tests/ai_backends.lua:95-190,282-410,450-505,672-805,1034`
- Modify: `.config/nvim/tests/ai_opencode_validation.lua`

**Interfaces:**

- Consumes: the lazy controller and registry facade from Task 4.
- Produces: the six exact registry methods in Shared Interfaces, ready-only OpenCode launch construction, and an optional OpenCode health field `compatibility` with one of the four public states.

- [ ] **Step 1: Replace the injected synchronous compatibility fixture**

In `ai_backends.lua`, replace the existing `opencode_compatibility` dependency closure with an injected controller object whose default snapshot is ready:

```lua
local compatibility_state = {
  snapshot = {
    state = "ready",
    installed = true,
    executable = "/usr/bin/opencode",
    version = "1.18.18",
    category = "",
    queued = false,
  },
  report = vim.deepcopy(compatibility_report),
  ensures = {},
  cancels = {},
}

local fake_validation = {
  snapshot = function()
    return vim.deepcopy(compatibility_state.snapshot)
  end,
  report = function()
    return vim.deepcopy(compatibility_state.report)
  end,
  ensure = function(_, request)
    compatibility_state.ensures[#compatibility_state.ensures + 1] = vim.deepcopy(request)
    return vim.deepcopy(compatibility_state.snapshot)
  end,
  take_open = function()
    return false
  end,
  cancel = function(_, reason)
    compatibility_state.cancels[#compatibility_state.cancels + 1] = reason
  end,
  subscribe = function()
    return function() end
  end,
  shutdown = function(_, exit_committed)
    assert(type(exit_committed) == "boolean", "fake shutdown phase")
    return true
  end,
}
```

Pass it as `opencode_validation = fake_validation` to `registry_module._test.new()`.

- [ ] **Step 2: Add passive health-state tests**

For each of `not_checked`, `checking`, and `failed`, call `registry:health("opencode")` and require an immediate object with the matching `compatibility`, empty capabilities, no authentication inspection, and a bounded generic error.
For `ready`, require exact version `1.18.18`, filtered authentication inspection, full capabilities, and an empty error.
Set a syntactically `ready` snapshot whose executable differs from the executable resolved by the adapter and require the adapter to normalize it to `failed` with category `executable-drift`, empty capabilities, and no authentication inspection.
Assert across all four calls that `compatibility_state.ensures` remains empty and no probe starter is called.
Call `registry:opencode_compatibility()` directly and prove it returns a fresh copy without starting validation.

- [ ] **Step 3: Add ready-only launch tests**

Set each non-ready state before `opencode:new_session(identity, paths)` and require `nil, "managed OpenCode compatibility is not ready"` before profile preparation, port allocation, password generation, or launch-table construction.
Set `ready` with a missing, mutated, or executable-mismatched report and require the same bounded failure.
Restore the exact ready report and require the existing exact managed server, attach, environment, profile, protected path, and capability assertions to pass unchanged.

- [ ] **Step 4: Add registry request and queue facade tests**

Call the exact methods from Shared Interfaces and prove that requests, identity keys, cancellations, subscriptions, and shutdown are forwarded once to the one lazy controller.
Assert that unknown backend health remains unchanged and Codex and Claude health output and probe order remain byte-for-byte equal to their current expected tables.

- [ ] **Step 5: Change `opencode.lua` to consume snapshots**

At the start of `build()`, after resolving the executable and before preparing or inspecting a profile, require this exact trusted state:

```lua
local snapshot_ok, snapshot = pcall(deps.opencode_compatibility_snapshot)
if
  not snapshot_ok
  or type(snapshot) ~= "table"
  or snapshot.state ~= "ready"
  or snapshot.installed ~= true
  or snapshot.executable ~= executable
  or snapshot.version ~= managed.version()
  or snapshot.category ~= ""
then
  return nil, "managed OpenCode compatibility is not ready"
end
local report_ok, report = pcall(deps.opencode_compatibility_report)
if not report_ok or type(report) ~= "table" or not managed.validate_compatibility(report) then
  return nil, "managed OpenCode compatibility is not ready"
end
```

Replace `adapter:health()`'s synchronous compatibility call with one immediate snapshot read.
Return `compatibility = snapshot.state` in every OpenCode health result.
Only read `report()`, resolve the filtered auth path, or inspect authentication when `snapshot.state == "ready"`, `snapshot.executable` equals the currently resolved executable, and `managed.validate_compatibility(report)` succeeds.
Keep capabilities empty in every other case.
Use these exact non-ready diagnostics so no raw dependency error can cross the adapter boundary:

```lua
local compatibility_errors = {
  not_checked = "managed OpenCode compatibility not checked",
  checking = "managed OpenCode compatibility checking",
}

local function compatibility_health(executable, snapshot)
  local state = type(snapshot) == "table" and snapshot.state or "failed"
  local category = type(snapshot) == "table" and snapshot.category or "probe-failure"
  local detail = compatibility_errors[state]
    or ("managed OpenCode compatibility failed: " .. tostring(category)):sub(
      1,
      MAX_DIAGNOSTIC_BYTES
    )
  return {
    installed = true,
    executable = executable,
    version = "",
    auth = "unknown",
    capabilities = {},
    compatibility = state,
    error = detail,
  }
end
```

Validate every snapshot field against the Shared Interfaces shape, validate `state` against the exact four public values, and validate `category` against the controller's generic failure allowlist before using this helper.
Map any malformed snapshot to `failed` and `probe-failure`.
Map a `ready` snapshot whose executable does not equal the newly resolved executable to `failed` and `executable-drift` before calling the helper, so health can never report `compatibility = "ready"` for a stale executable.

- [ ] **Step 6: Expose the registry facade**

Add the six exact methods from Shared Interfaces to the object returned by `new(deps)` and matching module-level methods on `M`.
Set service dependencies for the adapter to `opencode_compatibility_snapshot` and `opencode_compatibility_report` closures over the same lazy controller.
When `deps.opencode_validation` is supplied, use that exact injected object and do not construct a production controller.
Make `registry:shutdown(exit_committed)` idempotent, forward the explicit boolean, and avoid constructing a controller merely to shut down a registry that never used OpenCode validation.
Implement module-level shutdown with this exact singleton handoff so a later setup can create a fresh controller:

```lua
function M.shutdown(exit_committed)
  assert(type(exit_committed) == "boolean", "shutdown phase must be explicit")
  if not runtime then
    return true
  end
  local current = runtime
  runtime = nil
  return current:shutdown(exit_committed)
end
```

- [ ] **Step 7: Run backend and controller regressions**

Run:

```bash
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_backends.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exact lines `AI backend adapter assertions: ok` and `AI OpenCode background validation assertions: ok`, with no real OpenCode or Bubblewrap process.

- [ ] **Step 8: Record an uncommitted checkpoint**

Run `git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check` and confirm no implementation path is staged.

### Task 6: Prove the one real gate and preserve all managed regressions

**Files:**

- Modify: `.config/nvim/tests/ai_opencode_managed.lua:1293-1470,1906-2215,2236-2860`
- Modify: `.config/nvim/tests/ai_opencode_validation.lua`
- Verify: `.config/nvim/tests/nvim-ai-opencode-compat.sh`
- Verify: `.config/nvim/tests/nvim_ai_opencode_profile.py`
- Verify: `.config/nvim/tests/nvim_ai_launch.py`
- Verify: `.config/nvim/tests/ai_sandbox.lua`
- Verify: `.config/nvim/tests/nvim-ai-sandbox.sh`

**Interfaces:**

- Consumes: the production validation controller, async probe boundary, lock settling, registry facade, and adapter readiness contract.
- Produces: one provider-free installed-binary proof with exact success output and a reviewed uncommitted implementation candidate.

- [ ] **Step 1: Remove every extra real OpenCode probe**

Delete the loop that currently starts eight separate `agent list` commands to manufacture artifact trees.
Delete or convert the cleanup-failure, cleanup-replay, partial-create, and other direct installed-binary `opencode_compatibility()` calls between the installed executable resolution and the final gate into the deterministic injected lifecycle cases already owned by `ai_opencode_validation.lua`.
After the edit, `rg -n "installed_opencode|start_opencode_probe|ensure" .config/nvim/tests/ai_opencode_managed.lua` must show exactly one installed executable resolution and one controller `ensure()` call that starts the final twelve-command sequence.
Do not replace any removed call with another real command.
Create one exact current-user-owned mode-0700 retention root before the single real validation and register guarded cleanup before its first assertion.

- [ ] **Step 2: Adapt the real gate to the asynchronous controller**

Create the production test controller through `_test.new_opencode_validation()` and pass a concrete `observe_probe` callback that implements the guarded copy and bounded observation contract below.
Start it exactly once with:

```lua
local identity_key = string.rep("a", 32)
local started, start_error = controller:ensure({
  reason = "open",
  identity_key = identity_key,
})
assert(started, start_error)
assert(vim.wait(70000, function()
  local state = controller:snapshot().state
  return state == "ready" or state == "failed"
end, 10), "real managed OpenCode validation exceeded its outer test deadline")
```

The observer may copy one already exited, already inspected semantic tree into the guarded retention root before production cleanup.
Perform that bounded local copy with descriptor-checked `vim.uv` filesystem operations from the test helper; do not call `vim.system()`, `vim.fn.system()`, or any `wait()` method from the observer.
It must record only command name, timing, numeric code and signal, bounded byte counts, overflow flags, artifact category, and the retained path owned by the test.
It must not print or persist raw stdout, stderr, credentials, metadata bytes, logs, SQLite bytes, configuration contents, or prompt data outside the guarded test root.

- [ ] **Step 3: Rebase artifact mutation tests onto one retained semantic tree**

Choose the retained `names` tree, prove it is a current-user-owned mode-0700 strict child of the retention root, and run every existing non-lock mutation against it.
Use Task 3's fixture helpers to replace its lock subtree with absent, empty, transient, full, and hostile forms instead of depending on one nondeterministic post-exit lock shape.
Restore the exact retained bytes and modes after every mutation.
Require the original production inspector to reject every existing log, SQLite, bootstrap, ownership, mode, symlink, replacement, and unknown-entry mutation.

- [ ] **Step 4: Assert real readiness and one queued opening**

Require the final snapshot to be exactly `ready`, the report to pass `managed.validate_compatibility`, all twelve observations to appear once in fixed order, and every artifact observation to be accepted.
Require `take_open(identity_key)` to return `true` once and `false` afterward.
Require no retry, no second controller, no second twelve-command sequence, and no provider output.
Preserve the suite's exact final line `AI managed OpenCode assertions: ok`.

- [ ] **Step 5: Format the authorized Lua paths**

Run:

```bash
stylua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/init.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode_validation.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_backends.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_managed.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check
```

Expected: Stylua exits `0` and `diff --check` is silent.

- [ ] **Step 6: Run deterministic suites without real providers**

Run serially:

```bash
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_backends.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_sandbox.lua
python3 -I -B \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim_ai_opencode_profile.py
python3 -I -B \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim_ai_launch.py
shellcheck /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-sandbox.sh
bash /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-sandbox.sh
```

Expected: every command exits `0`; the Lua suites print their exact success lines; both Python suites report `OK`; the sandbox shell harness prints its existing exact success line; no real Codex, Claude, or OpenCode process starts.

- [ ] **Step 7: Run the real managed-Lua gate once**

Obtain the required host-execution approval because Bubblewrap and the installed OpenCode binary need the real Linux process and mount namespace boundary.
Run only this one command, wait for it to finish, and do not retry it automatically:

```bash
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_managed.lua
```

Expected: exit `0` within the outer 70-second test bound and exact final line `AI managed OpenCode assertions: ok`.
If it fails, preserve only the exact guarded private root named by the test after proving no owned process remains, record bounded categories and timings, and stop before the hostile-HOME harness.

- [ ] **Step 8: Audit processes and residue before the second real harness**

Run read-only process and root checks against the exact root printed or recorded by the managed test.
Expected: no owned Bubblewrap or OpenCode process remains; all successfully cleaned command roots are absent; any deliberately retained audit root is mode `0700`, current-user-owned, nonsymlink, and contains only the inspected failed command tree.
Do not delete an uncertain root.

- [ ] **Step 9: Run the hostile-HOME harness once after the managed gate**

Obtain or reuse the exact host-execution approval for the existing harness and run:

```bash
shellcheck /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-opencode-compat.sh
bash /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-opencode-compat.sh
```

Expected: shellcheck exits `0` and the harness prints exactly `Managed OpenCode compatibility assertions: ok`.
Do not run this command concurrently with the managed-Lua gate and do not retry automatically.

- [ ] **Step 10: Freeze the uncommitted candidate**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion status --short
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check
sha256sum \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/init.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode_validation.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_backends.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_managed.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exactly these six implementation paths are modified or untracked, this plan and its approved design are already committed, no implementation byte is staged, `diff --check` is silent, and the hashes are recorded in ISQ-22 with the bounded test evidence.

### Task 7: Review, commit under an exact lease, and hand back to the main plan

**Files:**

- Review: `.config/nvim/lua/ai/backends/init.lua`
- Review: `.config/nvim/lua/ai/backends/opencode.lua`
- Review: `.config/nvim/lua/ai/backends/opencode_validation.lua`
- Review: `.config/nvim/tests/ai_backends.lua`
- Review: `.config/nvim/tests/ai_opencode_managed.lua`
- Review: `.config/nvim/tests/ai_opencode_validation.lua`

**Interfaces:**

- Consumes: the frozen uncommitted hashes and complete evidence from Task 6.
- Produces: one reviewed repair commit that unblocks managed OpenCode Task 5 closure and then the main companion plan's Task 4.

- [ ] **Step 1: Obtain a fresh specification review**

Give the reviewer the approved design, this implementation plan, the six exact candidate hashes, and the focused test evidence.
Require explicit findings for every design section, especially passive startup, no UI wait, twelve-command order, five-second and sixty-second deadlines, three lock forms, two-snapshot settling, one queued content-free opening, cancellation, executable drift, exit-only drain, health passivity, no automatic retry, and one real gate.
Do not alter Git metadata while the review is open.

- [ ] **Step 2: Obtain a separate fresh quality review**

Require a different reviewer to inspect callback races, timer ownership, generation checks, duplicate completion, kill and cleanup ordering, root containment, stale handles, observer bounds, deep-copy boundaries, diagnostic sanitization, test realism, and untouched Codex and Claude behavior.
Do not alter Git metadata while the review is open.

- [ ] **Step 3: Repair every accepted finding test first**

For each finding, add or tighten the smallest deterministic failing assertion, run it to see the intended failure, patch only the six authorized paths, rerun the focused suite, refresh all six hashes, and return the new frozen candidate to both reviewers when their reviewed bytes changed.
Keep the candidate uncommitted until both reviews explicitly pass the same hashes.

- [ ] **Step 4: Revalidate Linear and local state before staging**

Read the complete Dotfiles coordination contract, ISQ-22 description, and recent comments again.
Compare its branch, worktree, base commits, active paths, candidate hashes, tests, process audit, residue audit, and stop conditions with read-only local inspection.
Stop if Linear is unavailable, another writer owns a candidate path, the branch or worktree differs, a hash changed, or any active scope conflicts.

- [ ] **Step 5: Acquire one exact Git-metadata lease**

Update ISQ-22 so the sole writer owns only staging and committing the six reviewed paths at their approved hashes.
The lease must forbid all implementation edits, extra paths, rebases, merges, provider calls, live-home writes, and unrelated Git metadata.

- [ ] **Step 6: Stage and inspect only the reviewed bytes**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion add -- \
  .config/nvim/lua/ai/backends/init.lua \
  .config/nvim/lua/ai/backends/opencode.lua \
  .config/nvim/lua/ai/backends/opencode_validation.lua \
  .config/nvim/tests/ai_backends.lua \
  .config/nvim/tests/ai_opencode_managed.lua \
  .config/nvim/tests/ai_opencode_validation.lua
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --cached --check
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --cached --stat
git -C /tmp/dotfiles-nvim-ai-cli-companion status --short
```

Expected: only the six reviewed paths are staged, their hashes match the approved review record, `diff --cached --check` is silent, and no other path is staged or modified.

- [ ] **Step 7: Commit the reviewed repair**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion commit -m "fix(nvim): validate OpenCode in background"
```

Expected: one commit is created on `agent/nvim-ai-cli-companion` with parent `d7c4b401415758b1d6bf7cea20023fd24e669ebd` and exactly the six reviewed implementation paths.

- [ ] **Step 8: Verify the committed tree and record handoff**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion status --short --branch
git -C /tmp/dotfiles-nvim-ai-cli-companion show --stat --oneline --decorate HEAD
git -C /tmp/dotfiles-nvim-ai-cli-companion diff HEAD^ HEAD --check
```

Expected: the worktree is clean, the commit contains exactly the six paths, and the commit diff has no whitespace errors.
Record the commit SHA, tree SHA, exact test outputs, process audit, residue audit, reviewer identities, reviewer decisions, and downstream API contract in ISQ-22.
Only after that record is complete may the managed OpenCode completion gate close and `.config/docs/superpowers/plans/2026-08-23-neovim-native-ai-cli-companion.md` resume at Task 4.

## Downstream Task 5 and Task 11 Contract

The later session coordinator must subscribe once to `registry:subscribe_opencode_compatibility()` for the pinned companion identity.
It must call `ensure_opencode_compatibility({ reason = "picker" })` only when the first AI picker observes `not_checked`.
It must render `OpenCode: checking` as selectable only for queuing the one opening.
It must call `ensure_opencode_compatibility({ reason = "open", identity_key = identity.key })` for an explicit OpenCode open or prompt.
It must not pass prompt text, selection bytes, a cursor location, or a context path to the controller.
After a `ready` notification, it must call `take_opencode_open(identity.key)` once, re-resolve current identity and launch inputs, enter the ordinary opening transaction, and notify a prompt caller to invoke the prompt again.
It must cancel on close, selection of Codex or Claude, identity drift, and shutdown.
The future status module may render `AI:O checking` from the read-only snapshot.
The future `:checkhealth nvim-ai` provider must report `not_checked`, `checking`, `ready`, or `failed` from the read-only snapshot and must never start or retry validation.
Both consumers must project only the public compatibility state and the validated generic failure category; the snapshot's trusted executable field is adapter-internal and must not be copied into detailed status or compatibility diagnostics.
