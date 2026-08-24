# Neovim Native AI CLI Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.
>
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Linux-only Neovim coordinator that runs Codex, Claude, or OpenCode in one worktree-confined native TUI pane, transfers explicit context, safely reviews agent edits, and exposes capability-aware status without changing the active tmux workspace schema.

**Architecture:** Focused Lua modules own identity, durable state, backend policy, transport, context, review, scope, and UI state.
A current-user-owned launch manifest crosses into a Python standard-library launcher, which constructs Bubblewrap arguments without evaluating user text as shell syntax.
Neovim activates write access only while an exact review batch exists, and all filesystem reversals pass through hash-checked review reducers.

**Tech Stack:** Neovim 0.12 Lua, `vim.system`, `vim.uv`, Python 3 standard library, Bubblewrap 0.11 or newer, tmux 3.7 or newer, Git, native Neovim diff buffers, `vim.ui.select`, POSIX shell test harnesses, and the existing terminal-stack checker.

## Global Constraints

- Support Codex, Claude, and OpenCode from the first integrated release.
- Reuse externally installed and authenticated CLIs without installing, updating, or logging into them.
- Use no AI integration plugin and make no `lazy-lock.json` change.
- Keep one active AI pane per tmux server namespace, owning Neovim pane, and canonical physical root.
- Keep one resumable session per backend for each companion identity.
- Run the native CLI TUI in a right-hand tmux pane, with a Neovim terminal split fallback outside tmux.
- Treat the physical root as the only writable project path unless Neovim explicitly approves a temporary grant.
- Keep linked-worktree `.git`, Git administration, common Git data, and refs read-only.
- Keep the managed AI pane read-only whenever no exact review batch is active.
- Keep Codex and Claude session and cache state identity-specific while mounting only their validated existing inputs read-only.
- Run OpenCode `v1.18.18` through the managed-profile contract in `.config/docs/superpowers/specs/2026-08-24-neovim-managed-opencode-profile-design.md`.
- Reuse only validated OpenCode `api` and `oauth` credentials, never global or project OpenCode configuration, `account.json`, or `mcp-auth.json`.
- Permit provider connectivity while keeping agent-initiated network and destructive actions under backend approval policy.
- Transfer visual selections through private files and otherwise transfer only relative path, line, and column.
- Never submit a prompt or resume a restored agent turn automatically.
- Review only tracked and non-ignored untracked files inside Git worktrees.
- Treat non-Git edits, ignored paths, modified buffers touched externally, mixed writers, and hash races as conflict-only.
- Never reset files to `HEAD`, invoke destructive Git checkout, or reject a change whose exact reviewed hash no longer matches.
- Publish bounded sanitized status through the existing tmux row or standalone Neovim statusline.
- Fail closed when Bubblewrap, identity, state ownership, confinement, or review attribution cannot be proven.
- Support agent launch on Linux only.
- Use fake CLIs and private tmux sockets for automated tests.
- Do not contact model providers in automated tests.
- Do not connect to, reload, or mutate the default tmux server in tests.
- Do not modify `.config/tmux/scripts/workspace`, `.config/tmux/tests/workspace-state.sh`, `.config/tmux/tests/workspace-restore.sh`, `.config/nvim/lua/integrations/tmux_persistence.lua`, or `.config/nvim/tests/tmux_persistence.lua` in this plan.
- Write the paused workspace restoration plan only after the active line-pin schema-2 candidate is accepted and integrated.
- Treat inline completion and ghost-text suggestions as a separate provider-comparison project.
- Never add an agent co-author trailer to a commit.

## Execution Amendment: Managed OpenCode Profile

Task 1 is complete through commit `596a652`.
The Task 2 candidate at commits `00e78e0` and `28bf53c` is not approved because its OpenCode environment policy can be overridden by configured agents.
Commit `6223541` adds the approved managed-profile design amendment.

Before executing any remaining work in this plan, complete `.config/docs/superpowers/plans/2026-08-24-neovim-managed-opencode-profile.md`.
Tasks 1 through 3 of that plan replace the OpenCode portions of Task 2 below.
Tasks 4 and 5 of that plan implement every nonconflicting base requirement from Task 3 below and replace its historical OpenCode portions with the managed-profile boundary.
After its fresh specification and quality reviews pass, resume this plan at Task 4.
Do not execute any conflicting historical OpenCode instruction in Task 2 or Task 3.

---

## File Map

### Core identity and state

- Create `.config/nvim/lua/ai/identity.lua`.
  This module resolves physical roots, Git administration paths, tmux server namespaces, owner panes, and stable identity keys.
- Create `.config/nvim/lua/ai/tools.lua`.
  This module resolves every trusted host executable to one canonical absolute nonsymlink target with safe metadata.
- Create `.config/nvim/lua/ai/state.lua`.
  This module owns private runtime and durable directories, strict JSON files, atomic publication, and per-identity records.
- Create `.config/nvim/tests/ai_identity.lua`.
  This focused headless test owns root, identity, ownership, mode, symlink, and atomic-state behavior.

### Backend policy and launch boundary

- Create `.config/nvim/lua/ai/backends/init.lua`.
  This registry exposes the common backend contract and installed-backend picker entries.
- Create `.config/nvim/lua/ai/backends/codex.lua`.
  This adapter owns Codex detection, health commands, isolated state, launch arguments, resume arguments, and capabilities.
- Create `.config/nvim/lua/ai/backends/claude.lua`.
  This adapter owns Claude detection, explicit UUID sessions, launch arguments, resume arguments, and hook metadata.
- Create `.config/nvim/lua/ai/backends/opencode.lua`.
  This adapter owns OpenCode detection, server-and-attach launch metadata, session IDs, event endpoint metadata, and capabilities.
- Create `.config/nvim/lua/ai/backends/opencode_managed.lua`.
  This module owns the exact audited OpenCode version, managed policy, profile request, environment, and semantic compatibility contract.
- Create `.config/nvim/scripts/nvim-ai-opencode-profile.py`.
  This helper filters credentials, snapshots approved instructions, and atomically publishes an immutable managed OpenCode profile.
- Create `.config/nvim/lua/ai/sandbox.lua`.
  This module validates grants and emits a versioned launch manifest plus the fixed launcher invocation.
- Create `.config/nvim/scripts/nvim-ai-launch.py`.
  This executable validates the manifest, constructs Bubblewrap arguments, launches direct or server-and-attach backends, and falls back to a diagnostic shell only after the managed backend exits.
- Create `.config/nvim/tests/ai_backends.lua`.
  This test owns the exact common contract, backend arguments, state isolation, and capability declarations.
- Create `.config/nvim/tests/ai_opencode_managed.lua`.
  This test owns managed OpenCode policy, version, native-agent semantics, and adapter integration.
- Create `.config/nvim/tests/nvim_ai_opencode_profile.py`.
  This test owns strict credential filtering, instruction snapshots, atomic profile publication, and secret-free failures.
- Create `.config/nvim/tests/nvim-ai-opencode-compat.sh`.
  This real-binary harness proves hostile OpenCode configuration isolation without provider access.
- Create `.config/nvim/tests/ai_sandbox.lua`.
  This test owns manifest validation, mount ordering, read-only mode, writable-batch mode, Git masks, grants, environment filtering, and launcher invocation.
- Create `.config/nvim/tests/nvim_ai_launch.py`.
  This Python standard-library test owns strict manifest validation and exact Bubblewrap argument construction.
- Create `.config/nvim/tests/nvim-ai-sandbox.sh`.
  This private filesystem test proves real Bubblewrap write and escape behavior without a model CLI.

### Transport, session, and context

- Create `.config/nvim/lua/ai/transports/tmux.lua`.
  This module discovers, creates, tags, focuses, respawns, pastes into, and closes managed tmux panes.
- Create `.config/nvim/lua/ai/transports/terminal.lua`.
  This module provides the same high-level contract with a Neovim right-hand terminal split.
- Create `.config/nvim/lua/ai/session.lua`.
  This coordinator enforces one pane, backend selection, read-only and writable relaunches, backend switching, resume records, and common state transitions.
- Create `.config/nvim/lua/ai/context.lua`.
  This module extracts exact visual text, writes mode-0600 context files, formats references, and never submits a prompt.
- Create `.config/nvim/tests/ai_transport.lua`.
  This test owns transport commands, duplicate handling, safe paste buffers, fallback terminals, and session transitions.
- Create `.config/nvim/tests/ai_context.lua`.
  This test owns normal, characterwise, linewise, blockwise, unsaved, non-file, and cleanup behavior.
- Create `.config/tmux/tests/nvim-ai.sh`.
  This private-socket end-to-end test owns real tmux pane identity, right-hand placement, reconnection, backend switching, and default-server isolation.

### Review and buffer safety

- Create `.config/nvim/lua/ai/review/baseline.lua`.
  This module records exact Git-visible baseline objects without touching the real index or object database.
- Create `.config/nvim/lua/ai/review/tracker.lua`.
  This module scans deltas, records Neovim writes, classifies conflicts, synchronizes unmodified buffers, and owns the review-batch lifecycle.
- Create `.config/nvim/lua/ai/review/reducer.lua`.
  This pure module calculates text hunks and hash-checked whole-file or hunk rejection results.
- Create `.config/nvim/lua/ai/review/ui.lua`.
  This module owns the file picker, side-by-side diff buffers, review mappings, and resolution navigation.
- Create `.config/nvim/scripts/nvim-ai-review.py`.
  This executable applies one exact hash-checked review mutation through directory file descriptors inside a root-only Bubblewrap boundary.
- Create `.config/nvim/tests/ai_review.lua`.
  This test owns dirty baselines, new and deleted files, modes, symlinks, binaries, ignored files, user writes, buffer conflicts, hash races, and review actions.
- Create `.config/nvim/tests/nvim_ai_review.py`.
  This Python test owns descriptor-relative mutation, symlink-parent refusal, expected hashes, atomic replacement, and exact object restoration.

### Scope, public API, health, and status

- Create `.config/nvim/lua/ai/scope.lua`.
  This module owns the private Unix socket, request validation, confirmation, grant state, and relaunch requests.
- Create `.config/nvim/lua/ai/events.lua`.
  This module reads bounded normalized backend events and publishes rich status observations without authorizing actions.
- Create `.config/nvim/scripts/nvim-ai-control.py`.
  This executable sends one bounded scope request to the private Unix socket and waits for one bounded response.
- Create `.config/nvim/scripts/nvim-ai-event.py`.
  This executable normalizes Claude hooks and OpenCode events into content-free bounded records.
- Create `.config/nvim/tests/ai_scope.lua`.
  This test owns scope protocol, canonicalization, denial, approval, expiry, revocation, and unavailable-Neovim behavior.
- Create `.config/nvim/tests/nvim_ai_control.py`.
  This Python test owns exact client framing, bounds, timeouts, and refusal messages.
- Create `.config/nvim/lua/ai/status.lua`.
  This module owns compact state, detailed state, transition notification deduplication, and the status subscription API.
- Create `.config/nvim/lua/ai/init.lua`.
  This public module wires commands, mappings, components, and teardown.
- Create `.config/nvim/lua/nvim-ai/health.lua`.
  This provider implements `:checkhealth nvim-ai` without provider calls or state mutation.
- Create `.config/nvim/tests/ai_status.lua`.
  This test owns compact status, notification transitions, command and mapping registration, health output, and shutdown.
- Modify `.config/nvim/init.lua`.
  Startup calls `require("ai").setup()` only after every safety component exists.
- Modify `.config/nvim/lua/plugins/key-helper.lua` and `.config/nvim/tests/key_helper.lua`.
  WhichKey declares the non-executable `<leader>a` group in normal and visual modes.
- Modify `.config/nvim/lua/integrations/tmux_status.lua`.
  The existing atomic pane publication adds one bounded `@dotfiles_nvim_ai` field.
- Modify `.config/nvim/lua/ui/statusline.lua` and `.config/nvim/tests/statusline.lua`.
  The standalone statusline consumes the same compact AI status without adding a second row.
- Modify `.config/tmux/conf/status.conf`.
  The existing tmux row renders the bounded AI option for the active Neovim pane.

### Aggregate verification

- Modify `.config/dotfiles/check-terminal-stack`.
  The checker inventories every new source, runs Lua and Python focused suites, runs the real Bubblewrap fixture, runs the private tmux harness, and checks configured startup.
- Read only `.config/docs/superpowers/specs/2026-08-23-neovim-native-ai-cli-companion-design.md`.
  This is the approved behavior contract.

## Shared Interfaces

Every task uses the exact names in this section.
Later tasks must not rename fields or methods without first updating every earlier focused test.

```lua
---@class AiHostTools
---@field git string
---@field tmux string|nil
---@field python string
---@field bwrap string
---@field shell string

---@class AiIdentity
---@field key string                    -- 32 lowercase hexadecimal characters
---@field root string                   -- canonical absolute physical root
---@field inside_git boolean
---@field git_dir string|nil            -- canonical absolute Git administration path
---@field git_common_dir string|nil     -- canonical absolute common Git path
---@field git_entry string|nil          -- physical-root `/.git` file or directory without symlink resolution
---@field owner_pane string|nil         -- `%` plus decimal digits
---@field tmux_socket string|nil        -- canonical absolute socket path
---@field namespace string              -- `tmux:<socket>:<device>:<inode>` or `nvim:<nonce>`

---@class AiBackendLaunch
---@field kind "direct"|"server_attach"
---@field backend "codex"|"claude"|"opencode"
---@field argv string[]|nil
---@field server_argv string[]|nil
---@field attach_argv string[]|nil
---@field env table<string,string>
---@field session string
---@field capabilities table<string,boolean>
---@field read_only_inputs { source:string, destination:string, kind:"file"|"directory" }[]
---@field protected_paths string[]
---@field event_url string|nil
---@field event_file string|nil

---@class AiLaunchManifest
---@field schema 1
---@field token string
---@field identity_key string
---@field root string
---@field git_dir string|nil
---@field git_common_dir string|nil
---@field git_entry string|nil
---@field writable boolean
---@field grants string[]
---@field review_id string|nil
---@field runtime_root string
---@field state_root string
---@field context_dir string
---@field backend_state_dir string
---@field control_socket string
---@field control_token string
---@field control_helper string
---@field event_helper string
---@field launcher string
---@field review_helper string
---@field event_file string
---@field tmux_socket string|nil
---@field python string
---@field bwrap string
---@field host_tools string[]
---@field shell string
---@field launch AiBackendLaunch

---@class AiTransport
---@field discover fun(identity: AiIdentity): table[]|nil, string|nil
---@field create fun(identity: AiIdentity, invocation: { command:string, argv:string[] }): string|nil, string|nil
---@field focus fun(pane: string): boolean, string|nil
---@field respawn fun(pane: string, invocation: { command:string, argv:string[] }, policy:table|nil): boolean, string|nil
---@field tag fun(pane: string, metadata: table): boolean, string|nil
---@field paste fun(pane: string, text: string): boolean, string|nil
---@field close fun(pane: string, policy:table|nil): boolean, string|nil
---@field shutdown fun(): nil

---@class AiReviewState
---@field id string
---@field identity_key string
---@field root string
---@field phase "open"|"conflicted"|"resolved"|"abandoned"
---@field baseline_hash string
---@field paths table<string,table>
```

The durable per-identity record uses this exact top-level shape:

```json
{
  "schema": 1,
  "identity": {
    "key": "0123456789abcdef0123456789abcdef",
    "root": "/absolute/root",
    "namespace": "tmux:/absolute/socket:41:9001",
    "owner_pane": "%12"
  },
  "active_backend": "codex",
  "sessions": {
    "codex": "last",
    "claude": "00000000-0000-4000-8000-000000000000",
    "opencode": ""
  },
  "grants": [],
  "review_id": null
}
```

The common status payload uses this exact shape:

```lua
{
  backend = "codex",           -- `codex`, `claude`, `opencode`, or nil
  state = "closed",            -- approved common or rich state
  unresolved = 0,
  conflicts = 0,
  detail = "",
}
```

Focused test snippets use local fixture constructors defined in the same test file before their first call.
Use these exact fixture contracts:

- `fake_transport_for(identity)` returns an `AiTransport` with pane `%40`, a chronological `calls` array, `created` and `closed` counters, configurable discovery records, and no external process.
- `fake_registry()` returns all three Task 2 adapters with deterministic sessions, fresh launch tables, exact suspend and stop policies, and no executable invocation.
- `fake_store(record)` deep-copies reads and writes, records every durable version, returns a deterministic control token, and exposes no real state path.
- `fake_sandbox()` returns an object whose `prepare(options)` deep-copies each final manifest into `manifests` and returns fixed safe `{ command, argv }` launcher data.
- `new_git_fixture()` creates one mode-0700 temporary root, runs Git only with `-C` that root, exposes binary-safe `write`, `read`, `unlink`, `path`, `git`, `commit`, `status_bytes`, `object_count`, `identity`, `store`, and guarded `cleanup` methods, and registers cleanup before the first assertion.
- `fake_tracker_dependencies(overrides)` returns deterministic baseline and current objects, manual watcher and timer callbacks, loaded-buffer state, exact hashes, and no real user path.
- `fake_review_tracker()` implements the Task 7 and Task 8 tracker APIs over deterministic unresolved, conflicted, ignored, and binary records while recording every action and expected hash.
- `fake_incremental_reader(chunks)` returns each supplied byte chunk once with monotonically increasing offsets, and `fake_watch()` invokes only an explicitly triggered callback.
- `fake_components()` returns lazy identity, session, context, baseline, tracker, review, scope, registry, and status fakes plus an `order` array used by the Task 11 transaction assertion.
- `hash(bytes)` in review tests is exactly `vim.fn.sha256(bytes)`.
- Python `FakeUnixServer` owns one temporary mode-0700 directory, accepts exactly one Unix connection in one joined thread, bounds the request to 8192 bytes, and removes only its own directory in `__exit__`.

No fake may read provider state, call a live CLI, connect to a default tmux server, or use a path outside its fixture root.

---

### Task 1: Resolve companion identity and publish private state atomically

**Files:**

- Create: `.config/nvim/lua/ai/identity.lua`
- Create: `.config/nvim/lua/ai/tools.lua`
- Create: `.config/nvim/lua/ai/state.lua`
- Create: `.config/nvim/tests/ai_identity.lua`

**Interfaces:**

- Consumes: local buffer name, buffer type, Neovim working directory, `TMUX`, `TMUX_PANE`, and a synchronous `git rev-parse` result.
- Produces: `require("ai.identity").resolve(context) -> AiIdentity|nil, string|nil`.
- Produces: `require("ai.tools").resolve(name_or_path) -> string|nil, string|nil`, `revalidate(path) -> boolean, string|nil`, and `resolve_host(options) -> AiHostTools|nil, string|nil`.
- Produces: `require("ai.identity")._test.new(deps)` with injected filesystem, Git, environment, and hashing dependencies.
- Produces: `require("ai.state").open(identity) -> store|nil, string|nil`.
- Produces: `store:runtime_root()`, `store:state_root()`, `store:read_record()`, `store:write_record(record)`, `store:write_launch(manifest)`, `store:remove_launch(token)`, `store:review_dir(review_id)`, `store:read_control_token()`, `store:ensure_control_token()`, `store:remove_control_token()`, and `store:cleanup_contexts()`.

- [ ] **Step 1: Write the failing identity and state test**

Create `.config/nvim/tests/ai_identity.lua` with fixture helpers and these exact core assertions:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format(
    "%s\nexpected: %s\nactual: %s",
    label,
    vim.inspect(expected),
    vim.inspect(actual)
  ))
end

local identity = require("ai.identity")
local state = require("ai.state")
local tools = require("ai.tools")

eq(identity._test.valid_pane("%12"), true, "numeric pane")
eq(identity._test.valid_pane("12"), false, "missing pane sigil")
eq(identity._test.tmux_socket("/tmp/tmux-1000/default,123,4"), "/tmp/tmux-1000/default", "tmux socket")
eq(identity._test.tmux_socket("/tmp/with,comma,123,4"), "/tmp/with,comma", "tmux socket comma")
eq(identity._test.tmux_socket("invalid"), nil, "invalid tmux value")

local tool_fixture = tools._test.new({
  exepath = function(name) return name == "git" and "/usr/bin/git-link" or "" end,
  realpath = function(path) return path == "/usr/bin/git-link" and "/usr/bin/git" or nil end,
  lstat = function(path)
    return path == "/usr/bin/git" and { type = "file", mode = 493, uid = 0, dev = 41, ino = 92 } or nil
  end,
  uid = function() return 1000 end,
})
eq(tool_fixture:resolve("git"), "/usr/bin/git", "canonical host tool")

local calls = {}
local resolver = identity._test.new({
  env = { TMUX = "/tmp/tmux-1000/default,123,4", TMUX_PANE = "%12" },
  pid = function() return 77 end,
  nonce = function() return "77_99" end,
  cwd = function() return "/work/repo/src" end,
  buffer_name = function() return "/work/repo/src/main.lua" end,
  buffer_type = function() return "" end,
  realpath = function(path)
    local values = {
      ["/work/repo/src/main.lua"] = "/physical/repo/src/main.lua",
      ["/work/repo/src"] = "/physical/repo/src",
      ["/work/repo"] = "/physical/repo",
      ["/git/worktrees/repo"] = "/git/worktrees/repo",
      ["/git"] = "/git",
      ["/tmp/tmux-1000/default"] = "/tmp/tmux-1000/default",
    }
    return values[path]
  end,
  stat = function(path)
    if path == "/tmp/tmux-1000/default" then return { type = "socket", dev = 41, ino = 9001 } end
    return path:match("main.lua$") and { type = "file" } or { type = "directory" }
  end,
  find_git_entry = function() return nil end,
  git = function(start)
    table.insert(calls, start)
    return {
      code = 0,
      signal = 0,
      stdout = "/work/repo\n/git/worktrees/repo\n/git\n",
      stderr = "",
    }
  end,
  hash = function(value)
    eq(value, "tmux:/tmp/tmux-1000/default:41:9001\0%12\0/physical/repo", "identity hash input")
    return string.rep("a", 64)
  end,
})

eq(resolver:resolve(), {
  key = string.rep("a", 32),
  root = "/physical/repo",
  inside_git = true,
  git_dir = "/git/worktrees/repo",
  git_common_dir = "/git",
  git_entry = "/physical/repo/.git",
  owner_pane = "%12",
  tmux_socket = "/tmp/tmux-1000/default",
  namespace = "tmux:/tmp/tmux-1000/default:41:9001",
}, "linked-worktree identity")
eq(calls, { "/physical/repo/src" }, "nearest existing start")

local fallback = identity._test.new({
  env = {},
  pid = function() return 88 end,
  nonce = function() return "88_101" end,
  cwd = function() return "/plain/project" end,
  buffer_name = function() return "" end,
  buffer_type = function() return "" end,
  realpath = function(path) return path end,
  stat = function() return { type = "directory" } end,
  find_git_entry = function() return nil end,
  git = function() return { code = 128, signal = 0, stdout = "", stderr = "not a repository" } end,
  hash = function() return string.rep("b", 64) end,
})
local plain = assert(fallback:resolve())
eq(plain.root, "/plain/project", "non-Git root")
eq(plain.inside_git, false, "non-Git marker")
eq(plain.namespace, "nvim:88_101", "standalone namespace")
eq(plain.owner_pane, nil, "standalone owner")

local fixture = vim.fn.tempname()
assert(vim.fn.mkdir(fixture, "p", 448) == 1, "state fixture")
local store = assert(state._test.open({
  identity = plain,
  runtime_base = vim.fs.joinpath(fixture, "run"),
  state_base = vim.fs.joinpath(fixture, "state"),
  uid = vim.uv.getuid(),
}))

local record = {
  schema = 1,
  identity = {
    key = plain.key,
    root = plain.root,
    namespace = plain.namespace,
    owner_pane = vim.NIL,
  },
  active_backend = "claude",
  sessions = { codex = "last", claude = "00000000-0000-4000-8000-000000000000", opencode = "" },
  grants = {},
  review_id = vim.NIL,
}
assert(store:write_record(record))
eq(store:read_record(), record, "durable record round trip")
local control_token = assert(store:ensure_control_token(function() return string.rep("c", 32) end))
eq(control_token, string.rep("c", 32), "control token creation")
eq(store:read_control_token(), control_token, "control token read")
eq(store:ensure_control_token(function() error("must reuse token") end), control_token, "control token reuse")

for _, path in ipairs({ store:runtime_dir(), store:state_dir() }) do
  local stat = assert(vim.uv.fs_stat(path), "private directory missing")
  eq(stat.mode % 512, 448, "private directory mode")
  eq(stat.uid, vim.uv.getuid(), "private directory owner")
end
local record_stat = assert(vim.uv.fs_stat(store:record_path()), "record missing")
eq(record_stat.mode % 512, 384, "record mode")

local unsafe = vim.fs.joinpath(fixture, "unsafe")
assert(vim.uv.fs_symlink(store:state_dir(), unsafe), "state symlink fixture")
local rejected, rejected_error = state._test.open({
  identity = plain,
  runtime_base = vim.fs.joinpath(fixture, "run-2"),
  state_base = unsafe,
  uid = vim.uv.getuid(),
})
eq(rejected, nil, "symlinked state root rejected")
assert(tostring(rejected_error):find("symlink", 1, true), "symlink rejection detail")

assert(vim.fn.delete(fixture, "rf") == 0, "state fixture cleanup")
print("AI identity and state assertions: ok")
```

Add table-driven cases for a non-Git named buffer using the physical Neovim working directory as root, Git exit other than 0 or 128, a timed-out or signaled Git query, exit 128 with a `.git` entry above the start path, a malformed three-line Git result, a nonphysical Git path, an invalid hash, an invalid tmux pane, a nonexistent tmux socket, missing executables, noncanonical targets, symlink targets, nonregular tools, missing execute bits, group- or world-writable tools, control-containing paths, unsafe XDG ancestors, partial writes, directory-fsync failure, corrupt or oversized JSON, wrong ownership or mode, and a symlink race.

- [ ] **Step 2: Run the focused test and verify the missing modules fail**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_identity.lua
```

Expected: exit nonzero with `module 'ai.identity' not found`.

- [ ] **Step 3: Implement canonical host tools and identity resolution**

Create `.config/nvim/lua/ai/tools.lua` with no shell lookup.
Resolve a bare tool name only through `vim.fn.exepath`, resolve the result through `vim.uv.fs_realpath`, and use the canonical target for every later argv.
Require an absolute control-free path, a nonsymlink regular target, at least one executable bit, no group or other write bit, and an owner UID that is either the current user or a file for which `fs_access(..., "W")` is false.
Cache canonical path, device, inode, owner, type, and mode on first resolution.
`revalidate()` compares that complete tuple and rejects replacement or metadata drift.
`resolve_host()` resolves Git, Python 3, Bubblewrap, the configured absolute login shell, and tmux only when the identity claims tmux.
It returns no partial table when any required tool is invalid.
The runtime may accept injected paths only through `_test`; production never takes a tool path from a command argument, project file, or backend event.

Create `.config/nvim/lua/ai/identity.lua` with these exact validation and resolution rules:

```lua
local M = {}

local function valid_pane(value)
  return type(value) == "string" and value:match("^%%%d+$") ~= nil
end

local function tmux_socket(value)
  if type(value) ~= "string" then
    return nil
  end
  return value:match("^(.*),%d+,%d+$")
end

local function split_lines(value)
  local lines = {}
  for line in tostring(value or ""):gmatch("([^\n]*)\n?") do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  return lines
end

local function new(deps)
  local standalone_nonce
  local resolver = {}

  local function physical(path)
    if type(path) ~= "string" or path == "" or path:sub(1, 1) ~= "/" then
      return nil
    end
    return deps.realpath(path)
  end

  local function start_path(context)
    context = context or {}
    local name = context.name or deps.buffer_name()
    local buftype = context.buftype or deps.buffer_type()
    if buftype == "" and type(name) == "string" and name ~= "" then
      local absolute = vim.fs.normalize(vim.fs.abspath(name))
      local stat = deps.stat(absolute)
      local candidate = stat and stat.type == "directory" and absolute or vim.fs.dirname(absolute)
      local resolved = physical(candidate)
      if resolved then
        return resolved
      end
    end
    return assert(physical(context.cwd or deps.cwd()), "working directory is not physical")
  end

  function resolver:resolve(context)
    local start = start_path(context)
    local result = deps.git(start)
    local root, git_dir, git_common_dir
    if not result or result.signal ~= 0 or type(result.code) ~= "number" then
      return nil, "Git root query did not complete safely"
    end
    local inside_git = result.code == 0
    if inside_git then
      local lines = split_lines(result.stdout)
      if #lines ~= 3 then
        return nil, "Git root query returned an invalid shape"
      end
      root = physical(lines[1])
      git_dir = physical(lines[2])
      git_common_dir = physical(lines[3])
      if not root or not git_dir or not git_common_dir then
        return nil, "Git root query returned a nonphysical path"
      end
    else
      if result.code ~= 128 then
        return nil, "Git root query failed: " .. tostring(result.stderr or "")
      end
      if deps.find_git_entry(start) then
        return nil, "Git metadata exists but its worktree boundary could not be resolved"
      end
      root = physical(context and context.cwd or deps.cwd())
      if not root then
        return nil, "working directory is not physical"
      end
    end

    local raw_socket = tmux_socket(deps.env.TMUX)
    local pane = deps.env.TMUX_PANE
    local socket = raw_socket and physical(raw_socket) or nil
    local namespace
    local tmux_claimed = (type(deps.env.TMUX) == "string" and deps.env.TMUX ~= "")
      or (type(pane) == "string" and pane ~= "")
    if tmux_claimed and (not socket or not valid_pane(pane)) then
      return nil, "tmux identity is incomplete or invalid"
    end
    if tmux_claimed then
      local socket_stat = deps.stat(socket)
      if not socket_stat or socket_stat.type ~= "socket" or not socket_stat.dev or not socket_stat.ino then
        return nil, "tmux server socket identity is unavailable"
      end
      namespace = string.format("tmux:%s:%s:%s", socket, socket_stat.dev, socket_stat.ino)
    else
      standalone_nonce = standalone_nonce or deps.nonce()
      namespace = "nvim:" .. standalone_nonce
      pane = nil
      socket = nil
    end
    local key = deps.hash(table.concat({ namespace, pane or "", root }, "\0")):sub(1, 32)
    if not key:match("^[0-9a-f]+$") or #key ~= 32 then
      return nil, "identity hash is invalid"
    end
    return {
      key = key,
      root = root,
      inside_git = inside_git,
      git_dir = git_dir,
      git_common_dir = git_common_dir,
      git_entry = inside_git and vim.fs.joinpath(root, ".git") or nil,
      owner_pane = pane,
      tmux_socket = socket,
      namespace = namespace,
    }
  end

  return resolver
end

local git_executable = assert(require("ai.tools").resolve("git"))
local runtime = new({
  env = vim.env,
  pid = vim.fn.getpid,
  nonce = function()
    return string.format("%d_%d", vim.fn.getpid(), vim.uv.hrtime())
  end,
  cwd = function() return vim.fn.getcwd(0, 0) end,
  buffer_name = function() return vim.api.nvim_buf_get_name(0) end,
  buffer_type = function() return vim.bo.buftype end,
  realpath = vim.uv.fs_realpath,
  stat = vim.uv.fs_stat,
  find_git_entry = function(start)
    return vim.fs.find(".git", { path = start, upward = true, limit = 1 })[1]
  end,
  hash = vim.fn.sha256,
  git = function(start)
    return vim.system({
      git_executable, "-C", start, "rev-parse", "--path-format=absolute",
      "--show-toplevel", "--absolute-git-dir", "--git-common-dir",
    }, { text = true }):wait(2000)
  end,
})

function M.resolve(context)
  return runtime:resolve(context)
end

M._test = { new = new, tmux_socket = tmux_socket, valid_pane = valid_pane }
return M
```

- [ ] **Step 4: Implement private state and atomic JSON publication**

Create `.config/nvim/lua/ai/state.lua`.
Implement the tested API with these non-negotiable details:

```lua
local function validate_directory(path, uid, create)
  local before = vim.uv.fs_lstat(path)
  if before and before.type == "link" then
    return nil, "private state path is a symlink: " .. path
  end
  if not before and create then
    local ok, err = vim.uv.fs_mkdir(path, 448)
    if not ok and not tostring(err):find("EEXIST", 1, true) then
      return nil, "could not create private state path: " .. tostring(err)
    end
  end
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "directory" or stat.uid ~= uid or stat.mode % 512 ~= 448 then
    return nil, "private state path has unsafe ownership or mode: " .. path
  end
  return path
end

local function write_atomic(path, bytes, uid)
  local parent = vim.fs.dirname(path)
  local temporary = vim.fs.joinpath(parent, string.format(".%s.%d.%d", vim.fs.basename(path), vim.fn.getpid(), vim.uv.hrtime()))
  if vim.uv.fs_lstat(path) and vim.uv.fs_lstat(path).type == "link" then
    return nil, "refusing to replace a symlink: " .. path
  end
  local fd, open_error = vim.uv.fs_open(temporary, "wx", 384)
  if not fd then
    return nil, tostring(open_error)
  end
  local offset = 0
  local write_error
  while offset < #bytes do
    local wrote
    wrote, write_error = vim.uv.fs_write(fd, bytes:sub(offset + 1), offset)
    if not wrote or wrote <= 0 then break end
    offset = offset + wrote
  end
  local synced = offset == #bytes and vim.uv.fs_fsync(fd)
  vim.uv.fs_close(fd)
  if offset ~= #bytes or not synced then
    vim.uv.fs_unlink(temporary)
    return nil, tostring(write_error or "fsync failed")
  end
  local stat = vim.uv.fs_stat(temporary)
  if not stat or stat.uid ~= uid or stat.mode % 512 ~= 384 then
    vim.uv.fs_unlink(temporary)
    return nil, "temporary state file has unsafe metadata"
  end
  local renamed, rename_error = vim.uv.fs_rename(temporary, path)
  if not renamed then
    vim.uv.fs_unlink(temporary)
    return nil, tostring(rename_error)
  end
  local parent_fd = vim.uv.fs_open(parent, "r", 0)
  local parent_synced = parent_fd and vim.uv.fs_fsync(parent_fd)
  if parent_fd then vim.uv.fs_close(parent_fd) end
  if not parent_synced then
    return nil, "state directory fsync failed"
  end
  return true
end
```

Use `vim.json.encode` and `vim.json.decode` only after checking that a file is a nonsymlink regular file owned by the current UID with mode 0600 and size at most 1 MiB.
Create application-owned parents one component at a time and validate each application-owned component after creation.
Accept an existing XDG or home ancestor only when it is a nonsymlink directory and the resulting application path remains beneath its canonical path.
Keep runtime files under `${XDG_RUNTIME_DIR}/dotfiles-nvim-ai/<identity-key>` when XDG runtime is a current-user-owned mode-0700 directory.
When XDG runtime is absent, use `/tmp/dotfiles-nvim-ai-<uid>/<identity-key>` after creating or validating the UID-qualified application root as current-user-owned mode 0700.
Keep durable files under `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/nvim-ai/<identity-key>`.
Expose only the methods named in this task's interface.
Store the control token in a separate mode-0600 runtime file, never in the durable JSON record or a tmux option.
Retain that token across an ordinary Neovim shutdown and remove it only when the owning managed pane closes or is proven absent.

- [ ] **Step 5: Run formatting and the focused test**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/identity.lua \
  /home/ruohao/.config/nvim/lua/ai/tools.lua \
  /home/ruohao/.config/nvim/lua/ai/state.lua \
  /home/ruohao/.config/nvim/tests/ai_identity.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_identity.lua
```

Expected: formatting exits `0`, and the test prints exactly `AI identity and state assertions: ok` with exit `0`.

- [ ] **Step 6: Commit the identity and state boundary**

```sh
git add .config/nvim/lua/ai/identity.lua \
  .config/nvim/lua/ai/tools.lua \
  .config/nvim/lua/ai/state.lua \
  .config/nvim/tests/ai_identity.lua
git commit -m "feat(nvim): define AI companion identity"
```

### Task 2: Define backend adapters and capability-aware health

> **Execution amendment:** Codex and Claude in this task are implemented and retained.
> The historical OpenCode examples in this task are superseded by Tasks 1 through 3 of `.config/docs/superpowers/plans/2026-08-24-neovim-managed-opencode-profile.md` and must not be executed.

**Files:**

- Create: `.config/nvim/lua/ai/backends/init.lua`
- Create: `.config/nvim/lua/ai/backends/codex.lua`
- Create: `.config/nvim/lua/ai/backends/claude.lua`
- Create: `.config/nvim/lua/ai/backends/opencode.lua`
- Create: `.config/nvim/tests/ai_backends.lua`

**Interfaces:**

- Consumes: `AiIdentity`, per-identity backend state directories, session strings, and injected executable, version, port, password, and UUID providers.
- Produces: `registry.names() -> { "codex", "claude", "opencode" }`.
- Produces: `registry.get(name) -> adapter|nil`.
- Produces: `registry.health(name) -> { installed, executable, version, auth, capabilities, error }`.
- Produces: `adapter.new_session(identity, paths) -> AiBackendLaunch|nil, string|nil`.
- Produces: `adapter.resume_session(identity, paths, session) -> AiBackendLaunch|nil, string|nil`.
- Produces: `adapter.format_context(context) -> string`.
- Produces: `adapter.capabilities() -> table<string,boolean>`, `adapter.session_reference(launch) -> string`, `adapter.suspend() -> { signal=1, timeout=2000 }`, and `adapter.stop() -> { signal=15, timeout=2000 }`.

- [ ] **Step 1: Write the failing backend contract test**

Create `.config/nvim/tests/ai_backends.lua` with an injected registry and assert these exact launch shapes:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local registry_module = require("ai.backends")
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
  global_opencode_config = "/home/user/.config/opencode",
  global_opencode_data = "/home/user/.local/share/opencode",
  grants = {},
}

local registry = registry_module._test.new({
  executable = function(name) return "/usr/bin/" .. name end,
  version = function(name, executable) return { code = 0, signal = 0, stdout = name .. " 1.0\n", stderr = "" } end,
  auth = function(name, executable) return { code = 0, signal = 0, stdout = "authenticated\n", stderr = "" } end,
  uuid = function() return "11111111-1111-4111-8111-111111111111" end,
  port = function() return 43123 end,
  password = function() return "0123456789abcdef0123456789abcdef" end,
  stat = function() return { type = "file" } end,
})

local codex = assert(registry:get("codex"))
eq(codex:new_session(identity, paths), {
  kind = "direct",
  backend = "codex",
  argv = { "/usr/bin/codex", "-C", "/work/repo", "--sandbox", "workspace-write", "--ask-for-approval", "on-request" },
  env = { CODEX_HOME = "/state/identity/backends/codex" },
  session = "last",
  capabilities = { approval = false, busy = false, completion = false, exact_session = false },
  read_only_inputs = {
    { source = "/home/user/.codex/auth.json", destination = "/state/identity/backends/codex/auth.json", kind = "file" },
    { source = "/home/user/.codex/config.toml", destination = "/state/identity/backends/codex/config.toml", kind = "file" },
  },
  protected_paths = { "/home/user/.codex", "/usr/bin/codex" },
}, "Codex new session")

eq(codex:resume_session(identity, paths, "last").argv, {
  "/usr/bin/codex", "resume", "--last", "-C", "/work/repo", "--sandbox", "workspace-write", "--ask-for-approval", "on-request",
}, "Codex isolated resume")

paths.backend_state = "/state/identity/backends/claude"
local claude = assert(registry:get("claude"))
local claude_launch = assert(claude:new_session(identity, paths))
eq(claude_launch.session, "11111111-1111-4111-8111-111111111111", "Claude UUID")
eq(claude_launch.argv, {
  "/usr/bin/claude", "--session-id", "11111111-1111-4111-8111-111111111111", "--permission-mode", "acceptEdits",
}, "Claude new session")
eq(claude_launch.env.CLAUDE_CONFIG_DIR, "/state/identity/backends/claude", "Claude isolated config")
eq(claude_launch.capabilities, { approval = true, busy = true, completion = true, exact_session = true }, "Claude capabilities")
eq(claude:resume_session(identity, paths, claude_launch.session).argv, {
  "/usr/bin/claude", "--resume", "11111111-1111-4111-8111-111111111111", "--permission-mode", "acceptEdits",
}, "Claude resume")

paths.backend_state = "/state/identity/backends/opencode"
local opencode = assert(registry:get("opencode"))
local opencode_launch = assert(opencode:new_session(identity, paths))
eq(opencode_launch.kind, "server_attach", "OpenCode launch kind")
eq(opencode_launch.server_argv, { "/usr/bin/opencode", "serve", "--hostname", "127.0.0.1", "--port", "43123" }, "OpenCode server")
eq(opencode_launch.attach_argv, { "/usr/bin/opencode", "attach", "http://127.0.0.1:43123", "--dir", "/work/repo" }, "OpenCode attach")
eq(opencode_launch.env.OPENCODE_SERVER_PASSWORD, "0123456789abcdef0123456789abcdef", "OpenCode password")
eq(opencode_launch.env.XDG_DATA_HOME, "/state/identity/backends/opencode/xdg-data", "OpenCode isolated data")
eq(opencode_launch.env.XDG_CACHE_HOME, "/state/identity/backends/opencode/xdg-cache", "OpenCode isolated cache")
eq(opencode_launch.capabilities, { approval = true, busy = true, completion = true, exact_session = true }, "OpenCode capabilities")

eq(codex:format_context({ kind = "location", path = "lua/main.lua", line = 7, column = 3 }), "Regarding lua/main.lua:7:3: ", "Codex location context")
eq(claude:format_context({ kind = "selection", path = "lua/main.lua", first = 7, last = 9, context_file = "/run/context/abc.txt" }), "Use the exact selection from lua/main.lua:7-9 stored at /run/context/abc.txt: ", "Claude selection context")

for _, name in ipairs(registry_module.names()) do
  local health = registry:health(name)
  eq(health.installed, true, name .. " installed")
  assert(type(health.version) == "string" and health.version ~= "", name .. " version")
  assert(type(health.capabilities) == "table", name .. " capabilities")
end

print("AI backend adapter assertions: ok")
```

- [ ] **Step 2: Run the backend test and verify the missing registry fails**

Run:

```sh
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_backends.lua
```

Expected: exit nonzero with `module 'ai.backends' not found`.

- [ ] **Step 3: Implement the common registry**

Create `.config/nvim/lua/ai/backends/init.lua` with a fixed backend order, injected constructors, and no dynamic plugin loading:

```lua
local names = { "codex", "claude", "opencode" }

local function read_only_probe(bwrap, command)
  local argv = {
    bwrap, "--new-session", "--unshare-pid", "--unshare-ipc", "--unshare-uts", "--unshare-net",
    "--die-with-parent", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp", "--",
  }
  vim.list_extend(argv, command)
  local env = vim.fn.environ()
  env.TMUX = nil
  env.TMUX_PANE = nil
  env.NVIM = nil
  return vim.system(argv, { text = true, timeout = 2000, clear_env = true, env = env }):wait()
end

local function guarded_probe(command)
  local bwrap, err = require("ai.tools").resolve("bwrap")
  if not bwrap then
    return { code = 127, signal = 0, stdout = "", stderr = err }
  end
  return read_only_probe(bwrap, command)
end

local function new(deps)
  local adapters = {
    codex = require("ai.backends.codex").new(deps),
    claude = require("ai.backends.claude").new(deps),
    opencode = require("ai.backends.opencode").new(deps),
  }
  return {
    names = function() return vim.deepcopy(names) end,
    get = function(_, name) return adapters[name] end,
    health = function(_, name)
      local adapter = adapters[name]
      if not adapter then
        return { installed = false, executable = "", version = "", auth = "unknown", capabilities = {}, error = "unknown backend" }
      end
      return adapter:health()
    end,
  }
end

local runtime = new({
  executable = function(name) return require("ai.tools").resolve(name) end,
  version = function(name, executable)
    return guarded_probe({ executable, "--version" })
  end,
  auth = function(name, executable)
    local commands = {
      codex = { executable, "login", "status" },
      claude = { executable, "auth", "status", "--json" },
      opencode = { executable, "providers", "list" },
    }
    return guarded_probe(commands[name])
  end,
  uuid = function()
    local bytes = assert(vim.uv.random(16))
    local values = { bytes:byte(1, 16) }
    values[7] = (values[7] % 16) + 64
    values[9] = (values[9] % 64) + 128
    local function hex_slice(first, last)
      local parts = {}
      for index = first, last do
        parts[#parts + 1] = string.format("%02x", values[index])
      end
      return table.concat(parts)
    end
    return table.concat({
      hex_slice(1, 4),
      hex_slice(5, 6),
      hex_slice(7, 8),
      hex_slice(9, 10),
      hex_slice(11, 16),
    }, "-")
  end,
  port = function()
    local socket = assert(vim.uv.new_tcp())
    assert(socket:bind("127.0.0.1", 0))
    local name = assert(socket:getsockname())
    socket:close()
    return assert(name.port)
  end,
  password = function() return vim.fn.sha256(assert(vim.uv.random(32))):sub(1, 32) end,
})

return {
  names = function() return vim.deepcopy(names) end,
  get = function(name) return runtime:get(name) end,
  health = function(name) return runtime:health(name) end,
  _test = { new = new },
}
```

The final helper must produce a lowercase RFC-4122 version-4 UUID and the focused test must assert its pattern.

- [ ] **Step 4: Implement the three adapters**

Create one focused module per backend.
Each module returns `{ new = function(deps) ... end }`, validates session strings before placing them in argv, and returns fresh tables on every call.
Canonicalize the detected executable with `vim.uv.fs_realpath`, require an executable regular file, and place only that absolute canonical path in launch argv.
Pass that canonical executable to injected version, authentication, and help probes, and include it in `protected_paths` so Bubblewrap read-only self-binds the exact program even when it lives below a writable project or grant.
Validate `paths.grants` as an already canonical sorted unique string list and rebuild backend argv on every review or grant relaunch.

Use these exact policies:

```lua
-- Codex
local common = { "-C", identity.root, "--sandbox", "workspace-write", "--ask-for-approval", "on-request" }
-- New: { absolute_executable, unpack(common) }
-- Resume: { absolute_executable, "resume", "--last", unpack(common) }
-- Append one { "--add-dir", GRANT } pair per sorted canonical grant.
-- CODEX_HOME is the identity-specific backend_state path.
-- Mount existing global auth.json and config.toml read-only over the same names in CODEX_HOME.
-- Protect the complete existing global CODEX_HOME at its original path with a read-only self-bind.

-- Claude
-- New: ABSOLUTE_CLAUDE --session-id UUID --permission-mode acceptEdits
-- Resume: ABSOLUTE_CLAUDE --resume UUID --permission-mode acceptEdits
-- Append one { "--add-dir", GRANT } pair per sorted canonical grant.
-- The adapter writes an ephemeral additional-settings file path into env.CLAUDE_CODE_ADDITIONAL_SETTINGS.
-- CLAUDE_CONFIG_DIR is the identity-specific backend_state path.
-- Mount an existing global settings.json read-only at backend_state/settings.json.
-- Protect the global Claude config directory and existing ~/.claude.json at their original paths with read-only self-binds.

-- OpenCode
-- Server: ABSOLUTE_OPENCODE serve --hostname 127.0.0.1 --port PORT
-- Attach: ABSOLUTE_OPENCODE attach http://127.0.0.1:PORT --dir ROOT
-- Resume appends --session SESSION to attach argv only when SESSION is nonempty.
-- OPENCODE_SERVER_PASSWORD is a 32-character lowercase hexadecimal secret.
-- XDG_DATA_HOME is backend_state/xdg-data and XDG_CACHE_HOME is backend_state/xdg-cache.
-- Mount existing auth.json, mcp-auth.json, and account.json from the global OpenCode data directory read-only at the corresponding isolated data paths.
-- Protect the global OpenCode config and data directories at their original paths with read-only self-binds.
```

All adapters must return a health object even when absent.
An absent executable yields `installed=false` without running version or authentication commands.
An authentication command failure yields `auth="unknown"` with a bounded diagnostic and does not mutate CLI state.
Strip controls and bound version and error text to 256 bytes.
Implement `read_only_probe(argv)` with Bubblewrap, a read-only `/`, private `/tmp`, hidden tmux environment, and `--unshare-net` so version and authentication inspection cannot write global CLI state or contact a provider.
Resolve Bubblewrap to a canonical absolute executable before every probe, reject a symlink or group- or world-writable program, and use that exact path as argv element zero.
If Bubblewrap is unavailable or the read-only probe fails, return a health error and do not retry the command unconfined.
Probe each installed CLI's local `--help` through the same boundary and require the exact launch, resume, permission, additional-directory, server, attach, session, and password flags used by its adapter.
Report an incompatible installed version as disabled rather than attempting a guessed argv.
Omit a read-only input whose source does not exist, but reject a source with the wrong type, a symlink, unsafe ownership, or unsafe mode.
Every destination must be a canonical descendant of the identity-specific backend-state directory.

- [ ] **Step 5: Run formatting and backend tests**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/backends \
  /home/ruohao/.config/nvim/tests/ai_backends.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_backends.lua
```

Expected: formatting exits `0`, and the test prints exactly `AI backend adapter assertions: ok` with exit `0`.

- [ ] **Step 6: Commit the backend contract**

```sh
git add .config/nvim/lua/ai/backends \
  .config/nvim/tests/ai_backends.lua
git commit -m "feat(nvim): define AI CLI adapters"
```

### Task 3: Build and prove the Bubblewrap launch boundary

> **Execution amendment:** Tasks 4 and 5 of `.config/docs/superpowers/plans/2026-08-24-neovim-managed-opencode-profile.md` are the execution version of this task and require every original confinement invariant plus the managed-profile boundary.
> After those tasks pass both reviews, continue with Task 4 below.

**Files:**

- Create: `.config/nvim/lua/ai/sandbox.lua`
- Create: `.config/nvim/scripts/nvim-ai-launch.py`
- Create: `.config/nvim/tests/ai_sandbox.lua`
- Create: `.config/nvim/tests/nvim_ai_launch.py`
- Create: `.config/nvim/tests/nvim-ai-sandbox.sh`

**Interfaces:**

- Consumes: `AiIdentity`, `AiBackendLaunch`, state-store paths, canonical Python and Bubblewrap executables, fixed launcher and helper paths, current environment, current shell, context directory, control socket, and canonical grants.
- Produces: `sandbox.prepare(options) -> { token, path, argv, command, manifest }|nil, string|nil`.
- Produces: `sandbox.validate_grants(identity, grants) -> string[]|nil, string|nil`.
- Produces: launcher CLI `nvim-ai-launch.py --manifest ABSOLUTE_MODE_0600_JSON`.
- Produces: pure Python `validate_manifest(data, metadata)` and `build_bwrap_argv(manifest, launch_argv=None)` functions for isolated tests.

- [ ] **Step 1: Write failing Lua manifest tests**

Create `.config/nvim/tests/ai_sandbox.lua`.
Use a private fixture state store and assert this exact mount-policy model:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local sandbox = require("ai.sandbox")
local identity = {
  key = string.rep("a", 32), root = "/work/repo", inside_git = true,
  git_dir = "/git/worktrees/repo", git_common_dir = "/git", git_entry = "/work/repo/.git", owner_pane = "%12",
  tmux_socket = "/tmp/tmux-1000/default", namespace = "tmux:/tmp/tmux-1000/default:41:9001",
}
local launch = {
  kind = "direct", backend = "claude", argv = { "/usr/bin/claude", "--session-id", "id" },
  env = {}, session = "id", capabilities = {}, read_only_inputs = {}, protected_paths = {},
}
local prepared = assert(sandbox._test.prepare({
  identity = identity,
  launch = launch,
  writable = false,
  grants = {},
  token = string.rep("b", 32),
  runtime_root = "/run/ai",
  state_root = "/state/ai",
  context_dir = "/run/ai/context",
  backend_state_dir = "/state/ai/backend",
  control_socket = "/run/ai/control.sock",
  control_token = string.rep("d", 32),
  control_helper = "/config/nvim/scripts/nvim-ai-control.py",
  event_helper = "/config/nvim/scripts/nvim-ai-event.py",
  review_helper = "/config/nvim/scripts/nvim-ai-review.py",
  event_file = "/state/ai/backend/events.ndjson",
  launcher = "/config/nvim/scripts/nvim-ai-launch.py",
  python = "/usr/bin/python3",
  bwrap = "/usr/bin/bwrap",
  host_tools = { "/usr/bin/git", "/usr/bin/tmux" },
  shell = "/bin/zsh",
  write_manifest = function(manifest)
    return "/run/ai/launch/" .. manifest.token .. ".json"
  end,
}))
eq(prepared.path, "/run/ai/launch/" .. string.rep("b", 32) .. ".json", "manifest path")
eq(prepared.argv, { "/usr/bin/python3", "-I", "-B", "/config/nvim/scripts/nvim-ai-launch.py", "--manifest", prepared.path }, "launcher argv")
eq(prepared.manifest.writable, false, "read-only launch")
eq(prepared.manifest.git_dir, "/git/worktrees/repo", "Git mask")
eq(prepared.manifest.tmux_socket, "/tmp/tmux-1000/default", "tmux mask")
eq(prepared.manifest.bwrap, "/usr/bin/bwrap", "canonical Bubblewrap")
eq(prepared.manifest.python, "/usr/bin/python3", "canonical Python")
eq(prepared.manifest.host_tools, { "/usr/bin/git", "/usr/bin/tmux" }, "protected host tools")
assert(prepared.command:match("^exec '[^']+' %-I %-B '[^']+' %-%-manifest '[^']+'$"), "fixed tmux command shape")

local writable = assert(sandbox._test.prepare({
  identity = identity,
  launch = launch,
  writable = true,
  review_id = "review_0123456789abcdef",
  grants = { "/outside/one", "/outside/two" },
  token = string.rep("c", 32),
  runtime_root = "/run/ai",
  state_root = "/state/ai",
  context_dir = "/run/ai/context",
  backend_state_dir = "/state/ai/backend",
  control_socket = "/run/ai/control.sock",
  control_token = string.rep("d", 32),
  control_helper = "/config/nvim/scripts/nvim-ai-control.py",
  event_helper = "/config/nvim/scripts/nvim-ai-event.py",
  review_helper = "/config/nvim/scripts/nvim-ai-review.py",
  event_file = "/state/ai/backend/events.ndjson",
  launcher = "/config/nvim/scripts/nvim-ai-launch.py",
  python = "/usr/bin/python3",
  bwrap = "/usr/bin/bwrap",
  host_tools = { "/usr/bin/git", "/usr/bin/tmux" },
  shell = "/bin/zsh",
  write_manifest = function(manifest) return "/run/ai/launch/" .. manifest.token .. ".json" end,
}))
eq(writable.manifest.grants, { "/outside/one", "/outside/two" }, "sorted grants")

for _, invalid in ipairs({ "", "/", "relative", "/path/../escape" }) do
  local value, err = sandbox._test.validate_grants(identity, { invalid }, {
    realpath = function(path) return path end,
    stat = function() return { type = "directory" } end,
  })
  eq(value, nil, "invalid grant " .. vim.inspect(invalid))
  assert(type(err) == "string" and err ~= "", "invalid grant detail")
end

print("AI sandbox manifest assertions: ok")
```

- [ ] **Step 2: Write failing Python launcher tests**

Create `.config/nvim/tests/nvim_ai_launch.py` with `unittest` and import the launcher by absolute file path through `importlib.util.spec_from_file_location`.
Cover these exact cases:

```python
def fixture_metadata(mode=0o600, uid=None):
    return {
        "is_symlink": False,
        "is_regular": True,
        "mode": mode,
        "uid": os.getuid() if uid is None else uid,
        "size": 1024,
    }


def windows(values, width):
    return [values[index:index + width] for index in range(0, len(values) - width + 1)]


def fixture_manifest(writable=False, grants=None):
    return {
        "schema": 1,
        "token": "b" * 32,
        "identity_key": "a" * 32,
        "root": "/work/repo",
        "git_dir": "/git/worktrees/repo",
        "git_common_dir": "/git",
        "git_entry": "/work/repo/.git",
        "writable": writable,
        "grants": list(grants or []),
        "review_id": "review_0123456789abcdef" if writable else None,
        "runtime_root": "/run/user/1000/nvim-ai",
        "state_root": "/state/ai",
        "context_dir": "/run/user/1000/nvim-ai/context",
        "backend_state_dir": "/state/ai/backend",
        "control_socket": "/run/user/1000/nvim-ai/control.sock",
        "control_token": "d" * 32,
        "control_helper": "/config/nvim/scripts/nvim-ai-control.py",
        "event_helper": "/config/nvim/scripts/nvim-ai-event.py",
        "launcher": "/config/nvim/scripts/nvim-ai-launch.py",
        "review_helper": "/config/nvim/scripts/nvim-ai-review.py",
        "event_file": "/state/ai/backend/events.ndjson",
        "tmux_socket": "/run/user/1000/tmux/default",
        "python": "/usr/bin/python3",
        "bwrap": "/usr/bin/bwrap",
        "host_tools": ["/usr/bin/git", "/usr/bin/tmux"],
        "shell": "/bin/zsh",
        "launch": {
            "kind": "direct",
            "backend": "codex",
            "argv": ["/usr/bin/codex", "-C", "/work/repo"],
            "server_argv": None,
            "attach_argv": None,
            "env": {"CODEX_HOME": "/state/ai/backend"},
            "session": "last",
            "capabilities": {"approval": False, "busy": False, "completion": False, "exact_session": False},
            "read_only_inputs": [
                {"source": "/home/user/.codex/auth.json", "destination": "/state/ai/backend/auth.json", "kind": "file"},
            ],
            "protected_paths": ["/home/user/.codex", "/usr/bin/codex"],
            "event_url": None,
            "event_file": None,
        },
    }


class ManifestTests(unittest.TestCase):
    def test_read_only_mount_order_masks_project_and_tmux(self):
        manifest = fixture_manifest(writable=False)
        argv = launcher.build_bwrap_argv(manifest)
        self.assertEqual(argv[:5], ["/usr/bin/bwrap", "--new-session", "--unshare-pid", "--unshare-ipc", "--unshare-uts"])
        root_bind = argv.index("/work/repo", argv.index("--ro-bind") + 1)
        self.assertEqual(argv[root_bind - 1], "--ro-bind")
        self.assertIn(["--ro-bind", "/dev/null", "/run/user/1000/tmux/default"], windows(argv, 3))
        self.assertIn(["--ro-bind", "/git/worktrees/repo", "/git/worktrees/repo"], windows(argv, 3))
        self.assertIn(["--ro-bind", "/git", "/git"], windows(argv, 3))
        self.assertNotIn(["--bind", "/work/repo", "/work/repo"], windows(argv, 3))

    def test_writable_batch_and_grant_are_exact_binds(self):
        manifest = fixture_manifest(writable=True, grants=["/outside/one"])
        argv = launcher.build_bwrap_argv(manifest)
        self.assertIn(["--bind", "/work/repo", "/work/repo"], windows(argv, 3))
        self.assertIn(["--bind", "/outside/one", "/outside/one"], windows(argv, 3))
        self.assertGreater(windows(argv, 3).index(["--ro-bind", "/git", "/git"]), windows(argv, 3).index(["--bind", "/work/repo", "/work/repo"]))

    def test_manifest_rejects_unknown_keys_and_unsafe_metadata(self):
        manifest = fixture_manifest()
        manifest["unknown"] = True
        with self.assertRaisesRegex(ValueError, "manifest keys"):
            launcher.validate_manifest(manifest, fixture_metadata())
        with self.assertRaisesRegex(ValueError, "0600"):
            launcher.validate_manifest(fixture_manifest(), fixture_metadata(mode=0o644))
        with self.assertRaisesRegex(ValueError, "owner"):
            launcher.validate_manifest(fixture_manifest(), fixture_metadata(uid=os.getuid() + 1))

    def test_environment_is_allowlisted(self):
        manifest = fixture_manifest()
        env = launcher.build_environment(manifest, {"PATH": "/usr/bin", "HOME": "/home/u", "TERM": "xterm-256color", "SECRET": "no"})
        self.assertEqual(env["PATH"], "/usr/bin")
        self.assertEqual(env["HOME"], "/home/u")
        self.assertEqual(env["TERM"], "xterm-256color")
        self.assertNotIn("SECRET", env)
        manifest["launch"]["env"]["CLAUDE_TOKEN"] = "must-not-pass"
        with self.assertRaisesRegex(ValueError, "adapter environment"):
            launcher.build_environment(manifest, {"PATH": "/usr/bin", "HOME": "/home/u"})
```

The manifest fixture must match `AiLaunchManifest` exactly and contain no production credentials.

- [ ] **Step 3: Run both focused tests and verify missing implementations fail**

Run:

```sh
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_sandbox.lua
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_launch.py
```

Expected: the Lua test fails on missing `ai.sandbox`, and the Python test fails because `nvim-ai-launch.py` is absent.

- [ ] **Step 4: Implement the Lua manifest builder**

Create `.config/nvim/lua/ai/sandbox.lua`.
Validate exact keys, token pattern `^[0-9a-f]{32}$`, canonical paths, backend launch shape, grant uniqueness, grant sort order, and the read-only versus writable root flag.
The command string passed to tmux contains only shell-quoted fixed executable paths and the generated manifest path.
Use this quoting function and reject controls before calling it:

```lua
local function shell_quote(value)
  assert(type(value) == "string" and value ~= "" and not value:find("[%z\1-\31\127]"), "unsafe launcher value")
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function launcher_command(python, launcher, manifest)
  return table.concat({ "exec", shell_quote(python), "-I", "-B", shell_quote(launcher), "--manifest", shell_quote(manifest) }, " ")
end
```

`prepare()` writes the manifest through the injected state store before returning argv or command data.
If publication fails, return the exact state-store error and no launch invocation.
Resolve and validate the Python interpreter, Bubblewrap, login shell, launcher, and three helper paths before publication, and copy those exact canonical values into the manifest.

- [ ] **Step 5: Implement strict Python manifest validation and Bubblewrap argv construction**

Create executable `.config/nvim/scripts/nvim-ai-launch.py` with no third-party imports.
Keep import-time behavior inert so the test can import it.
Use `argparse`, `json`, `os`, `pathlib`, `signal`, `socket`, `stat`, `subprocess`, `sys`, and `time` only.

The exact high-level argv order is:

```python
def build_bwrap_argv(manifest, launch_argv=None):
    if launch_argv is None:
        launch_argv = manifest["launch"]["argv"]
    if not launch_argv:
        raise ValueError("a concrete backend argv is required")
    root = manifest["root"]
    argv = [
        manifest["bwrap"],
        "--new-session",
        "--unshare-pid",
        "--unshare-ipc",
        "--unshare-uts",
        "--die-with-parent",
        "--ro-bind", "/", "/",
        "--dev", "/dev",
        "--proc", "/proc",
        "--tmpfs", "/tmp",
    ]
    argv += ["--bind" if manifest["writable"] else "--ro-bind", root, root]
    for grant in manifest["grants"]:
        argv += ["--bind" if manifest["writable"] else "--ro-bind", grant, grant]
    trusted = [
        manifest["python"], manifest["bwrap"], manifest["launcher"], manifest["review_helper"],
        manifest["control_helper"], manifest["event_helper"], manifest["shell"], *manifest["host_tools"],
    ]
    for protected in unique_paths(manifest["runtime_root"], manifest["state_root"], *trusted, *manifest["launch"]["protected_paths"]):
        argv += ["--ro-bind", protected, protected]
    argv += ["--bind", manifest["backend_state_dir"], manifest["backend_state_dir"]]
    for item in manifest["launch"]["read_only_inputs"]:
        argv += ["--ro-bind", item["source"], item["destination"]]
    for git_path in unique_paths(manifest.get("git_entry"), manifest.get("git_dir"), manifest.get("git_common_dir")):
        argv += ["--ro-bind", git_path, git_path]
    if manifest.get("tmux_socket"):
        argv += ["--ro-bind", "/dev/null", manifest["tmux_socket"]]
    argv += ["--ro-bind", manifest["context_dir"], manifest["context_dir"]]
    argv += ["--ro-bind", os.path.dirname(manifest["control_socket"]), os.path.dirname(manifest["control_socket"])]
    argv += ["--chdir", root, "--unsetenv", "TMUX", "--unsetenv", "TMUX_PANE", "--"]
    argv += launch_argv
    return argv
```

Deduplicate nested Git masks while preserving the deepest path first.
Mask the exact tmux socket with a `/dev/null` read-only bind after every root and grant bind, even when it is below `/tmp`, because a project or grant bind can otherwise re-expose it.
Create required destination parents inside the sandbox namespace with `--dir` before binding a root, runtime path, or state path that lives below the private `/tmp`.
Reject a grant equal to `/`, a noncanonical path, a missing path, or a path containing controls.
Reject manifest files that are symlinks, not regular, not current-user-owned, not mode 0600, larger than 1 MiB, or contain unknown keys.
Require `bwrap` to be an absolute canonical nonsymlink executable owned by root or the current user and not writable by group or other, then use only that exact path as argv element zero.
Apply the same canonical executable and ownership policy to `python` and `shell`.
Require `host_tools` to be a sorted unique list containing the exact canonical Git path and, in tmux mode, the exact canonical tmux path supplied by `ai.tools`.
Require `launcher` to match the canonical file currently executing, and validate `launcher`, `review_helper`, `control_helper`, and `event_helper` as exact canonical nonsymlink regular files with safe ownership and mode.
Read-only self-bind all seven trusted executables and helper files after any writable root or grant bind, so an agent cannot replace a future launch, scope, event, or review boundary even when those files live inside the project root.
After a complete validated read, unlink the exact manifest path before starting Bubblewrap so a launch token cannot be replayed or read from the pane's process argv later.
Refuse `writable=true` when `review_id` is missing from the manifest.
Require `control_token` to be exactly 32 lowercase hexadecimal characters without publishing it outside the mode-0600 manifest and sandbox environment.
Validate every read-only input source as a nonsymlink existing file or directory under the adapter's declared global provider root.
Validate every read-only input destination as the same kind and a canonical descendant of `backend_state_dir`.
Create absent destination mount points safely before entering Bubblewrap, and fail closed rather than replacing an existing symlink or wrong-kind object.
Validate `runtime_root` and `state_root` as the Task 1 application-owned roots and read-only self-bind both after any writable project or grant bind.
Validate each adapter `protected_paths` entry as an existing canonical nonsymlink current-user-owned provider path or the already validated absolute executable, reject `/`, and read-only self-bind it at its original path.
Apply the backend-state writable bind only after those private and provider protections so identity-specific session data remains the sole exception.

Allow only `PATH`, `HOME`, `USER`, `LOGNAME`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TERM`, `COLORTERM`, `NO_COLOR`, certificate variables, and upper- or lowercase proxy variables from the parent environment.
Reject NUL, control-containing, or larger-than-8192-byte environment names or values rather than truncating them.
Allow backend adapter overrides only for `CODEX_HOME`, `CLAUDE_CODE_ADDITIONAL_SETTINGS`, `CLAUDE_CONFIG_DIR`, `OPENCODE_SERVER_PASSWORD`, `OPENCODE_SERVER_USERNAME`, `XDG_DATA_HOME`, and `XDG_CACHE_HOME`.
Require `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `XDG_DATA_HOME`, and `XDG_CACHE_HOME` to be canonical descendants of `backend_state_dir`.
Reject every other adapter environment key.

For `kind="direct"`, run Bubblewrap in the foreground.
For `kind="server_attach"`, start the Bubblewrap-wrapped server with stdout and stderr redirected to mode-0600 files in the backend state directory, poll `127.0.0.1:PORT` for at most five seconds, then run the attach argv through a second Bubblewrap invocation as the native TUI client.
Start every child with `close_fds=True` and pass only stdin, stdout, stderr, and the explicit backend environment so no inherited tmux or Neovim descriptor crosses the boundary.
On TUI exit, terminate and wait for the server.
Forward `SIGTERM`, `SIGINT`, and `SIGHUP` to active children.
Immediately after a managed backend process starts, append one normalized `open` record to the mode-0600 event file with backend and exact session only.
On unexpected start or exit failure, append one normalized `failed` record before showing the diagnostic.
Use the same bounded append primitive as Task 10's event helper and never include argv, environment, prompt, output, or credentials.
After any managed backend exit, print one bounded diagnostic line and `exec` a new read-only Bubblewrap invocation of the configured login shell.
If Bubblewrap itself cannot start, print one bounded diagnostic and wait in a fixed noninteractive process rather than exposing an unconfined shell.

- [ ] **Step 6: Add the real Bubblewrap filesystem harness**

Create executable `.config/nvim/tests/nvim-ai-sandbox.sh`.
The harness must create one mode-0700 private root, one fake project, one ungranted sibling directory, one separate approved-grant directory, one symlink-escape target, one fake Git administration directory, one private context directory, one backend state directory, and one fake backend executable.
Use the existing nonsymlink executable `/bin/true` as the unused control, event, and review helper mount source in these confinement-only manifests, use the real canonical launcher path as `launcher`, and create a mode-0600 empty event file in backend state.
Resolve canonical Python and Bubblewrap paths before building each manifest and assert that the fake backend cannot modify either executable or any of the four trusted helper paths.
The fake backend receives paths through fixed environment variables and attempts these writes:

```sh
project_root=$1
sibling_root=$2
git_root=$3
backend_state=$4
tmux_socket=$5
grant_root=$6
grant_policy=$7
root_policy=$8
if printf inside >"$project_root/inside.txt" 2>/dev/null; then
  [ "$root_policy" = allow ] || exit 27
else
  [ "$root_policy" = deny ] || exit 28
fi
if printf sibling >"$sibling_root/outside.txt" 2>/dev/null; then exit 21; fi
if printf git >"$git_root/config" 2>/dev/null; then exit 22; fi
if printf escape >"$project_root/escape/outside.txt" 2>/dev/null; then exit 23; fi
printf cache >"$backend_state/cache.txt"
[ ! -S "$tmux_socket" ] || exit 24
if printf grant >"$grant_root/granted.txt" 2>/dev/null; then
  [ "$grant_policy" = allow ] || exit 25
else
  [ "$grant_policy" = deny ] || exit 26
fi
```

Pass these fixed test paths as fake-backend argv, not environment overrides.
Make `escape` a symlink to the separate ungranted escape target before launch.
Run one read-only manifest and assert that `inside.txt` is absent.
Run one writable manifest and assert that only `inside.txt` and backend `cache.txt` exist.
Run one approved-grant manifest against the separate grant directory and assert that the exact granted write succeeds while sibling, Git, and symlink-escape writes remain denied.
For each run, make the fake backend write a mode-0600 completion sentinel in backend state, start the launcher in the background, poll that sentinel for at most five seconds, send `SIGTERM` to the exact launcher process after assertions, and wait for it so the confined diagnostic shell cannot keep the test alive.
Use a trap that removes only the harness-owned root and leaves no process.

- [ ] **Step 7: Run static, unit, and real confinement tests**

Run:

```sh
chmod 700 /home/ruohao/.config/nvim/scripts/nvim-ai-launch.py \
  /home/ruohao/.config/nvim/tests/nvim-ai-sandbox.sh
stylua /home/ruohao/.config/nvim/lua/ai/sandbox.lua \
  /home/ruohao/.config/nvim/tests/ai_sandbox.lua
python3 -I -B -c 'import ast,pathlib,sys; [ast.parse(pathlib.Path(item).read_text(encoding="utf-8"), filename=item) for item in sys.argv[1:]]' \
  /home/ruohao/.config/nvim/scripts/nvim-ai-launch.py \
  /home/ruohao/.config/nvim/tests/nvim_ai_launch.py
shellcheck /home/ruohao/.config/nvim/tests/nvim-ai-sandbox.sh
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_sandbox.lua
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_launch.py
env -u TMUX -u TMUX_PANE /home/ruohao/.config/nvim/tests/nvim-ai-sandbox.sh
```

Expected: all commands exit `0`; the Lua test prints `AI sandbox manifest assertions: ok`; Python prints an `OK` unittest summary; the shell test prints `ok - nvim AI Bubblewrap boundary`.
Verify no Python `__pycache__` exists or is staged before committing.

- [ ] **Step 8: Commit the launch boundary**

```sh
git add .config/nvim/lua/ai/sandbox.lua \
  .config/nvim/scripts/nvim-ai-launch.py \
  .config/nvim/tests/ai_sandbox.lua \
  .config/nvim/tests/nvim_ai_launch.py \
  .config/nvim/tests/nvim-ai-sandbox.sh
git commit -m "feat(nvim): confine AI CLI processes"
```

### Task 4: Create safe tmux and terminal transports

**Files:**

- Create: `.config/nvim/lua/ai/transports/tmux.lua`
- Create: `.config/nvim/lua/ai/transports/terminal.lua`
- Create: `.config/nvim/tests/ai_transport.lua`

**Interfaces:**

- Consumes: `AiIdentity`, `AiHostTools`, the `{ command, argv }` launcher invocation returned by `sandbox.prepare`, validated pane handles, and exact text to paste.
- Produces: `require("ai.transports.tmux").new(options) -> AiTransport`.
- Produces: `require("ai.transports.terminal").new(options) -> AiTransport`.
- Extends `AiTransport` with `tag(pane, metadata) -> boolean, string|nil` and `shutdown() -> nil`.
- Uses tmux metadata names `@dotfiles_nvim_ai`, `@dotfiles_nvim_ai_key`, `@dotfiles_nvim_ai_owner`, `@dotfiles_nvim_ai_root`, `@dotfiles_nvim_ai_backend`, `@dotfiles_nvim_ai_state`, `@dotfiles_nvim_ai_grants`, `@dotfiles_nvim_ai_session`, `@dotfiles_nvim_ai_opencode_token`, `@dotfiles_nvim_ai_opencode_fingerprint`, and `@dotfiles_nvim_ai_opencode_version`.
- Represents a terminal fallback handle as `term:<buffer-number>:<job-number>` and never persists that handle.

- [ ] **Step 1: Write the failing transport test**

Create `.config/nvim/tests/ai_transport.lua` with a fake command runner and fake terminal API.
The core assertions must be these:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local tmux_module = require("ai.transports.tmux")
local terminal_module = require("ai.transports.terminal")
local identity = {
  key = string.rep("a", 32),
  root = "/work/repo",
  inside_git = true,
  git_dir = "/git/worktrees/repo",
  git_common_dir = "/git",
  git_entry = "/work/repo/.git",
  owner_pane = "%12",
  tmux_socket = "/tmp/tmux-1000/default",
  namespace = "tmux:/tmp/tmux-1000/default:41:9001",
}

local calls = {}
local results = {
  { code = 0, signal = 0, stdout = "%30\t1\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t%12\t/work/repo\tclaude\topen\t0\t11111111-1111-4111-8111-111111111111\t\t\t\n%31\t1\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t%12\t/work/repo\tclaude\topen\t0\t11111111-1111-4111-8111-111111111111\t\t\t\n", stderr = "" },
  { code = 0, signal = 0, stdout = "%40\n", stderr = "" },
  { code = 0, signal = 0, stdout = "", stderr = "" },
  { code = 0, signal = 0, stdout = "", stderr = "" },
  { code = 0, signal = 0, stdout = "", stderr = "" },
  { code = 0, signal = 0, stdout = "", stderr = "" },
  { code = 0, signal = 0, stdout = "", stderr = "" },
  { code = 0, signal = 0, stdout = "", stderr = "" },
}
local transport = tmux_module._test.new({
  tmux = "/usr/bin/tmux",
  run = function(argv, options)
    table.insert(calls, { argv = vim.deepcopy(argv), stdin = options and options.stdin or nil })
    return table.remove(results, 1)
  end,
  nonce = function() return "77_99" end,
  hold_command = "exec '/usr/bin/sleep' '2147483647'",
  width = 40,
})

local panes = assert(transport:discover(identity))
eq(vim.tbl_map(function(item) return item.pane end, panes), { "%30", "%31" }, "duplicates remain visible")
eq(calls[1].argv, {
  "/usr/bin/tmux", "-S", "/tmp/tmux-1000/default", "list-panes", "-a", "-F",
  "#{pane_id}\t#{@dotfiles_nvim_ai}\t#{@dotfiles_nvim_ai_key}\t#{@dotfiles_nvim_ai_owner}\t#{@dotfiles_nvim_ai_root}\t#{@dotfiles_nvim_ai_backend}\t#{@dotfiles_nvim_ai_state}\t#{@dotfiles_nvim_ai_grants}\t#{@dotfiles_nvim_ai_session}\t#{@dotfiles_nvim_ai_opencode_token}\t#{@dotfiles_nvim_ai_opencode_fingerprint}\t#{@dotfiles_nvim_ai_opencode_version}",
}, "discovery argv")
eq(panes[1].grants, "0", "discovery retains grant hash")
eq(panes[1].session, "11111111-1111-4111-8111-111111111111", "discovery retains session")

local invocation = {
  command = "exec '/usr/bin/python3' -I -B '/config/nvim/scripts/nvim-ai-launch.py' --manifest '/run/launch.json'",
  argv = { "/usr/bin/python3", "-I", "-B", "/config/nvim/scripts/nvim-ai-launch.py", "--manifest", "/run/launch.json" },
}
local pane = assert(transport:create(identity, invocation))
eq(pane, "%40", "created pane")
eq(calls[2].argv, {
  "/usr/bin/tmux", "-S", "/tmp/tmux-1000/default", "split-window", "-h", "-p", "40", "-d", "-P", "-F", "#{pane_id}",
  "-t", "%12", "-c", "/work/repo", "exec '/usr/bin/sleep' '2147483647'",
}, "right-hand split argv")
eq(calls[4].argv, {
  "/usr/bin/tmux", "-S", "/tmp/tmux-1000/default", "respawn-pane", "-k", "-t", "%40", invocation.command,
}, "tagged pane starts launcher")
assert(transport:tag("%40", {
  key = identity.key, owner = "%12", root = "/work/repo", backend = "claude",
  state = "starting", grants = "0", session = "11111111-1111-4111-8111-111111111111",
  opencode_token = "", opencode_fingerprint = "", opencode_version = "",
}))
assert(transport:paste("%40", "Regarding lua/main.lua:7:3: "))
eq(calls[6].argv, {
  "/usr/bin/tmux", "-S", "/tmp/tmux-1000/default", "load-buffer", "-b",
  "dotfiles-nvim-ai-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-77_99", "-",
}, "named paste buffer load")
eq(calls[6].stdin, "Regarding lua/main.lua:7:3: ", "paste bytes use stdin")

local terminal_calls = {}
local terminal = terminal_module._test.new({
  create = function(root, argv)
    table.insert(terminal_calls, { operation = "create", root = root, argv = argv })
    return 8, 91
  end,
  focus = function(bufnr) table.insert(terminal_calls, { operation = "focus", bufnr = bufnr }) return true end,
  send = function(job, bytes) table.insert(terminal_calls, { operation = "send", job = job, bytes = bytes }) return true end,
  stop = function(job) table.insert(terminal_calls, { operation = "stop", job = job }) return true end,
})
eq(terminal:create(identity, invocation), "term:8:91", "terminal handle")
assert(terminal:paste("term:8:91", "selection reference"))
eq(terminal_calls[2], { operation = "send", job = 91, bytes = "selection reference" }, "terminal paste has no carriage return")

print("AI transport assertions: ok")
```

Add failure cases for an invalid pane, a missing tmux socket, malformed discovery output, a tag failure, split cleanup after tag failure, duplicate pane metadata, `load-buffer` failure, `paste-buffer` failure, guaranteed `delete-buffer`, and a stale terminal handle.
The fake runner must assert that every tmux call contains `-S identity.tmux_socket` and therefore cannot reach the default server.

- [ ] **Step 2: Run the focused test and verify both modules are missing**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_transport.lua
```

Expected: exit nonzero with `module 'ai.transports.tmux' not found`.

- [ ] **Step 3: Implement the tmux transport**

Create `.config/nvim/lua/ai/transports/tmux.lua` around one injected `run(argv, options)` function.
Receive the canonical tmux executable from `AiHostTools`, revalidate its metadata before every lifecycle mutation, and never resolve it again through `PATH`.
Use this exact validation and argv construction core:

```lua
local metadata_names = {
  marker = "@dotfiles_nvim_ai",
  key = "@dotfiles_nvim_ai_key",
  owner = "@dotfiles_nvim_ai_owner",
  root = "@dotfiles_nvim_ai_root",
  backend = "@dotfiles_nvim_ai_backend",
  state = "@dotfiles_nvim_ai_state",
  grants = "@dotfiles_nvim_ai_grants",
  session = "@dotfiles_nvim_ai_session",
  opencode_token = "@dotfiles_nvim_ai_opencode_token",
  opencode_fingerprint = "@dotfiles_nvim_ai_opencode_fingerprint",
  opencode_version = "@dotfiles_nvim_ai_opencode_version",
}

local function valid_pane(value)
  return type(value) == "string" and value:match("^%%%d+$") ~= nil
end

local function safe_metadata(name, value)
  value = tostring(value or "")
  if name == "root" then
    value = value:gsub("([^A-Za-z0-9._/-])", function(byte)
      return string.format("%%%02X", string.byte(byte))
    end)
  end
  local limits = {
    key = 32, owner = 16, root = 1024, backend = 16, state = 32, grants = 16, session = 128,
    opencode_token = 32, opencode_fingerprint = 64, opencode_version = 16,
  }
  if value:find("[%z\1-\31\127]") or #value > assert(limits[name]) then
    return nil, "unsafe tmux AI metadata: " .. name
  end
  if name == "key" and not value:match("^[0-9a-f]+$") then return nil, "invalid identity key" end
  if name == "owner" and not valid_pane(value) then return nil, "invalid owner pane" end
  if name == "root" and value:sub(1, 1) ~= "/" then return nil, "invalid physical root" end
  if name == "backend" and not ({ codex = true, claude = true, opencode = true })[value] then return nil, "invalid backend" end
  if name == "grants" and value ~= "0" and (#value ~= 16 or not value:match("^[0-9a-f]+$")) then return nil, "invalid grant hash" end
  return value
end

local function base(identity)
  assert(type(identity.tmux_socket) == "string" and identity.tmux_socket:sub(1, 1) == "/", "missing tmux socket")
  return { assert(deps.tmux), "-S", identity.tmux_socket }
end

local function split_argv(identity, command, width)
  local argv = base(identity)
  vim.list_extend(argv, {
    "split-window", "-h", "-p", tostring(width), "-d", "-P", "-F", "#{pane_id}",
    "-t", assert(identity.owner_pane), "-c", identity.root, command,
  })
  return argv
end
```

`discover()` must run `list-panes -a` once, parse exactly the twelve tab-separated fields from the focused test, validate and percent-decode the bounded root, retain every exact marker, key, owner, and root match, and return each candidate's validated backend, state, grant hash, session, and OpenCode profile reference with the whole matching list.
It must reject any malformed matching record instead of silently ignoring it.
Require all three OpenCode fields to be empty for Codex and Claude.
For OpenCode, require a 32-character lowercase hexadecimal token, a 64-character lowercase hexadecimal fingerprint, and exact version `1.18.18`.
Add a synthetic OpenCode discovery row and tag call that round-trip those exact values, plus rejection cases for a partial or malformed profile tuple and a non-OpenCode backend carrying any profile value.
`create()` must split a passive fixed `sleep` holder, validate the returned pane, tag marker, key, owner, root, and `starting` state, then respawn the tagged pane with `invocation.command`.
It must kill only that newly created pane when initial tagging or launcher respawn fails.
`tag()` must use one multi-command tmux argv with `set-option -pt` and literal argv elements, never a shell command string.
Before appending a tmux value that ends in `;`, replace only that final byte with `\;`, matching the existing `integrations.tmux_status` argv separator defense.
Initial tagging must also set per-pane `remain-on-exit` to `on` so a signaled launcher leaves a respawnable pane.
Encode no grants as `0` and a nonempty grant set as the first 16 lowercase hexadecimal characters of SHA-256 over its sorted canonical paths joined by NUL.
`focus()` uses `select-pane -t PANE`.
For a managed backend replacement, `respawn()` queries the exact decimal `#{pane_pid}`, sends the adapter's signal through injected `kill(pid, signal)`, and polls `#{pane_dead}` for at most the adapter's 2000-millisecond timeout.
It then uses `respawn-pane -k -t PANE COMMAND`, where `-k` is only the bounded fallback for a process that ignored the graceful signal.
For the initial passive holder, use `policy.force=true` and respawn immediately.
`close()` applies the adapter stop policy, waits through the same bounded dead-pane check, then uses `kill-pane -t PANE` only for a pane that still has the exact managed identity key.
The terminal transport maps the same suspend and stop policies to the owned job and waits before forcing `jobstop`.

`paste()` must run these three calls in order and pass text only as stdin to `load-buffer`:

```lua
local buffer = "dotfiles-nvim-ai-" .. identity.key .. "-" .. deps.nonce()
run(with_base({ "load-buffer", "-b", buffer, "-" }), { text = true, stdin = text, timeout = 2000 })
run(with_base({ "paste-buffer", "-b", buffer, "-t", pane }), { text = true, timeout = 2000 })
run(with_base({ "delete-buffer", "-b", buffer }), { text = true, timeout = 500 })
```

The cleanup call is required after either earlier call fails.
Refuse empty, control-containing, or larger-than-2048-byte paste text before creating the tmux buffer.
Treat cleanup failure as a visible transport failure and retry only the exact named-buffer deletion once.
Do not call `send-keys` anywhere in this module.

- [ ] **Step 4: Implement the standalone terminal transport**

Create `.config/nvim/lua/ai/transports/terminal.lua` with the same high-level methods.
Use `vim.cmd.vsplit()`, a 40-percent right-hand window width, `vim.fn.termopen(argv, { cwd = identity.root })`, `vim.fn.chansend(job, text)`, and `vim.fn.jobstop(job)` behind injected functions.
Pass `invocation.argv` directly to `termopen` after rejecting empty or control-containing elements.
`paste()` passes the exact text bytes without `\r`, `\n`, or any submit key.
`discover()` returns the one live module-owned handle or an empty list.
`shutdown()` stops and wipes only the module-owned terminal buffer because standalone companions cannot survive Neovim exit.

- [ ] **Step 5: Run formatting and transport tests**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/transports \
  /home/ruohao/.config/nvim/tests/ai_transport.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_transport.lua
```

Expected: formatting exits `0`, and the test prints exactly `AI transport assertions: ok` with exit `0`.

- [ ] **Step 6: Commit the transport boundary**

```sh
git add .config/nvim/lua/ai/transports \
  .config/nvim/tests/ai_transport.lua
git commit -m "feat(nvim): add AI companion transports"
```

### Task 5: Coordinate one pane and one resumable session per backend

**Files:**

- Create: `.config/nvim/lua/ai/session.lua`
- Modify: `.config/nvim/lua/ai/state.lua`
- Modify: `.config/nvim/tests/ai_transport.lua`
- Modify: `.config/nvim/tests/ai_identity.lua`

**Interfaces:**

- Consumes: `AiIdentity`, `AiHostTools`, `AiTransport`, backend registry adapters, `sandbox.prepare`, and the Task 1 state store.
- Produces: `require("ai.session").new(options) -> coordinator`.
- Produces: `coordinator:attach()`, `coordinator:open(backend)`, `coordinator:switch(backend)`, `coordinator:prepare_review(review_id)`, `coordinator:finish_review(review_id)`, `coordinator:set_grants(grants)`, `coordinator:paste(text)`, `coordinator:close()`, `coordinator:shutdown()`, and `coordinator:snapshot()`.
- Produces: `coordinator:subscribe(callback) -> unsubscribe` for common state changes.
- Keeps `sessions.codex`, `sessions.claude`, and `sessions.opencode` in the durable record even when another backend is active.
- Keeps `opencode_profile` as either JSON null or the exact public `{ token, fingerprint, version }` reference for the active surviving OpenCode process.

- [ ] **Step 1: Add failing coordinator tests**

Append coordinator cases to `.config/nvim/tests/ai_transport.lua` with fake transport, state, backend, and sandbox objects.
Use this exact state sequence:

```lua
local session_module = require("ai.session")
local events = {}
local record = {
  schema = 1,
  identity = { key = identity.key, root = identity.root, namespace = identity.namespace, owner_pane = identity.owner_pane },
  active_backend = "claude",
  sessions = { codex = "last", claude = "11111111-1111-4111-8111-111111111111", opencode = "" },
  grants = {},
  review_id = vim.NIL,
  opencode_profile = vim.NIL,
}
local fake_transport = fake_transport_for(identity)
local fake_sandbox_boundary = fake_sandbox()
local coordinator = session_module._test.new({
  identity = identity,
  transport = fake_transport,
  registry = fake_registry(),
  store = fake_store(record),
  sandbox = fake_sandbox_boundary,
  confirm = function() return true end,
  notify = function() end,
})
coordinator:subscribe(function(snapshot) table.insert(events, snapshot.state) end)

assert(coordinator:open("claude"))
eq(fake_transport.calls[1].operation, "create", "first launch creates pane")
eq(fake_sandbox_boundary.manifests[1].writable, false, "plain open is read-only")
eq(coordinator:snapshot().state, "open", "opened state")

assert(coordinator:prepare_review("review_0123456789abcdef"))
eq(fake_transport.calls[#fake_transport.calls].operation, "respawn", "review relaunch")
eq(fake_sandbox_boundary.manifests[#fake_sandbox_boundary.manifests].writable, true, "review root is writable")
eq(fake_sandbox_boundary.manifests[#fake_sandbox_boundary.manifests].review_id, "review_0123456789abcdef", "exact review binds launch")

assert(coordinator:switch("opencode"))
eq(coordinator:snapshot().backend, "opencode", "backend switched")
eq(coordinator:snapshot().pane, fake_transport.pane, "backend reuses pane")
eq(fake_transport.created, 1, "only one pane created")
eq(coordinator:snapshot().opencode_profile, {
  token = string.rep("b", 32), fingerprint = string.rep("c", 64), version = "1.18.18",
}, "managed profile reference retained")

assert(coordinator:finish_review("review_0123456789abcdef"))
eq(fake_sandbox_boundary.manifests[#fake_sandbox_boundary.manifests].writable, false, "resolved review relaunches read-only")
eq(coordinator:snapshot().review_id, nil, "review cleared")
eq(coordinator:snapshot().opencode_profile.fingerprint, string.rep("c", 64), "review relaunch reuses profile")

coordinator:shutdown()
eq(fake_transport.closed, 0, "Neovim shutdown preserves tmux pane")
assert(coordinator:close())
eq(fake_transport.closed, 1, "explicit close removes pane")
eq(coordinator:snapshot().grants, {}, "close revokes grants")
```

Configure the fake OpenCode adapter to return a managed launch whose public reference is the token, fingerprint, and version above.
Add exact cases for a unique discovered pane reconnect, duplicate refusal listing both pane IDs, stale metadata, failed record decode, missing active backend, unavailable backend, startup failure, unexpected exit, failed writable relaunch rollback, a rich `busy` switch requiring confirmation, a common-state switch without confirmation, grant persistence across backend switch, and standalone shutdown closing its terminal.
Add separate reconnect refusals for a changed pane token, fingerprint, version, durable reference, missing profile generation, changed profile manifest, wrong physical root, and an `inspect-profile` helper failure.
Assert that every refusal leaves the pane untouched, disables prompt transfer, emits no sensitive path or file contents, and requires explicit restart or close.
Assert that close after a refused attach requires confirmation, kills only the one exact identity-matching pane, clears the stale profile reference, and lets the next open publish a fresh profile.

- [ ] **Step 2: Run the focused test and verify the coordinator is missing**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_transport.lua
```

Expected: exit nonzero with `module 'ai.session' not found` after the transport assertions reach the new coordinator section.

- [ ] **Step 3: Implement the session state machine**

Create `.config/nvim/lua/ai/session.lua` with this exact transition table and no terminal-output parsing:

```lua
local transitions = {
  closed = { starting = true, paused = true },
  starting = { open = true, failed = true, closed = true },
  open = { starting = true, attention = true, changes = true, conflicted = true, failed = true, closed = true },
  idle = { starting = true, busy = true, attention = true, changes = true, conflicted = true, failed = true, closed = true },
  busy = { starting = true, idle = true, approval = true, completed = true, changes = true, conflicted = true, failed = true },
  approval = { busy = true, idle = true, completed = true, failed = true },
  completed = { idle = true, busy = true, changes = true, conflicted = true, failed = true },
  attention = { open = true, starting = true, changes = true, conflicted = true, failed = true },
  changes = { open = true, starting = true, conflicted = true, closed = true },
  conflicted = { starting = true, conflicted = true, closed = true },
  failed = { starting = true, closed = true },
  paused = { starting = true, closed = true },
}
```

Keep the conflict latch outside this table.
When `conflicts > 0`, `snapshot().state` remains `conflicted` until the review tracker reports zero conflicts or the batch is abandoned.

Amend the pre-integration schema-1 durable record in `.config/nvim/lua/ai/state.lua` to require the `opencode_profile` field.
Accept only JSON null or a table with exactly `token`, `fingerprint`, and `version`, where token is 32 lowercase hexadecimal characters, fingerprint is 64 lowercase hexadecimal characters, and version is exactly `1.18.18`.
Reject a non-null profile unless `active_backend == "opencode"`, while allowing an OpenCode backend with a null profile before its first launch or after explicit close.
Update every state fixture in `.config/nvim/tests/ai_identity.lua`, test rejection of missing, extra, and malformed profile fields, and retain the existing atomic publication and rollback assertions.
This is a correction to the not-yet-integrated schema-1 shape, not an on-disk migration.

Use one `launch(backend, mode)` helper for first launch, resume, backend switch, grant change, and review transition.
The helper must:

1. Resolve the backend-specific durable session reference.
2. Build backend paths with the current sorted canonical grants, then call `new_session` only when no valid session reference exists and otherwise call `resume_session`.
   Resolve the original inherited home and optional XDG data root once through canonical current-user-owned directory checks, set `home_agents` to the exact home `AGENTS.md` child, and set `global_opencode_data` to the exact `opencode` child of `${XDG_DATA_HOME:-$HOME/.local/share}`.
   Pass `paths.opencode_profile` only while relaunching the same already-active OpenCode pane for a review or grant transition.
   A new activation, backend switch into OpenCode, or explicit close-and-reopen passes no profile reference and therefore creates a fresh generation.
3. Call `sandbox.prepare` with `writable = review_id ~= nil`, the exact review ID, and the current grants.
   Pass the Task 1 runtime and durable application roots so the launcher re-masks all Neovim-owned state after a writable project bind.
   Pass the canonical Python, Bubblewrap, shell, launcher, review helper, control helper, and event helper paths plus the sorted canonical Git and optional tmux host-tool list so the launcher can validate and protect every future control boundary.
4. Reuse the pane-stable control token from `store:ensure_control_token()` across backend switches, review relaunches, grants, and ordinary Neovim reopen.
5. Persist the returned backend session reference before process creation.
   For OpenCode, derive and validate the exact public profile reference from the prepared launch and persist it in the same durable-record write.
   For Codex and Claude, require and persist `opencode_profile = vim.NIL`.
6. Create a pane only when none exists and otherwise call `respawn` on the same pane.
   Pass `adapter:suspend()` for backend switch, review transition, and grant transition; pass `adapter:stop()` for explicit close.
7. Tag the pane with bounded nonsecret metadata after a successful create or respawn.
   Tag all three exact OpenCode profile fields for OpenCode and clear all three for Codex and Claude.
   If tagging fails, stop the just-started managed process before rolling state back and report cleanup failure without adopting the pane.
8. Roll the durable record and in-memory snapshot back when any step fails.
   When failure occurs after stopping the prior process, rebuild its prior validated launch, respawn and retag it with the prior profile tuple, and restore durable state only after that recovery succeeds.
   If process recovery fails, retain a truthful `failed` snapshot and bounded diagnostic instead of claiming rollback.
9. Let the launcher unlink a successfully validated one-time manifest and remove it from Neovim only when process creation fails before the launcher can read it.

`attach()` must focus neither pane nor window.
It accepts exactly one discovered pane whose identity metadata and durable record agree.
It requires the decoded root, backend, and backend-specific session reference to agree with the durable record, validates the bounded state before seeding the snapshot, and reports stale metadata instead of silently overwriting either side.
For OpenCode, it requires the pane token, fingerprint, and version to equal the durable reference, then calls `adapter:validate_profile()` with the exact identity and physical root to securely re-open and verify that generation before adoption.
For Codex and Claude, it requires both the durable profile reference and all three pane profile fields to be empty.
It never rebuilds a profile during attach, so credential or instruction changes take effect only after an explicit OpenCode restart creates and tags a fresh generation.
A profile mismatch leaves the surviving pane untouched and blocks focus-independent prompt transfer until explicit restart or close.
It compares the pane's bounded grant hash with the durable grant list and refuses prompt transfer until a mismatch is reconciled by a confirmed sandbox relaunch.
If a surviving pane's control-token file is missing, reconnect keeps the pane visible but requires an explicit relaunch with a new token before scope requests can work; it never fabricates a token for the already running process.
It returns an error naming all pane IDs when discovery returns more than one match.
It does not start or resume a backend during reconnection.
When discovery proves that no managed pane exists, it clears stale grants and the old control token before creating a new pane.
It also clears a stale OpenCode profile reference so the following explicit open creates a fresh generation.

`open()` focuses a uniquely attached pane or launches the requested backend.
`switch()` requests confirmation only when the current adapter has `busy=true` and the current rich state is `busy` or `approval`.
The confirmation text must name both backend names and state that the same pane will resume a different session.
`prepare_review()` refuses a second review ID, relaunches with writable root, and persists the ID only if relaunch succeeds.
When no pane exists yet, `prepare_review()` persists the ID without launching, and the following `open()` creates the pane directly in writable review mode.
`finish_review()` requires the exact current review ID, relaunches read-only, clears grants only when the pane is being closed, and clears the review ID only if relaunch succeeds.
When the managed pane is already closed, it clears the resolved review ID and baseline without launching a backend.
`set_grants()` relaunches with the same review ID and backend and never pastes or submits text.
`shutdown()` leaves a tmux pane and its backend alone but tears down subscriptions.
`close()` closes the owned pane, calls `store:cleanup_contexts()`, removes the control token, clears all grants, launch manifests, and the active OpenCode profile reference, retains the three session references, and writes `review_id` unchanged when unresolved.
After a refused attach, `close()` may stop and remove exactly one identity-matching pane only after revalidating its pane ID, marker, owner, and physical root and obtaining explicit confirmation; close followed by open is the explicit managed-profile restart path.

- [ ] **Step 4: Run formatting and coordinator tests**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/session.lua \
  /home/ruohao/.config/nvim/lua/ai/state.lua \
  /home/ruohao/.config/nvim/tests/ai_transport.lua \
  /home/ruohao/.config/nvim/tests/ai_identity.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_transport.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_identity.lua
```

Expected: both focused tests exit `0` and print their exact success lines.

- [ ] **Step 5: Commit the session coordinator**

```sh
git add .config/nvim/lua/ai/session.lua \
  .config/nvim/lua/ai/state.lua \
  .config/nvim/tests/ai_transport.lua \
  .config/nvim/tests/ai_identity.lua
git commit -m "feat(nvim): coordinate AI CLI sessions"
```

### Task 6: Preserve exact explicit context without submitting prompts

**Files:**

- Create: `.config/nvim/lua/ai/context.lua`
- Create: `.config/nvim/tests/ai_context.lua`

**Interfaces:**

- Consumes: current buffer, cursor, visual marks, visual mode, `AiIdentity`, backend `format_context`, and the Task 1 state store.
- Produces: `context.location(identity, bufnr, cursor) -> context|nil, string|nil`.
- Produces: `context.selection(identity, bufnr, marks) -> context|nil, string|nil`.
- Produces: `context.prepare(options) -> { text, file, metadata }|nil, string|nil`.
- Produces: `context:supersede()`, `context:consumed(path)`, and `context:cleanup()`.
- Leaves prompt submission to the native backend TUI and never returns a newline-terminated paste.

- [ ] **Step 1: Write failing exact-context tests**

Create `.config/nvim/tests/ai_context.lua`.
Use real scratch buffers for byte preservation and an injected private-file writer for metadata.
The core cases must be these:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local context_module = require("ai.context")
local identity = { key = string.rep("a", 32), root = "/work/repo" }
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, "/work/repo/lua/main.lua")
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local café = 1", "\talpha beta", "return café" })
vim.bo[bufnr].modified = true

local writes = {}
local context = context_module._test.new({
  write_private = function(name, bytes)
    table.insert(writes, { name = name, bytes = bytes, mode = 384 })
    return "/run/ai/context/" .. name
  end,
  unlink = function() return true end,
  nonce = function() return "77_99" end,
  getregion = vim.fn.getregion,
  getregionpos = vim.fn.getregionpos,
})

eq(context:location(identity, bufnr, { 1, 7 }), {
  kind = "location", path = "lua/main.lua", line = 1, column = 8,
}, "normal location is relative and one-based")

local characterwise = assert(context:selection(identity, bufnr, {
  first = { bufnr, 1, 7, 0 }, last = { bufnr, 1, 10, 0 }, mode = "v", inclusive = true,
}))
eq(writes[#writes].bytes, "café", "characterwise UTF-8 bytes")
eq(characterwise.path, "lua/main.lua", "selection source path")
eq(characterwise.context_file, "/run/ai/context/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-77_99.txt", "private context path")

local linewise = assert(context:selection(identity, bufnr, {
  first = { bufnr, 1, 1, 0 }, last = { bufnr, 2, 1, 0 }, mode = "V", inclusive = true,
}))
eq(writes[#writes].bytes, "local café = 1\n\talpha beta\n", "linewise bytes")

local blockwise = assert(context:selection(identity, bufnr, {
  first = { bufnr, 2, 2, 0 }, last = { bufnr, 3, 6, 0 }, mode = "\22", inclusive = true,
}))
eq(blockwise.kind, "selection", "blockwise selection")
assert(writes[#writes].bytes:find("alpha", 1, true), "blockwise text omitted selected bytes")

local unnamed = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { "unsaved secret" })
local explicit = assert(context:selection(identity, unnamed, {
  first = { unnamed, 1, 1, 0 }, last = { unnamed, 1, 7, 0 }, mode = "v", inclusive = true,
}))
eq(explicit.path, "[No Name]", "non-file visual context")
eq(context:location(identity, unnamed, { 1, 0 }), nil, "non-file normal context refused")

print("AI context assertions: ok")
```

Add cases for exclusive selection, reversed marks, tabs, combining characters, a multibyte final character, a selection outside the pinned root, a named non-file buffer, writer failure, superseding the previous file, proven consumption, pane-close cleanup, and context text containing quotes, newlines, shell syntax, terminal escapes, and a final newline.
Add relative source paths containing percent, tab, newline, carriage return, escape, and non-ASCII bytes; assert the pasted reference remains one printable line and identifies the path through uppercase percent encoding.
Assert every written file name contains only the identity key, nonce, and `.txt`, and every recorded mode is 0600.

- [ ] **Step 2: Run the focused test and verify the context module is missing**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_context.lua
```

Expected: exit nonzero with `module 'ai.context' not found`.

- [ ] **Step 3: Implement normal and visual context extraction**

Create `.config/nvim/lua/ai/context.lua`.
Use Neovim 0.12 `getregion()` for visual extraction so tabs, multibyte characters, inclusive or exclusive selection, and blockwise regions follow Neovim's own selection semantics:

```lua
local function selected_bytes(deps, bufnr, marks)
  local options = {
    type = marks.mode,
    exclusive = marks.inclusive == false,
  }
  local lines = vim.api.nvim_buf_call(bufnr, function()
    return deps.getregion(marks.first, marks.last, options)
  end)
  if type(lines) ~= "table" or #lines == 0 then
    return nil, "visual selection is empty"
  end
  local bytes = table.concat(lines, "\n")
  if marks.mode == "V" then
    bytes = bytes .. "\n"
  end
  if #bytes > 4 * 1024 * 1024 then
    return nil, "visual selection exceeds the 4 MiB context limit"
  end
  return bytes
end

local function encode_source(value)
  return (value:gsub("([^A-Za-z0-9._/-])", function(byte)
    return string.format("%%%02X", string.byte(byte))
  end))
end

local function relative_path(identity, bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then return "[No Name]" end
  if vim.bo[bufnr].buftype ~= "" then return encode_source(vim.fs.basename(name)) end
  local physical = vim.uv.fs_realpath(name) or vim.fs.normalize(vim.fs.abspath(name))
  local relative = vim.fs.relpath(identity.root, physical)
  if type(relative) ~= "string" or relative == ".." or relative:match("^%.%./") then
    return nil, "buffer is outside the pinned companion root"
  end
  return encode_source(relative)
end
```

Normal context returns only relative path, one-based line, and one-based byte column.
The relative path in a pasted reference is UTF-8 byte-wise percent encoded outside `[A-Za-z0-9._/-]`, including percent itself, so no filename can add a control or submit key.
It rejects unnamed and non-file buffers before creating a review batch.
Visual context allows unnamed and non-file buffers because the explicit bytes are copied into the private file.
It writes through the Task 1 state store using exclusive creation, mode 0600, fsync, and a nonsymlink check.
It returns a short metadata table and never places selected text in durable state, tmux options, command argv, environment values, or logs.
Require every adapter's formatted context to contain no C0 or C1 control, end without carriage return or newline, and remain at most 2048 bytes before transport paste.

Track at most one unconsumed context file per companion.
Delete the older file only after the newer file has been published successfully.
Delete a file after a structured backend event proves the turn ended, when superseded, or when the pane closes.
When consumption cannot be proven, retain it until superseded or pane close.

- [ ] **Step 4: Format and run context tests**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/context.lua \
  /home/ruohao/.config/nvim/tests/ai_context.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_context.lua
```

Expected: the test prints exactly `AI context assertions: ok` with exit `0`.

- [ ] **Step 5: Commit explicit context handling**

```sh
git add .config/nvim/lua/ai/context.lua \
  .config/nvim/tests/ai_context.lua
git commit -m "feat(nvim): prepare explicit AI context"
```

### Task 7: Capture exact Git-visible baselines and classify writers

**Files:**

- Create: `.config/nvim/lua/ai/review/baseline.lua`
- Create: `.config/nvim/lua/ai/review/tracker.lua`
- Create: `.config/nvim/tests/ai_review.lua`

**Interfaces:**

- Consumes: `AiIdentity`, the canonical Git path from `AiHostTools`, Task 1 review directories, Git command results, filesystem objects, Neovim buffer state, and debounced filesystem signals.
- Produces: `baseline.create(identity, store) -> baseline|nil, string|nil`.
- Produces: `baseline.open(identity, store, review_id) -> baseline|nil, string|nil`.
- Produces: `baseline:manifest()`, `baseline:read(path)`, `baseline:bytes(path)`, `baseline:fingerprint(path)`, `baseline:ignored_fingerprint(path)`, and `baseline:remove()`.
- Produces: `tracker.new(options) -> tracker`.
- Produces: `tracker:ensure_batch()`, `tracker:scan(reason)`, `tracker:record_nvim_write(bufnr)`, `tracker:paths()`, `tracker:get(path)`, `tracker:resolve(path, resolution)`, `tracker:abandon()`, `tracker:subscribe(callback)`, and `tracker:shutdown()`.
- Produces path records with exact fields `{ path, baseline, decision_base, current, current_hash, writer, state, action, reason }`.

The three object fields in a path record use this exact shape:

```lua
{
  kind = "absent",             -- `absent`, `regular`, `symlink`, or `unsupported`
  mode = nil,                   -- `100644`, `100755`, or `120000` when present
  size = 0,
  sha256 = nil,                 -- SHA-256 of exact bytes or symlink target bytes
  storage = nil,                -- `tree:<oid>`, `copy:<object-name>`, or nil
  tree_oid = nil,
}
```

The path fields use these exact vocabularies:

- `writer` is `none`, `nvim`, `external`, or `mixed`.
- `state` is `unchanged`, `unresolved`, `accepted`, `rejected`, `ignored`, `conflicted`, or `unsupported`.
- `action` is `hunks`, `whole`, or `none`.

- [ ] **Step 1: Write a failing real-Git baseline fixture**

Create `.config/nvim/tests/ai_review.lua` with one temporary Git worktree created only beneath `vim.fn.tempname()`.
Set fixture-local user identity, make an initial commit, then create clean, dirty, staged, executable, symlink, non-ignored untracked, and ignored paths.
Capture exact status and object counts before baseline creation.
Use these core assertions:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local baseline_module = require("ai.review.baseline")
local tracker_module = require("ai.review.tracker")
local fixture = new_git_fixture()
fixture:write("clean.txt", "clean\n")
fixture:write("dirty.txt", "committed\n")
fixture:write("staged.txt", "committed staged\n")
fixture:write("script.sh", "#!/bin/sh\nexit 0\n", 493)
fixture:write("missing.txt", "present in committed tree\n")
fixture:commit("baseline")
fixture:unlink("missing.txt")
fixture:write("dirty.txt", "pre-request dirty\n")
fixture:write("staged.txt", "staged bytes\n")
fixture:git({ "add", "--", "staged.txt" })
fixture:write("untracked.txt", "pre-request untracked\n")
fixture:write("ignored.log", "ignored before\n")
fixture:write(".gitignore", "*.log\n")

local status_before = fixture:status_bytes()
local objects_before = fixture:object_count()
local baseline = assert(baseline_module.create(fixture:identity(), fixture:store()))
eq(fixture:status_bytes(), status_before, "baseline does not alter Git status")
eq(fixture:object_count(), objects_before, "baseline writes no Git object")
eq(baseline:read("clean.txt").storage:sub(1, 5), "tree:", "clean tracked tree reference")
eq(baseline:read("dirty.txt").storage:sub(1, 5), "copy:", "dirty tracked copy")
eq(baseline:bytes("dirty.txt"), "pre-request dirty\n", "dirty bytes retained exactly")
eq(baseline:read("staged.txt").storage:sub(1, 5), "copy:", "staged path copied")
eq(baseline:bytes("untracked.txt"), "pre-request untracked\n", "untracked bytes retained exactly")
eq(baseline:read("missing.txt").kind, "absent", "absent path")
assert(baseline:ignored_fingerprint("ignored.log").sha256, "ignored path fingerprint missing")
eq(baseline:read("ignored.log"), nil, "ignored bytes are not retained")

local reopened = assert(baseline_module.open(fixture:identity(), fixture:store(), baseline:id()))
eq(reopened:bytes("dirty.txt"), "pre-request dirty\n", "durable baseline reopen")
eq(reopened:manifest().baseline_hash, baseline:manifest().baseline_hash, "manifest hash")
```

Add fixtures for an unborn repository, staged deletion, missing worktree file, executable-bit change, symlink target, filename containing tab and newline, submodule or special-file classification, concurrent file mutation during capture, corrupt manifest, missing copied object, wrong file mode, symlinked storage, and a non-Git root.
For non-Git, assert `conflict_only=true`, no automatic object data, and no Git command.

- [ ] **Step 2: Add failing tracker classification tests**

Continue `.config/nvim/tests/ai_review.lua` with injected scanner, buffer, watcher, timer, and reload dependencies.
Use this exact table as the expected authoritative classification matrix:

```lua
local cases = {
  { name = "unchanged", baseline = "A", current = "A", nvim = nil, external = false, state = "unchanged", writer = "none" },
  { name = "external", baseline = "A", current = "B", nvim = nil, external = true, state = "unresolved", writer = "external" },
  { name = "user only", baseline = "A", current = "B", nvim = "B", external = false, state = "unchanged", writer = "nvim" },
  { name = "external after user", baseline = "A", current = "C", nvim = "B", external = true, state = "conflicted", writer = "mixed" },
  { name = "user after external", baseline = "A", current = "C", nvim = "C", external = true, state = "conflicted", writer = "mixed" },
}
for _, case in ipairs(cases) do
  local result = tracker_module._test.classify_writer({
    baseline_hash = hash(case.baseline),
    current_hash = hash(case.current),
    last_nvim_hash = case.nvim and hash(case.nvim) or nil,
    external_seen = case.external,
    nvim_seen = case.nvim ~= nil,
  })
  eq({ state = result.state, writer = result.writer }, { state = case.state, writer = case.writer }, case.name)
end

local reloads = {}
local tracker = tracker_module._test.new(fake_tracker_dependencies({
  reload = function(bufnr, expected_hash)
    table.insert(reloads, { bufnr = bufnr, expected_hash = expected_hash })
    return true
  end,
}))
assert(tracker:ensure_batch())
tracker:signal("src/agent.lua")
assert(tracker:scan("filesystem"))
eq(tracker:get("src/agent.lua").state, "unresolved", "external delta")
eq(#reloads, 1, "unmodified buffer reload")

tracker:set_buffer_state("src/modified.lua", { loaded = true, modified = true })
tracker:signal("src/modified.lua")
assert(tracker:scan("filesystem"))
eq(tracker:get("src/modified.lua").state, "conflicted", "modified buffer conflict")
eq(#reloads, 1, "modified buffer never reloaded")
```

Add cases for missed watcher events found by the full scan, new directories, user-only `BufWritePost`, external then user, user then external, external change equal to baseline, ignored change, `.gitignore` exposing a pre-existing ignored path, deleted file, new file, mode-only change, symlink change, binary whole-file classification, non-Git conflict-only paths, and scan failure latching the batch conflicted.
Represent a rename as one deletion and one addition unless an exact baseline/current object identity and single unambiguous pairing proves the rename; neither representation changes the reject safety rules.

- [ ] **Step 3: Run the review test and verify both review modules are missing**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_review.lua
```

Expected: exit nonzero with `module 'ai.review.baseline' not found`.

- [ ] **Step 4: Implement exact baseline capture without Git writes**

Create `.config/nvim/lua/ai/review/baseline.lua`.
Receive and revalidate the cached canonical Git executable from `AiHostTools`, and never resolve or invoke Git through `PATH`.
Run every Git command with `GIT_OPTIONAL_LOCKS=0`, `LC_ALL=C`, a literal argv array, a 30-second timeout, and `--literal-pathspecs` where a pathspec is present.
Insert `-c core.fsmonitor=false` before every Git subcommand so baseline capture cannot invoke a configured filesystem-monitor hook.
The allowed Git command families are exactly:

```lua
local commands = {
  head_tree = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "rev-parse", "--verify", "HEAD^{tree}" },
  tree = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "ls-tree", "-rz", "--full-tree", "HEAD" },
  index = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "ls-files", "-z", "--stage" },
  staged = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "diff", "--cached", "--name-only", "-z", "--diff-filter=ACDMRTUXB" },
  untracked = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "ls-files", "-z", "--others", "--exclude-standard" },
  ignored = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "ls-files", "-z", "--others", "--ignored", "--exclude-standard" },
  hash = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "hash-object", "--no-filters", "--stdin" },
  read = { git_executable, "-C", root, "-c", "core.fsmonitor=false", "cat-file", "blob", object_id },
}
```

Reject and mark conflicted any index entry with a stage other than zero, any tree type other than `blob`, mode other than `100644`, `100755`, or `120000`, any special filesystem object, or any path escaping the physical root after parent canonicalization.

For each tracked path, read exact disk bytes or symlink-target bytes with lstat before and after.
Compute SHA-256 locally and compute the Git object ID by sending the captured bytes to `git hash-object --no-filters --stdin`.
Use `tree:<oid>` only when the path is not staged, the tree mode matches, the raw object ID matches, and both lstat samples match.
Use `copy:<sha256>` for every other present tracked or non-ignored untracked path.
Record `absent` when a tracked path is absent at batch creation.
Store ignored path fingerprints without storing ignored bytes.

Publish copied objects first and the manifest last.
Serialize Git paths as lowercase byte-hex `path_hex` fields in sorted arrays rather than JSON object keys, then decode them back to exact path bytes on open.
This keeps newline, control, and non-UTF-8 filenames round-trippable without using them in a storage filename.
Use mode 0600, reject symlinks, fsync every file, fsync the directory, and hash canonical JSON with path arrays sorted by decoded bytes into `baseline_hash`.
If any capture or publication step races or fails, remove only newly published objects for that new batch and return an error without a usable review ID.
`open()` verifies directory ownership and mode, manifest schema and identity, every copied-object size and SHA-256, every tree reference through `cat-file`, and the manifest hash before enabling rejection.

- [ ] **Step 5: Implement authoritative scans and writer classification**

Create `.config/nvim/lua/ai/review/tracker.lua`.
Use one root filesystem watcher only as a wake-up signal, a 120-millisecond debounce timer, and a two-second periodic scan timer while a batch is open.
Also scan immediately on `FocusGained`, `BufEnter`, explicit review, and structured backend completion.
Every `scan()` must enumerate the full current tracked plus non-ignored untracked set again and compare exact fingerprints to the immutable baseline and last observation.
The full scan, not watcher coverage, is authoritative.

Implement the writer classifier exactly as follows:

```lua
local function classify_writer(input)
  if input.current_hash == input.baseline_hash then
    return { writer = input.nvim_seen and "nvim" or "none", state = "unchanged" }
  end
  if input.external_seen and input.nvim_seen then
    return { writer = "mixed", state = "conflicted" }
  end
  if input.last_nvim_hash and input.current_hash == input.last_nvim_hash and not input.external_seen then
    return { writer = "nvim", state = "unchanged" }
  end
  if input.nvim_seen then
    return { writer = "mixed", state = "conflicted" }
  end
  return { writer = "external", state = "unresolved" }
end
```

`record_nvim_write()` records the exact post-write fingerprint synchronously on `BufWritePost`.
If an external delta was already observed, that path becomes `mixed` even when the final bytes equal the user's write.
If a later scan differs from the last Neovim write, mark external involvement and apply the same mixed-writer rule.

For an unmodified loaded buffer, record the expected disk hash, invoke `checktime` inside that buffer, and recheck the disk hash after Neovim's normal file-change handling.
If either hash differs, mark the path conflicted.
For a modified loaded buffer, never call `checktime`, `:edit`, or `:edit!`; mark the path conflicted and notify through the tracker subscription.

Ignored paths use fingerprints only and always receive `state="ignored"` and `action="none"`.
A path that was ignored at baseline but becomes Git-visible receives `state="conflicted"` because no recovery bytes exist.
Non-Git batches enumerate signaled and loaded paths but set `action="none"` for every external delta.
Any scan failure, baseline loss, hash race, unsupported type, or mixed writer latches the path and batch conflicted.

- [ ] **Step 6: Format and run baseline and tracker tests**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/review/baseline.lua \
  /home/ruohao/.config/nvim/lua/ai/review/tracker.lua \
  /home/ruohao/.config/nvim/tests/ai_review.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_review.lua
```

Expected: the test prints `AI review assertions: ok` with exit `0`, fixture cleanup restores no user files, and fixture Git status matches its asserted post-test state.

- [ ] **Step 7: Commit exact baseline tracking**

```sh
git add .config/nvim/lua/ai/review/baseline.lua \
  .config/nvim/lua/ai/review/tracker.lua \
  .config/nvim/tests/ai_review.lua
git commit -m "feat(nvim): track exact AI edit baselines"
```

### Task 8: Apply hash-checked hunk and whole-file review decisions

**Files:**

- Create: `.config/nvim/lua/ai/review/reducer.lua`
- Create: `.config/nvim/scripts/nvim-ai-review.py`
- Create: `.config/nvim/tests/nvim_ai_review.py`
- Modify: `.config/nvim/lua/ai/review/tracker.lua`
- Modify: `.config/nvim/tests/ai_review.lua`

**Interfaces:**

- Consumes: Task 7 baseline objects, current objects, decision-base objects, exact reviewed hashes, and `vim.diff` index hunks.
- Produces: `reducer.hunks(base_bytes, current_bytes) -> hunk[]`.
- Produces: `reducer.accept_hunk(base_bytes, current_bytes, index) -> string|nil, string|nil`.
- Produces: `reducer.reject_hunk(base_bytes, current_bytes, index) -> string|nil, string|nil`.
- Adds `tracker:accept_hunk(path, index, expected_hash)`, `tracker:reject_hunk(path, index, expected_hash)`, `tracker:accept_file(path, expected_hash)`, and `tracker:reject_file(path, expected_hash)`.
- Returns decision results as `{ path, state, current_hash, unresolved_hunks }`.
- Produces `nvim-ai-review.py --manifest ABSOLUTE_MODE_0600_JSON` and pure Python `validate_action`, `open_parent`, `fingerprint_at`, and `apply_action` functions.

- [ ] **Step 1: Add failing pure reducer tests**

Append these exact cases to `.config/nvim/tests/ai_review.lua`:

```lua
local reducer = require("ai.review.reducer")

local base = "one\ntwo\nthree\nfour\n"
local current = "one\nTWO\nthree\nFOUR\n"
local hunks = reducer.hunks(base, current)
eq(#hunks, 2, "two independent hunks")

local accepted_base = assert(reducer.accept_hunk(base, current, 1))
eq(accepted_base, "one\nTWO\nthree\nfour\n", "accept records bytes without changing current")
eq(#reducer.hunks(accepted_base, current), 1, "accepted hunk leaves one unresolved")

local rejected_current = assert(reducer.reject_hunk(accepted_base, current, 1))
eq(rejected_current, accepted_base, "reject remaining hunk restores decision base")
eq(#reducer.hunks(accepted_base, rejected_current), 0, "all hunks resolved")

for _, pair in ipairs({
  { "", "created without newline" },
  { "deleted without newline", "" },
  { "a\nb\n", "a\ninserted\nb\n" },
  { "a\ndeleted\nb\n", "a\nb\n" },
  { "café\n", "CAFE\n" },
}) do
  local one = reducer.hunks(pair[1], pair[2])
  assert(#one > 0, "fixture needs a hunk")
  eq(assert(reducer.reject_hunk(pair[1], pair[2], 1)), pair[1], "byte-exact inverse")
end
eq(reducer.reject_hunk(base, current, 99), nil, "invalid hunk refused")
```

Add cases for adjacent hunks, insertion at byte zero, deletion at EOF, CRLF bytes, NUL bytes classified as binary before reducer use, and final-newline-only changes.

- [ ] **Step 2: Add failing hash and filesystem action tests**

Continue the same test with a real private fixture and the tracker action API.
Cover all of these exact outcomes:

```lua
local item = assert(tracker:get("src/two-hunks.txt"))
local reviewed_hash = item.current_hash
assert(tracker:accept_hunk(item.path, 1, reviewed_hash))
eq(tracker:get(item.path).state, "unresolved", "one accepted hunk remains in batch")
assert(tracker:reject_hunk(item.path, 1, tracker:get(item.path).current_hash))
eq(tracker:get(item.path).state, "accepted", "accepted bytes remain after other rejection")

local stale = assert(tracker:get("src/race.txt"))
fixture:write(stale.path, "changed after render\n")
local result, error_message = tracker:reject_file(stale.path, stale.current_hash)
eq(result, nil, "stale whole-file reject refused")
assert(error_message:find("hash", 1, true), "hash-race detail")
eq(tracker:get(stale.path).state, "conflicted", "hash race latches conflict")

local created = assert(tracker:get("src/created.txt"))
assert(tracker:reject_file(created.path, created.current_hash))
eq(vim.uv.fs_lstat(fixture:path(created.path)), nil, "matching created file removed")

local deleted = assert(tracker:get("src/deleted.txt"))
assert(tracker:reject_file(deleted.path, deleted.current_hash))
eq(fixture:read(deleted.path), "pre-request dirty deletion baseline\n", "deleted path restored exactly")
```

Add executable-mode, symlink-target, binary whole-file, modified-buffer, external writer, accepted-file, rejected-file, path replacement with symlink, directory replacement, write failure, rename failure, and post-write hash mismatch cases.
Inject the mutation runner in Lua tests, assert its manifest contains path hex plus exact expected and desired objects, and let the Python suite own real filesystem mutation.
Assert conflicted and ignored paths expose no accept or reject action.
Assert no test or production command invokes `git checkout`, `git restore`, `git reset`, `git apply`, or any command that writes the real index or object database.

- [ ] **Step 3: Write failing descriptor-relative mutation tests**

Create `.config/nvim/tests/nvim_ai_review.py` with `unittest` and import `.config/nvim/scripts/nvim-ai-review.py` through `importlib.util.spec_from_file_location`.
Use one temporary mode-0700 root and these core assertions:

```python
class ReviewMutationTests(unittest.TestCase):
    def test_regular_replacement_is_exact_and_descriptor_relative(self):
        fixture = ReviewFixture()
        fixture.write("src/item.txt", b"agent\n", 0o644)
        desired = fixture.private_object(b"baseline dirty\n")
        action = fixture.action(
            path=b"src/item.txt",
            expected={"kind": "regular", "mode": "100644", "size": 6, "sha256": sha256(b"agent\n")},
            desired={"kind": "regular", "mode": "100644", "size": 15, "sha256": sha256(b"baseline dirty\n"), "source": desired},
        )
        result = review_helper.apply_action(action)
        self.assertEqual(result["sha256"], sha256(b"baseline dirty\n"))
        self.assertEqual(fixture.read("src/item.txt"), b"baseline dirty\n")

    def test_expected_hash_mismatch_writes_nothing(self):
        fixture = ReviewFixture()
        fixture.write("race.txt", b"newer\n", 0o644)
        action = fixture.action(
            path=b"race.txt",
            expected={"kind": "regular", "mode": "100644", "size": 6, "sha256": sha256(b"older\n")},
            desired={"kind": "absent", "mode": None, "size": 0, "sha256": None, "source": None},
        )
        with self.assertRaisesRegex(ValueError, "expected fingerprint"):
            review_helper.apply_action(action)
        self.assertEqual(fixture.read("race.txt"), b"newer\n")

    def test_symlink_parent_is_refused(self):
        fixture = ReviewFixture()
        outside = fixture.outside_directory()
        fixture.symlink("linked", outside)
        action = fixture.absent_to_regular(path=b"linked/escape.txt", content=b"no\n")
        with self.assertRaisesRegex(ValueError, "parent.*symlink"):
            review_helper.apply_action(action)
        self.assertFalse(os.path.exists(os.path.join(outside, "escape.txt")))
```

Define `sha256`, `ReviewFixture.write`, `read`, `symlink`, `private_object`, `action`, `absent_to_regular`, `outside_directory`, and cleanup in the same file.
Add created-file unlink, deleted-file restoration, executable mode, symlink target, wrong-kind destination, destination swap, source-object hash mismatch, partial write, fsync failure, parent rename during action, control-containing path bytes, `..`, absolute path, empty component, manifest symlink, wrong manifest ownership or mode, and unknown-key cases.

- [ ] **Step 4: Run focused review tests and verify both implementations are missing**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_review.lua
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_review.py
```

Expected: Lua exits nonzero with `module 'ai.review.reducer' not found`, and Python exits nonzero because `nvim-ai-review.py` is absent.

- [ ] **Step 5: Implement byte-preserving hunk reduction**

Create `.config/nvim/lua/ai/review/reducer.lua`.
Obtain zero-context line-index hunks from:

```lua
local raw = vim.diff(base_bytes, current_bytes, {
  result_type = "indices",
  algorithm = "histogram",
  ctxlen = 0,
  interhunkctxlen = 0,
})
```

Represent each hunk as `{ base_start, base_count, current_start, current_count }` without changing Neovim's one-based line indices or zero-count insertion positions.
Build a line-span table that retains each line's terminating `\n` and separately retains a final unterminated line.
Use the line-span table to convert each hunk to exact byte offsets.

`accept_hunk(base, current, index)` replaces the selected base span with the exact current span and returns the new decision base.
`reject_hunk(base, current, index)` replaces the selected current span with the exact base span and returns the new current bytes.
Neither function reads a path, writes a path, normalizes line endings, adds a final newline, or accepts an out-of-range hunk.
Reject strings containing NUL because the tracker routes them to whole-file binary actions.
Also route bytes that fail `vim.str_utfindex` UTF-8 validation to whole-file binary actions.

- [ ] **Step 6: Implement the confined descriptor-relative mutation helper**

Create executable `.config/nvim/scripts/nvim-ai-review.py` with `argparse`, `hashlib`, `json`, `os`, `stat`, and `sys` only.
Read a nonsymlink current-user-owned mode-0600 manifest of at most 1 MiB, reject unknown keys, and decode the relative path only from lowercase even-length `path_hex`.
Reject an empty or absolute path, NUL, `.` or `..` component, empty component, and more than 4096 decoded path bytes.

Open the canonical root once with `O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC`.
Traverse every parent component with `os.open(component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, dir_fd=current_fd)` and retain the final parent directory descriptor.
Never reconstruct an absolute destination path after opening the root.
Read, lstat, unlink, create, chmod, rename, and fsync the destination only through `dir_fd` arguments.

Validate the current kind, regular bytes or symlink-target bytes, mode, size, and SHA-256 against the exact expected object.
Validate a desired private source as a nonsymlink current-user-owned mode-0600 regular file and verify its size and SHA-256 before use.
For a desired regular file, create a random 32-hex temporary sibling with `O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW`, write all bytes, set mode 0644 or 0755, fsync, fingerprint the destination again, and use `os.rename` with both directory descriptors.
For a desired symlink, read the exact target bytes from the private source, reject NUL, create a temporary symlink through `dir_fd`, fingerprint the destination again, and rename through the same descriptor.
For desired absence, fingerprint again immediately before `os.unlink(name, dir_fd=parent_fd)`.
Fsync the retained parent descriptor and return only the final `{ kind, mode, size, sha256 }` JSON object.
On any mismatch, remove only the helper's still-private temporary sibling and leave the destination unchanged.

Invoke this helper through a fixed Bubblewrap argv built by the tracker.
Resolve Bubblewrap to the same canonical absolute executable policy as the launch manifest and use only that path as argv element zero.
Invoke the Python interpreter with `-I -B` before the fixed helper path.
Receive the canonical Python, Bubblewrap, and review-helper paths from the already initialized runtime, reject any metadata drift before every action, and never rediscover them through a project-controlled `PATH`.
The helper sandbox uses a read-only `/`, writable bind of only the physical root, read-only Git entry and administration masks, read-only bind of the action manifest and desired object, private `/tmp`, `--unshare-net`, no grants, no tmux environment, and `close_fds=True`.
If Bubblewrap or the helper fails, never retry the mutation unconfined.
After the helper exits, the tracker removes only its exact one-time action manifest and private desired object regardless of success.

- [ ] **Step 7: Implement atomic hash-checked tracker actions**

Extend `.config/nvim/lua/ai/review/tracker.lua`.
Every action must acquire the current path record, require `state="unresolved"`, require the advertised action, lstat and read the disk object, and compare type, mode, size, and SHA-256 with `expected_hash` before changing either disk or review state.
Immediately recheck all loaded buffers for that path and refuse the action if any became modified after the review view was rendered.

For hunk accept, update only the private `decision_base` copy and state manifest.
For hunk reject, publish the reducer result as a mode-0600 private action object and ask `nvim-ai-review.py` to preserve the current executable bit and replace it.
For whole-file accept, record the exact current object as the decision base without changing disk.
For whole-file reject, send this type matrix to the confined helper:

| Baseline | Current | Exact action |
| --- | --- | --- |
| absent | regular or symlink | Unlink only after the current fingerprint matches. |
| regular | absent, regular, or symlink | Publish a private temporary regular file, set baseline mode, fsync, recheck destination fingerprint, and rename. |
| symlink | absent, regular, or symlink | Create a temporary symlink with the exact baseline target, recheck destination fingerprint, and rename. |
| unsupported | any | Refuse and mark conflicted. |

After a successful helper action, compare its returned fingerprint with a fresh tracker fingerprint, recompute hunks against the decision base, and persist the new record atomically.
If no unresolved hunks remain, mark the path `accepted` when any accepted bytes remain relative to the immutable baseline and `rejected` when the current object equals the immutable baseline.
If any precondition or postcondition differs, write no further bytes, mark the path conflicted, invalidate the review view, and notify subscribers.
If a path changes after one or more hunk decisions, discard its mutable decision base, restore comparison against the immutable baseline, and classify the new writer state before permitting another action.

After a successful reject, call normal `checktime` only for an unmodified loaded buffer and verify its disk hash around reload.
Never touch a modified loaded buffer.
When every changed path is accepted, rejected, or exact-hash manually resolved and no conflict remains, mark the batch resolved, ask the session coordinator to relaunch read-only, and remove baseline storage only after that relaunch succeeds.
Do not auto-resolve a batch that has never observed an external delta; an empty batch stays open until the user explicitly abandons it.

- [ ] **Step 8: Format and run reducer and action tests**

Run:

```sh
chmod 700 /home/ruohao/.config/nvim/scripts/nvim-ai-review.py
stylua /home/ruohao/.config/nvim/lua/ai/review/reducer.lua \
  /home/ruohao/.config/nvim/lua/ai/review/tracker.lua \
  /home/ruohao/.config/nvim/tests/ai_review.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_review.lua
python3 -I -B -c 'import ast,pathlib,sys; [ast.parse(pathlib.Path(item).read_text(encoding="utf-8"), filename=item) for item in sys.argv[1:]]' \
  /home/ruohao/.config/nvim/scripts/nvim-ai-review.py \
  /home/ruohao/.config/nvim/tests/nvim_ai_review.py
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_review.py
```

Expected: Lua prints exactly `AI review assertions: ok`; Python ends in `OK`; every command exits `0`.

- [ ] **Step 9: Commit reviewed change reduction**

```sh
git add .config/nvim/lua/ai/review/reducer.lua \
  .config/nvim/lua/ai/review/tracker.lua \
  .config/nvim/scripts/nvim-ai-review.py \
  .config/nvim/tests/ai_review.lua \
  .config/nvim/tests/nvim_ai_review.py
git commit -m "feat(nvim): review AI edits by exact hash"
```

### Task 9: Present native file and hunk review controls

**Files:**

- Create: `.config/nvim/lua/ai/review/ui.lua`
- Modify: `.config/nvim/tests/ai_review.lua`

**Interfaces:**

- Consumes: the Task 7 tracker list and Task 8 action methods.
- Produces: `review_ui.new(options) -> review_ui`.
- Produces: `review_ui:open()`, `review_ui:open_path(path)`, `review_ui:next(direction)`, `review_ui:refresh()`, and `review_ui:close()`.
- Uses buffer-local mappings `a`, `r`, `A`, `R`, `m`, `]r`, `[r`, `o`, and `q` only inside owned review buffers.

- [ ] **Step 1: Add failing picker and review-buffer tests**

Append dependency-injected UI cases to `.config/nvim/tests/ai_review.lua`:

```lua
local ui_module = require("ai.review.ui")
local selected_items = {}
local mapped = {}
local opened = {}
local ui = ui_module._test.new({
  tracker = fake_review_tracker(),
  select = function(items, options, callback)
    selected_items = items
    eq(options.prompt, "AI review batch review_0123456789abcdef", "picker prompt")
    callback(items[1])
  end,
  open_diff = function(view) table.insert(opened, view) return { baseline = 21, current = 22 } end,
  map = function(bufnr, mode, lhs, callback, description)
    mapped[lhs] = { bufnr = bufnr, mode = mode, callback = callback, description = description }
  end,
  notify = function() end,
})
assert(ui:open())
eq(selected_items[1].label, "[unresolved] src/agent.lua", "picker label")
eq(opened[1].path, "src/agent.lua", "selected path opens")
for _, lhs in ipairs({ "a", "r", "A", "R", "m", "]r", "[r", "o", "q" }) do
  assert(mapped[lhs], "missing review mapping " .. lhs)
end
mapped.r.callback()
eq(ui._debug().last_action, "reject_hunk", "lowercase reject action")
mapped.R.callback()
eq(ui._debug().last_action, "reject_file", "uppercase reject action")
```

Add cancellation, empty batch, conflict-only opening, ignored item, binary whole-file view, stale-hash invalidation, accept and reject refresh, next and previous unresolved wrap, closed buffer, and batch-resolution cleanup cases.
Assert `a`, `r`, `A`, and `R` are absent from conflict-only buffers, `m` records an exact-hash manual resolution, and `o` opens the real path for editing.

- [ ] **Step 2: Run the review test and verify the UI module is missing**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_review.lua
```

Expected: exit nonzero with `module 'ai.review.ui' not found`.

- [ ] **Step 3: Implement the native review picker and diff view**

Create `.config/nvim/lua/ai/review/ui.lua`.
Build picker items from a sorted tracker snapshot and use this exact label function:

```lua
local function display_path(path)
  return (path:gsub("([^A-Za-z0-9._/-])", function(byte)
    return string.format("%%%02X", string.byte(byte))
  end))
end

local function label(item)
  local state = item.state
  local suffix = item.reason and item.reason ~= "" and (" - " .. item.reason) or ""
  return string.format("[%s] %s%s", state, display_path(item.path), suffix)
end
```

Call `vim.ui.select(items, { prompt = "AI review batch " .. review_id, format_item = function(item) return item.label end }, callback)`.
Append one final picker item labeled `[batch] Abandon review batch`; selecting it invokes the same confirmed abandonment transaction as `:NvimAIReview!`.
Cancellation must have no side effect.

For a reviewable text path, create two `nofile` scratch buffers named `nvim-ai-baseline://<review-id>/<percent-encoded-path>` and `nvim-ai-current://<review-id>/<percent-encoded-path>`.
Set `bufhidden=wipe`, `buftype=nofile`, `swapfile=false`, `modifiable=false`, and matching filetypes inferred from the real path.
Open them in a dedicated tab with baseline on the left and current on the right, then enable `diffthis` in both windows.
Store exact `path`, `current_hash`, and current hunk index in buffer-local variables.

Install these exact buffer-local normal mappings:

| Mapping | Action |
| --- | --- |
| `a` | Accept the current unresolved hunk. |
| `r` | Reject the current unresolved hunk. |
| `A` | Accept the entire file. |
| `R` | Reject the entire file. |
| `m` | Mark the exact current conflicted, ignored, unsupported, or non-Git object manually resolved after confirmation. |
| `]r` | Move to the next unresolved path. |
| `[r` | Move to the previous unresolved path. |
| `o` | Open the real current file for manual resolution. |
| `q` | Close only the owned review tab. |

Before each action, map the current-side cursor line to the latest reducer hunk, pass the stored exact hash to the tracker, and refuse when the view is stale.
After a successful action, recreate both scratch contents and hunk positions from the latest tracker state.
Never make a scratch buffer writable.
For conflicted, ignored, unsupported, and non-Git paths, show metadata and the real current file but install only `m`, `o`, `]r`, `[r`, and `q`.
`m` must pass the displayed exact hash to `tracker:resolve(path, "manual", expected_hash)` and must refuse when the path has changed since display.
On confirmation and an exact fingerprint match, manual resolution records `state="accepted"`, retains the original writer classification, and sets the bounded reason to `manually resolved`; it never creates recovery bytes or claims automatic rejection is available.
For binary, symlink, mode-only, created, and deleted paths, install whole-file actions only.

- [ ] **Step 4: Format and run the complete review suite**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/review/ui.lua \
  /home/ruohao/.config/nvim/tests/ai_review.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_review.lua
```

Expected: the test prints exactly `AI review assertions: ok` with exit `0`.

- [ ] **Step 5: Commit the native review UI**

```sh
git add .config/nvim/lua/ai/review/ui.lua \
  .config/nvim/tests/ai_review.lua
git commit -m "feat(nvim): add native AI edit review"
```

### Task 10: Broker temporary scope and normalize structured backend events

**Files:**

- Create: `.config/nvim/lua/ai/scope.lua`
- Create: `.config/nvim/lua/ai/events.lua`
- Create: `.config/nvim/scripts/nvim-ai-control.py`
- Create: `.config/nvim/scripts/nvim-ai-event.py`
- Create: `.config/nvim/tests/ai_scope.lua`
- Create: `.config/nvim/tests/nvim_ai_control.py`
- Modify: `.config/nvim/lua/ai/backends/claude.lua`
- Modify: `.config/nvim/lua/ai/backends/opencode.lua`
- Modify: `.config/nvim/lua/ai/session.lua`
- Modify: `.config/nvim/scripts/nvim-ai-launch.py`
- Modify: `.config/nvim/tests/ai_backends.lua`
- Modify: `.config/nvim/tests/nvim_ai_launch.py`

**Interfaces:**

- Consumes: `AiIdentity`, active session snapshot, review ID, current grants, Task 5 relaunch, a mode-0700 runtime directory, and structured backend event feeds.
- Produces: `scope.new(options) -> broker`.
- Produces: `broker:start()`, `broker:list()`, `broker:request(payload, callback)`, `broker:revoke(path, callback)`, `broker:clear_for_close(callback)`, and `broker:stop()`.
- Produces Unix request lines `{"schema":1,"operation":"request_scope","token":"<32 hex>","path":"<path>","reason":"<reason>"}\n`.
- Produces Unix response lines `{"schema":1,"ok":true|false,"code":"<code>","message":"<bounded text>"}\n`.
- Produces client CLI `nvim-ai-control.py request-scope --path PATH --reason REASON`.
- Produces `events.new(options) -> reader` with `reader:start()`, `reader:poll()`, `reader:subscribe(callback)`, and `reader:stop()`.
- Produces normalized event records `{ schema=1, backend, session, state, time }` where state is common `open` or `failed`, or rich `idle`, `busy`, `approval`, `completed`.

- [ ] **Step 1: Write failing Lua scope protocol tests**

Create `.config/nvim/tests/ai_scope.lua` with injected socket, canonicalization, confirmation, session, and state dependencies.
Use this exact request and approval sequence:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local scope_module = require("ai.scope")
local events_module = require("ai.events")
local relaunches = {}
local prompts = {}
local broker = scope_module._test.new({
  identity = {
    key = string.rep("a", 32), root = "/work/repo", git_dir = "/git/worktrees/repo",
    git_common_dir = "/git", git_entry = "/work/repo/.git", owner_pane = "%12", tmux_socket = "/tmp/tmux/default",
  },
  backend = function() return "claude" end,
  review_id = function() return "review_0123456789abcdef" end,
  token = string.rep("b", 32),
  realpath = function(path)
    local values = { ["/outside/link"] = "/outside/physical", ["/outside/physical"] = "/outside/physical" }
    return values[path]
  end,
  lstat = function(path) return path == "/outside/physical" and { type = "directory" } or nil end,
  confirm = function(message, callback) table.insert(prompts, message) callback(true) end,
  relaunch = function(grants) table.insert(relaunches, vim.deepcopy(grants)) return true end,
  write_grants = function() return true end,
  notify = function() end,
})

local response
broker:request({
  schema = 1, operation = "request_scope", token = string.rep("b", 32),
  path = "/outside/link", reason = "generate a fixture",
}, function(value) response = value end)
eq(response.code, "granted", "approved response")
eq(broker:list(), { "/outside/physical" }, "canonical grant")
eq(relaunches[1], { "/outside/physical" }, "sandbox rebuilt with exact grant")
assert(prompts[1]:find("Claude", 1, true), "approval omitted backend")
assert(prompts[1]:find("%12", 1, true), "approval omitted owner pane")
assert(prompts[1]:find("/work/repo", 1, true), "approval omitted pinned root")
assert(prompts[1]:find("/outside/physical", 1, true), "approval omitted requested path")

local revoked
broker:revoke("/outside/physical", function(value) revoked = value end)
eq(revoked.code, "revoked", "revocation response")
eq(relaunches[2], {}, "revocation rebuilds sandbox")
eq(broker:list(), {}, "grant removed")
```

Add exact refusal cases for missing review batch, bad schema, unknown operation, wrong token, missing or relative path, nonexistent path, filesystem root, path already inside the pinned root, Git administration paths, tmux socket, control characters, duplicate grant, empty reason, reason longer than 512 bytes, request longer than 8192 bytes, confirmation refusal, relaunch failure rollback, durable-state failure rollback, timeout, pane close, and broker not running.

- [ ] **Step 2: Write failing Python client and event-normalizer tests**

Create `.config/nvim/tests/nvim_ai_control.py` with `unittest`, a temporary mode-0700 Unix-socket directory, and a one-request fake server thread.
Import both scripts by absolute file path.
The core cases must be these:

```python
class ControlClientTests(unittest.TestCase):
    def test_exact_request_and_response(self):
        with FakeUnixServer({"schema": 1, "ok": True, "code": "granted", "message": "approved"}) as server:
            result = control.request_scope(
                socket_path=server.path,
                token="b" * 32,
                path="/outside/physical",
                reason="generate a fixture",
                timeout=1.0,
            )
        self.assertEqual(result["code"], "granted")
        self.assertEqual(server.request, {
            "schema": 1,
            "operation": "request_scope",
            "token": "b" * 32,
            "path": "/outside/physical",
            "reason": "generate a fixture",
        })

    def test_missing_neovim_socket_is_actionable(self):
        with self.assertRaisesRegex(RuntimeError, "reopen the owning Neovim"):
            control.request_scope("/missing/control.sock", "b" * 32, "/outside", "reason", 0.1)

    def test_response_and_timeout_are_bounded(self):
        with FakeUnixServer(raw_response=b"x" * 4097) as server:
            with self.assertRaisesRegex(RuntimeError, "response limit"):
                control.request_scope(server.path, "b" * 32, "/outside", "reason", 1.0)

class EventTests(unittest.TestCase):
    def test_claude_hook_discards_prompt_content(self):
        payload = {"hook_event_name": "PreToolUse", "session_id": "11111111-1111-4111-8111-111111111111", "prompt": "must not persist"}
        event = event_helper.normalize_claude(payload, now=123)
        self.assertEqual(event, {
            "schema": 1, "backend": "claude", "session": payload["session_id"], "state": "busy", "time": 123,
        })
        self.assertNotIn("prompt", json.dumps(event))

    def test_opencode_event_maps_only_supported_state(self):
        payload = {"type": "permission.asked", "properties": {"sessionID": "ses_123", "content": "discard"}}
        event = event_helper.normalize_opencode(payload, now=124)
        self.assertEqual(event["state"], "approval")
        self.assertNotIn("content", json.dumps(event))
```

Add invalid environment, invalid token, newline and control handling, connect timeout, partial response, malformed JSON, unknown keys, false response exit status, event input larger than 65536 bytes, unknown event type, invalid session, symlink event file, wrong ownership or mode, concurrent append, and OpenCode stream reconnect cases.

- [ ] **Step 3: Add failing event reader and adapter tests**

Append to `.config/nvim/tests/ai_scope.lua`:

```lua
local emitted = {}
local reader = events_module._test.new({
  backend = "claude",
  session = "11111111-1111-4111-8111-111111111111",
  path = "/state/backend/events.ndjson",
  read = fake_incremental_reader({
    '{"schema":1,"backend":"claude","session":"11111111-1111-4111-8111-111111111111","state":"busy","time":123}\n',
    '{"schema":1,"backend":"claude","session":"wrong","state":"completed","time":124}\n',
    '{"schema":1,"backend":"claude","session":"11111111-1111-4111-8111-111111111111","state":"completed","time":125}\n',
  }),
  watch = fake_watch(),
})
reader:subscribe(function(event) table.insert(emitted, event.state) end)
assert(reader:start())
assert(reader:poll())
eq(emitted, { "busy", "completed" }, "foreign session event ignored")
```

Append to `.config/nvim/tests/ai_backends.lua` assertions that Claude's ephemeral settings install only fixed lifecycle and permission hooks through `nvim-ai-event.py`, and that OpenCode returns a loopback event URL plus password through launcher-private fields.
Append to `.config/nvim/tests/nvim_ai_launch.py` assertions that the event helper is started only for OpenCode, receives the password through environment rather than argv, and is terminated and waited for with the server.

- [ ] **Step 4: Run all new focused tests and verify missing modules and scripts fail**

Run:

```sh
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_scope.lua
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_control.py
```

Expected: the Lua test fails on missing `ai.scope`, and Python fails because both helper scripts are absent.

- [ ] **Step 5: Implement the single-operation scope client**

Create executable `.config/nvim/scripts/nvim-ai-control.py` with only Python standard-library imports.
Use `argparse`, `json`, `os`, `socket`, and `sys`.
Read `NVIM_AI_CONTROL_SOCKET` and `NVIM_AI_CONTROL_TOKEN` from the launcher-owned environment, require an absolute socket path and a 32-character lowercase hexadecimal token, bound UTF-8 path to 4096 bytes and reason to 512 bytes, and reject control characters.
Connect with a 30-second default timeout, send one compact sorted JSON line, call `shutdown(socket.SHUT_WR)`, read at most 4097 response bytes, and require one exact response object with keys `schema`, `ok`, `code`, and `message`.
Print only the bounded response message.
Exit `0` for `ok=true`, `2` for a broker refusal, and `1` for protocol or connection failure.
The missing-socket diagnostic must say `reopen the owning Neovim instance and retry the scope request`.
Expose no other subcommand or operation.

- [ ] **Step 6: Implement the private Neovim scope broker**

Create `.config/nvim/lua/ai/scope.lua` with a `vim.uv.new_pipe(false)` server inside the identity's mode-0700 runtime directory.
Unlink only a stale nonsymlink socket owned by the current UID.
Load the pane-stable token through `store:ensure_control_token()` so a surviving TUI can reconnect to the same broker after Neovim reopens.
Accept one newline-terminated request per connection, stop reading after 8192 bytes, and close idle clients after five seconds.
Parse strict JSON and reject unknown keys.
Allow at most one pending confirmation or relaunch transaction per companion and answer additional requests with code `busy` without opening another prompt.
Once a valid request opens confirmation, start a 30-second transaction timer and watch client disconnect.
Expiry or disconnect invalidates the confirmation callback and guarantees that a late UI answer grants nothing.

Canonicalize the requested path with `vim.uv.fs_realpath`, require an existing regular file or directory, and reject `/`, the pinned root or any descendant already writable, either Git administration path, the tmux socket, the control directory, and backend state directories.
Also reject either Task 1 application-owned state root and every adapter-protected global provider path, including a request for one of their ancestors that would make the protected path writable except for the launcher's later read-only re-mask.
When checking containment, compare path components rather than string prefixes.

Confirmation text must contain the backend display name, owner pane, physical root, canonical requested path, reason, and this exact sentence: `Approval restarts the TUI with this path writable and does not continue the pending turn.`
On approval, call `session:set_grants(new_sorted_grants)`.
Within `session:set_grants`, persist the approved new list before relaunch, then tag the successful pane with its grant hash.
If relaunch fails, restore the old durable list and keep or restore the old sandbox before returning failure.
This ordering lets reconnect detect a crash between record publication, process replacement, and pane tagging without losing an approved grant or silently inventing one.
On denial or any error, grant nothing.
Revocation uses the same relaunch and rollback transaction.
`stop()` closes clients and unlinks the socket but retains the token and grants while a tmux pane survives ordinary Neovim exit.
`clear_for_close()` revokes grants, removes the token file, and unlinks the socket only after the session coordinator has closed or proven absent the managed pane.

Add `NVIM_AI_CONTROL_SOCKET`, `NVIM_AI_CONTROL_TOKEN`, and `NVIM_AI_CONTROL_HELPER` in the launcher-owned environment after filtering parent and adapter variables.
Add `NVIM_AI_CONTROL_PYTHON` as the manifest's validated canonical Python path after verifying canonical `sys.executable` matches it, and document the in-sandbox helper invocation as `$NVIM_AI_CONTROL_PYTHON -I -B $NVIM_AI_CONTROL_HELPER request-scope ...`.
Do not add them to adapter-controlled environment allowlists.

- [ ] **Step 7: Implement bounded structured event normalization**

Create executable `.config/nvim/scripts/nvim-ai-event.py`.
For Claude hook mode, read at most 65536 bytes of JSON from stdin, map only lifecycle and permission event names, and append one normalized compact JSON line to a nonsymlink current-user-owned mode-0600 event file.
Use `os.open` with `O_RDWR | O_APPEND | O_CREAT | O_NOFOLLOW`, mode 0600, validate `fstat`, and take an exclusive `fcntl.flock` while checking size and writing.
When the next line would exceed 1 MiB, truncate under the same lock before appending that latest normalized record; the Lua reader must detect size shrink and restart at offset zero.
Write one line with one checked `os.write` call and fsync before unlocking.
Discard every field other than event name and validated session ID before constructing output.
Map Claude `SessionStart` and `PostToolUse` to `idle`, `UserPromptSubmit` and `PreToolUse` to `busy`, `PermissionRequest` to `approval`, `Stop` and `SessionEnd` to `completed`, and hook execution failure to no event rather than a fabricated state.

For OpenCode stream mode, use `urllib.request` to connect only to the adapter-provided `http://127.0.0.1:<port>/event` URL.
Supply basic authentication from `OPENCODE_SERVER_PASSWORD` in the process environment, never argv.
Parse Server-Sent Events incrementally with a 65536-byte event cap, normalize only session status, permission, completion, and failure event types, and reconnect with bounded exponential delays of 100, 250, 500, 1000, and 2000 milliseconds while the parent launcher remains alive.
Map OpenCode `session.status` values `idle`, `busy`, and `retry` to `idle`, `busy`, and `busy`; map `permission.asked` to `approval`, `session.idle` to `completed`, and `session.error` to `failed`; ignore every other type.

Create `.config/nvim/lua/ai/events.lua` as a read-only incremental NDJSON reader.
Require a nonsymlink current-user-owned mode-0600 regular file of at most 1 MiB, retain a byte offset, cap each line at 4096 bytes, reject unknown keys, and emit only records matching the active backend and exact session.
On reconnect, seed common status from only the last valid matching record without emitting historical transition notifications, then set the live offset to EOF.
Event records may improve display status but must never authorize a write, resolve a review path, accept a scope request, submit a prompt, or trigger an automatic backend switch.

Extend Claude adapter settings with fixed hook argv generated from the event helper and event file.
The hook command uses the canonical `paths.python`, literal `-I -B`, and the fixed event-helper path; no backend or event payload byte enters shell syntax.
Extend the OpenCode launch shape with launcher-private `event_url` and `event_file` fields.
Populate the Task 3 manifest's validated absolute `event_helper` and `event_file` paths, keep strict key-set tests, and mount the helper read-only plus the event-file parent writable.
Extend the launcher so its trusted event helper is a supervised child for OpenCode and is stopped with the server.

- [ ] **Step 8: Connect rich events to the session state machine**

Extend `.config/nvim/lua/ai/session.lua` with `coordinator:handle_event(event)`.
Require exact backend and session match, require the adapter capability for the incoming rich state, pass the state through Task 5's transition table, and publish a snapshot.
Accept launcher-originated common `open` and `failed` states for every backend without requiring a rich capability.
For a newly created OpenCode session whose durable reference is empty, accept the first valid `ses_` session ID from the authenticated loopback event feed, persist it atomically, and require exact matching for every later event.
Ignore duplicate, foreign-backend, foreign-session, and unsupported events; process valid records in append order rather than trusting wall-clock ordering.
Codex remains on common process and filesystem states and does not become unhealthy because its rich capabilities are false.

- [ ] **Step 9: Format and run scope, event, adapter, and launcher tests**

Run:

```sh
chmod 700 /home/ruohao/.config/nvim/scripts/nvim-ai-control.py \
  /home/ruohao/.config/nvim/scripts/nvim-ai-event.py
stylua /home/ruohao/.config/nvim/lua/ai/scope.lua \
  /home/ruohao/.config/nvim/lua/ai/events.lua \
  /home/ruohao/.config/nvim/lua/ai/session.lua \
  /home/ruohao/.config/nvim/lua/ai/backends/claude.lua \
  /home/ruohao/.config/nvim/lua/ai/backends/opencode.lua \
  /home/ruohao/.config/nvim/tests/ai_scope.lua \
  /home/ruohao/.config/nvim/tests/ai_backends.lua
python3 -I -B -c 'import ast,pathlib,sys; [ast.parse(pathlib.Path(item).read_text(encoding="utf-8"), filename=item) for item in sys.argv[1:]]' \
  /home/ruohao/.config/nvim/scripts/nvim-ai-control.py \
  /home/ruohao/.config/nvim/scripts/nvim-ai-event.py \
  /home/ruohao/.config/nvim/scripts/nvim-ai-launch.py \
  /home/ruohao/.config/nvim/tests/nvim_ai_control.py \
  /home/ruohao/.config/nvim/tests/nvim_ai_launch.py
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_scope.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_backends.lua
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_control.py
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_launch.py
```

Expected: all commands exit `0`; Lua prints `AI scope assertions: ok` and `AI backend adapter assertions: ok`; both Python suites end in `OK`.

- [ ] **Step 10: Commit scope and event control**

```sh
git add .config/nvim/lua/ai/scope.lua \
  .config/nvim/lua/ai/events.lua \
  .config/nvim/lua/ai/session.lua \
  .config/nvim/lua/ai/backends/claude.lua \
  .config/nvim/lua/ai/backends/opencode.lua \
  .config/nvim/scripts/nvim-ai-control.py \
  .config/nvim/scripts/nvim-ai-event.py \
  .config/nvim/scripts/nvim-ai-launch.py \
  .config/nvim/tests/ai_scope.lua \
  .config/nvim/tests/nvim_ai_control.py \
  .config/nvim/tests/ai_backends.lua \
  .config/nvim/tests/nvim_ai_launch.py
git commit -m "feat(nvim): broker AI scope requests"
```

### Task 11: Wire commands, mappings, prompt transactions, health, and compact status

**Files:**

- Create: `.config/nvim/lua/ai/status.lua`
- Create: `.config/nvim/lua/ai/init.lua`
- Create: `.config/nvim/lua/nvim-ai/health.lua`
- Create: `.config/nvim/tests/ai_status.lua`
- Modify: `.config/nvim/init.lua`
- Modify: `.config/nvim/lua/plugins/key-helper.lua`
- Modify: `.config/nvim/tests/key_helper.lua`
- Modify: `.config/nvim/lua/integrations/tmux_status.lua`
- Modify: `.config/nvim/lua/ui/statusline.lua`
- Modify: `.config/nvim/tests/statusline.lua`
- Modify: `.config/tmux/conf/status.conf`

**Interfaces:**

- Consumes: every stable interface from Tasks 1 through 10.
- Produces: `require("ai").setup(options) -> runtime` and idempotent setup.
- Produces: `runtime:open()`, `runtime:prompt(mode)`, `runtime:backend()`, `runtime:review(options)`, `runtime:grants()`, `runtime:show_status()`, `runtime:close()`, and `runtime:shutdown()`.
- Produces: `status.new(options) -> status`, `status:update(snapshot, category)`, `status:compact()`, `status:detail()`, `status:subscribe(callback)`, and `status:stop()`.
- Produces global commands `NvimAIOpen`, `NvimAIPrompt`, `NvimAIBackend`, `NvimAIReview`, `NvimAIGrants`, `NvimAIStatus`, and `NvimAIClose`.
- Produces mappings `<leader>aa`, `<leader>ap`, `<leader>ab`, `<leader>ar`, `<leader>ag`, `<leader>as`, and `<leader>ax`.
- Publishes a sanitized compact string of at most 32 UTF-8 bytes as `snapshot.ai` and tmux option `@dotfiles_nvim_ai`.

- [ ] **Step 1: Write failing compact-status and notification tests**

Create `.config/nvim/tests/ai_status.lua` with these exact compact results and transition assertions:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local status_module = require("ai.status")
local notifications = {}
local redraws = 0
local status = status_module._test.new({
  notify = function(message, level) table.insert(notifications, { message = message, level = level }) end,
  redraw = function() redraws = redraws + 1 end,
})

local cases = {
  { { backend = nil, state = "closed", unresolved = 0, conflicts = 0 }, "" },
  { { backend = "codex", state = "open", unresolved = 0, conflicts = 0 }, "AI:C open" },
  { { backend = "claude", state = "busy", unresolved = 0, conflicts = 0 }, "AI:L busy" },
  { { backend = "opencode", state = "approval", unresolved = 0, conflicts = 0 }, "AI:O ?" },
  { { backend = "codex", state = "changes", unresolved = 3, conflicts = 0 }, "AI:C +3" },
  { { backend = "claude", state = "conflicted", unresolved = 2, conflicts = 1 }, "AI:L !" },
  { { backend = "opencode", state = "paused", unresolved = 0, conflicts = 0 }, "AI:O ||" },
}
for _, case in ipairs(cases) do
  status:update(case[1])
  eq(status:compact(), case[2], "compact " .. vim.inspect(case[1]))
  assert(#status:compact() <= 32, "compact status exceeds byte cap")
end

status:update({ backend = "claude", state = "approval", unresolved = 0, conflicts = 0 }, "approval")
status:update({ backend = "claude", state = "approval", unresolved = 0, conflicts = 0 }, "approval")
eq(#notifications, 1, "duplicate transition notification suppressed")
assert(notifications[1].message:find("<leader>aa", 1, true), "approval notification lacks focus mapping")
assert(redraws > 0, "status changes request redraw")
```

Add notification cases for completed, failed, files changed with `<leader>ar`, buffer conflict with `<leader>ar`, scope granted, scope refused, scope revoked, and restored paused with `<leader>aa`.
Add control stripping, C1 stripping, invalid backend and state fallback, count saturation at `999+`, transition away and back, stopped status, and a detailed status payload that excludes prompt text, context bytes, passwords, tokens, and authentication data.

- [ ] **Step 2: Write failing public command, mapping, and prompt-transaction tests**

Continue `.config/nvim/tests/ai_status.lua` with injected command, mapping, picker, context, tracker, session, review, scope, and status dependencies.
Use this exact registration matrix:

```lua
local ai_module = require("ai")
local commands, mappings = {}, {}
local runtime = ai_module._test.setup({
  create_command = function(name, callback, options) commands[name] = { callback = callback, options = options } end,
  set_keymap = function(mode, lhs, callback, options) mappings[lhs .. ":" .. mode] = { callback = callback, options = options } end,
  create_autocmd = function() end,
  create_augroup = function() return 1 end,
  components = fake_components(),
})

for _, name in ipairs({ "NvimAIOpen", "NvimAIPrompt", "NvimAIBackend", "NvimAIReview", "NvimAIGrants", "NvimAIStatus", "NvimAIClose" }) do
  assert(commands[name], "missing command " .. name)
end
for _, lhs in ipairs({ "<leader>aa", "<leader>ab", "<leader>ar", "<leader>ag", "<leader>as", "<leader>ax" }) do
  assert(mappings[lhs .. ":n"], "missing normal mapping " .. lhs)
end
assert(mappings["<leader>ap:n"], "missing normal prompt mapping")
assert(mappings["<leader>ap:x"], "missing visual prompt mapping")
eq(mappings["<leader>aa:n"].options.desc, "AI: open or focus companion", "mapping description")
```

Then assert the exact first-prompt transaction order:

```lua
local order = runtime._debug().order
assert(runtime:prompt("x"))
eq(order, {
  "resolve_identity",
  "attach",
  "pick_backend",
  "prepare_context",
  "create_baseline",
  "prepare_review",
  "open_writable",
  "format_context",
  "paste_without_submit",
  "focus",
}, "first prompt transaction")
eq(runtime._debug().pasted, "Use exact selection at /run/context/one.txt: ", "prepared prompt")
assert(not runtime._debug().pasted:match("[\r\n]$"), "prompt paste submits a newline")
```

Add normal prompt, existing pane, existing batch, picker cancellation, invalid normal context, context-write failure, baseline failure, writable-relaunch failure, pane-open failure, paste failure, focus failure, review picker, review abandonment with confirmation, grant listing and revocation, backend switching, detailed status, explicit close, `VimLeavePre`, and setup idempotence cases.
For every failure before paste, assert that a newly created empty batch is abandoned, the pane returns read-only, and a newly created context file is removed.
For an existing batch, assert that failure does not abandon or replace it.

- [ ] **Step 3: Add failing WhichKey, statusline, and tmux publication assertions**

Modify `.config/nvim/tests/key_helper.lua` to require these exact group entries:

```lua
assert_group("<leader>a", "AI", "n")
assert_group("<leader>a", "AI", "x")
```

Modify `.config/nvim/tests/statusline.lua` so `build_snapshot()` preserves `ai = "AI:C +3"`, control stripping applies to it, and `render_parts()` includes it as one existing-row component outside tmux.
Add tmux publisher assertions that canonicalization bounds `ai` to 32 bytes, claim and update argv set `@dotfiles_nvim_ai`, cleanup unsets it, and no value can introduce a tmux command separator.

Add a static assertion in `.config/nvim/tests/ai_status.lua` that `.config/tmux/conf/status.conf` references `#{qh:@dotfiles_nvim_ai}` only inside the active-Neovim status branch and still contains exactly one `set -g status-right` declaration.

- [ ] **Step 4: Run focused tests and verify public modules are missing**

Run:

```sh
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_status.lua
```

Expected: exit nonzero with `module 'ai.status' not found`.

- [ ] **Step 5: Implement compact status and transition notifications**

Create `.config/nvim/lua/ai/status.lua`.
Use this exact precedence:

```lua
local letters = { codex = "C", claude = "L", opencode = "O" }
local allowed_states = {
  closed = true, starting = true, open = true, idle = true, busy = true,
  completed = true, changes = true, failed = true,
}
local function compact(snapshot)
  local letter = letters[snapshot.backend]
  if not letter then return "" end
  local suffix
  if snapshot.state == "paused" then suffix = "||"
  elseif (tonumber(snapshot.conflicts) or 0) > 0 or snapshot.state == "conflicted" then suffix = "!"
  elseif snapshot.state == "approval" or snapshot.state == "attention" then suffix = "?"
  elseif (tonumber(snapshot.unresolved) or 0) > 0 then suffix = "+" .. saturate(snapshot.unresolved, 999)
  else suffix = allowed_states[snapshot.state] and snapshot.state or "open" end
  return bound_utf8(strip_controls("AI:" .. letter .. " " .. suffix), 32)
end
```

Store no prompt or context data in status.
Detailed status contains only backend, common or rich state, capability names, root, identity key, owner pane, managed pane, canonical grants, unresolved count, conflict count, and a boolean for each resumable session.
Deduplicate notifications by category plus backend plus state plus review ID plus affected path.
Notifications never call focus.
Use `vim.schedule` before notifying from watcher, process, socket, or event callbacks.

- [ ] **Step 6: Implement the public runtime and transactional prompt flow**

Create `.config/nvim/lua/ai/init.lua`.
Keep setup passive: register APIs and subscriptions, but do not resolve a root, create state directories, run a backend health command, create a socket, start a watcher, contact a provider, or launch a process until the first AI command.

Create a per-identity runtime lazily after `identity.resolve()`.
At that first runtime creation, eagerly require every Task 1 through Task 10 Lua module before any review batch can make the project writable, retain those module tables for the lifetime of Neovim, and never reload boundary code from an agent-editable path.
Let identity resolution obtain Git from the same `ai.tools` cache, then resolve one complete `AiHostTools` table, pass its canonical tmux path to the transport and its canonical Git path to review, and place its sorted Git and optional tmux paths in every launch manifest's `host_tools` list.
Revalidate cached device, inode, ownership, type, and mode before every external invocation and fail closed on drift.
Pin the first successful AI identity to the current Neovim instance.
If a later command resolves a different physical root or identity key, refuse it and instruct the user to open that worktree in its own Neovim instance or request an explicit scope grant from the pinned companion.
Select the tmux transport only when the identity has both owner pane and socket; otherwise select the terminal transport.
Call `session:attach()` before every pane action so reopen reconnects without relaunch.
When the durable record contains a review ID, call `baseline.open()` and start the tracker against that exact batch before accepting another prompt or review action.
If the durable baseline is missing or invalid, retain the review ID, mark the batch conflict-only, disable automatic rejection, and require explicit manual resolution or abandonment.

Implement `runtime:prompt(mode)` as this transaction:

1. Resolve identity and attach a unique companion.
2. When no active backend exists, show a picker with all three backends, disabled health entries included, and allow only an installed healthy selection.
   Treat `installed=true`, a compatible nonempty bounded version, and no executable or confinement health error as eligible.
   Allow `auth="authenticated"`, `auth="unknown"`, or `auth="unsupported"`, display the latter two as warnings, and disable only an explicit `auth="unauthenticated"` result.
   Never initiate login; if an allowed backend later reports an authentication problem in its native TUI, leave that TUI visible and report the common failed state.
3. Prepare normal or visual context without reading more than the approved context.
4. Call `tracker:ensure_batch()` and remember whether this invocation created it.
5. Bind the exact review ID through `session:prepare_review()`.
6. Open a missing pane directly with that writable review manifest, or relaunch the existing pane writable.
7. Format the context through the selected adapter.
8. Paste through the transport, focus the TUI, and never send Enter.
9. On failure before a successful paste, remove only the new context, abandon only a newly created empty batch, and restore read-only mode.

`runtime:review({ bang = true })` abandons a batch only after confirmation.
An empty batch may be abandoned directly after confirmation.
A nonempty batch confirmation must state that automatic rejection capability for unresolved changes will be removed.
Ordinary `runtime:review()` scans and opens Task 9's picker.

Register commands with descriptions and no completion side effects.
`NvimAIReview` supports `!` for explicit abandonment.
`NvimAIBackend` takes an optional exact backend name and otherwise opens the picker.
`NvimAIGrants` takes no argument to list and one canonical current grant to revoke through a picker.
Register mappings with `silent=true` and the descriptions in the approved mapping table.
Register one `VimLeavePre` callback that calls runtime shutdown, preserving tmux panes but closing standalone terminals and Neovim-owned sockets and watchers.

- [ ] **Step 7: Add nonmutating health reporting**

Create `.config/nvim/lua/nvim-ai/health.lua` with `check()` and `_test.check(deps)`.
Report Neovim platform, tmux executable and identity, Bubblewrap executable and a read-only self-check, physical root, private runtime and durable directory readiness, backend executable paths and versions, safe local authentication status, common and optional capabilities, and pane metadata diagnostics.

Resolve Bubblewrap with the same canonical absolute executable policy as the launcher.
The Bubblewrap self-check runs only this bounded command and writes nowhere:

```lua
{
  absolute_bwrap, "--new-session", "--unshare-pid", "--unshare-ipc", "--unshare-uts",
  "--die-with-parent", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--", "/bin/true",
}
```

On non-Linux platforms, report launch disabled without throwing.
Do not install, update, authenticate, start a TUI, create a session, or contact a provider.
Check prospective runtime and durable paths through their existing canonical ancestors and access bits without creating the application directories.
Bound and sanitize every external result before passing it to `vim.health`.

- [ ] **Step 8: Integrate the existing single status row**

Modify `.config/nvim/lua/integrations/tmux_status.lua` by adding `@dotfiles_nvim_ai` to `option_names`, adding `ai` to `snapshot_keys`, and adding `ai = safe_text(snapshot.ai, 32)` to `canonicalize()`.
This keeps AI publication inside the existing owner guard and atomic inactive-update-active transaction.

Modify `.config/nvim/lua/ui/statusline.lua` by adding `ai` to semantic snapshots, accepting an injected `ai_status` provider, and adding the compact AI string as a `DotfilesStatusContext` component immediately before the cursor component when not empty.
The existing tmux branch publishes the same `snapshot.ai`; the standalone branch renders it.
Call redraw through the existing controller rather than adding a second statusline owner.

Modify `.config/tmux/conf/status.conf` by prepending this exact fragment inside the active-Neovim `status-right` branch before path, diagnostics, and cursor:

```tmux
#{?#{&&:#{&&:#{==:#{@dotfiles_nvim_active},1},#{m/r:^(nvim|nvimdiff|nvim-wrapped|nvimdiff-wrapped)$,#{b:pane_current_command}}},#{m/r:^AI:[CLO] .{1#,24#}$,#{@dotfiles_nvim_ai}}},#[fg=#7dcfff#,bg=#2A2F41] #{qh:@dotfiles_nvim_ai} #[default],}
```

Keep `status on`, one bottom status row, and one `status-right` declaration.
Do not reload tmux as part of Neovim setup.

- [ ] **Step 9: Wire startup and WhichKey only after all safety modules exist**

Modify `.config/nvim/init.lua` by inserting this line after tmux persistence setup and before statusline setup:

```lua
require("ai").setup()
```

Modify `.config/nvim/lua/plugins/key-helper.lua` by inserting these two non-executable group declarations in the existing `spec` table:

```lua
{ "<leader>a", group = "AI", mode = { "n", "x" } },
```

Use one entry with both modes, not executable WhichKey proxy mappings.
Do not change `lazy-lock.json`.

- [ ] **Step 10: Format and run all focused UI and startup tests**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/status.lua \
  /home/ruohao/.config/nvim/lua/ai/init.lua \
  /home/ruohao/.config/nvim/lua/nvim-ai/health.lua \
  /home/ruohao/.config/nvim/lua/integrations/tmux_status.lua \
  /home/ruohao/.config/nvim/lua/ui/statusline.lua \
  /home/ruohao/.config/nvim/lua/plugins/key-helper.lua \
  /home/ruohao/.config/nvim/tests/ai_status.lua \
  /home/ruohao/.config/nvim/tests/statusline.lua \
  /home/ruohao/.config/nvim/tests/key_helper.lua \
  /home/ruohao/.config/nvim/init.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_status.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/statusline.lua
env -u TMUX -u TMUX_PANE NVIM_LOG_FILE=/dev/null \
  nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/key_helper.lua
ai_startup_root=$(mktemp -d "${TMPDIR:-/tmp}/nvim-ai-startup.XXXXXX")
trap 'case "$ai_startup_root" in "${TMPDIR:-/tmp}"/nvim-ai-startup.*) rm -rf -- "$ai_startup_root" ;; esac' EXIT HUP INT TERM
mkdir -m 700 "$ai_startup_root/state" "$ai_startup_root/runtime"
env -u TMUX -u TMUX_PANE \
  XDG_STATE_HOME="$ai_startup_root/state" \
  XDG_RUNTIME_DIR="$ai_startup_root/runtime" \
  NVIM_LOG_FILE=/dev/null \
  nvim --headless -i NONE \
  -c 'lua for _, name in ipairs({ "NvimAIOpen", "NvimAIPrompt", "NvimAIBackend", "NvimAIReview", "NvimAIGrants", "NvimAIStatus", "NvimAIClose" }) do assert(vim.fn.exists(":" .. name) == 2, name) end; assert(package.loaded["ai.session"] == nil, "passive startup constructed a session")' \
  -c qa
trap - EXIT HUP INT TERM
rm -rf -- "$ai_startup_root"
```

Expected: formatting and every command exit `0`; focused tests print their exact success lines; configured startup registers all commands and creates no session or backend process; the guarded temporary root is removed.

- [ ] **Step 11: Commit the public Neovim integration**

```sh
git add .config/nvim/lua/ai/status.lua \
  .config/nvim/lua/ai/init.lua \
  .config/nvim/lua/nvim-ai/health.lua \
  .config/nvim/tests/ai_status.lua \
  .config/nvim/init.lua \
  .config/nvim/lua/plugins/key-helper.lua \
  .config/nvim/tests/key_helper.lua \
  .config/nvim/lua/integrations/tmux_status.lua \
  .config/nvim/lua/ui/statusline.lua \
  .config/nvim/tests/statusline.lua \
  .config/tmux/conf/status.conf
git commit -m "feat(nvim): expose native AI companions"
```

### Task 12: Prove private-tmux lifecycle and aggregate the complete checker

**Files:**

- Create: `.config/tmux/tests/nvim-ai.sh`
- Modify: `.config/dotfiles/check-terminal-stack`

**Interfaces:**

- Consumes: the complete milestones 1 through 5 implementation from Tasks 1 through 11.
- Produces: one provider-free private-tmux end-to-end harness.
- Produces: checker inventory, static checks, focused suites, real Bubblewrap checks, configured-startup checks, and one final zero-failure aggregate result.
- Does not consume or mutate workspace snapshot schema, the live tmux server, real provider state, or real model APIs.

- [ ] **Step 1: Write a failing private-tmux lifecycle harness**

Create executable `.config/tmux/tests/nvim-ai.sh` with this fixed safety skeleton:

```sh
#!/bin/sh
set -eu

test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nvim-ai.XXXXXX")
socket=$test_root/tmux.sock
real_tmux=$(command -v tmux)
tmux_started=false

cleanup() {
  if [ "$tmux_started" = true ] && [ -S "$socket" ]; then
    "$real_tmux" -S "$socket" kill-server >/dev/null 2>&1 || true
  fi
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dotfiles-nvim-ai.*) rm -rf -- "$test_root" ;;
    *) printf 'refusing unsafe AI test cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -m 700 "$test_root/bin" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/root" "$test_root/outside"
"$real_tmux" -S "$socket" -f /dev/null start-server
tmux_started=true
```

Create a test-owned `tmux` shim in `$test_root/bin` that exits `97` unless argv begins with `-S "$socket"`, then execs the captured real tmux.
This makes any accidental default-server call fail without connecting to the default server.

Create test-owned fake `codex`, `claude`, and `opencode` executables in the same bin directory.
Codex and Claude must support only their exact version and local-auth commands from Task 2 plus their exact launch and resume forms.
OpenCode must support the audited version, help, agent-list, five-agent debug, and two disabled-agent negative probes plus the exact managed server and attach forms from the managed-profile plan.
Create one mode-0600 synthetic OpenCode `auth.json` under the harness home and require the generated managed profile to contain only its accepted fake credential record.
Codex and Claude write one bounded session sentinel into their identity-specific backend-state directory and remain attached to the terminal until signaled.
For `opencode serve`, start a loopback Python HTTP server on the requested port with an empty event stream.
For `opencode attach`, remain attached to the native terminal until signaled.
Every unsupported argv exits `96` and logs only argv shape, never environment secrets.
The fake TUI creates a `turn-started` sentinel only after it receives a newline.
When a submitted line starts with `scope `, it invokes the fixed `NVIM_AI_CONTROL_HELPER request-scope` command with the requested test path and records only the returned grant code.

- [ ] **Step 2: Add exact owner, reconnect, switch, grant, paste, and duplicate assertions**

Continue `.config/tmux/tests/nvim-ai.sh` with helpers that always call the shim as `tmux -S "$socket"`.
Create a Git repository beneath `$test_root/root`, two owner panes in one tmux window, and set `remain-on-exit` for both owner panes.
Start headless Neovim in each owner through this function:

```sh
start_owner_nvim() {
  owner_name=$1
  owner_pane=$2
  owner_state=$test_root/state/$owner_name
  owner_runtime=$test_root/runtime/$owner_name
  mkdir -m 700 "$owner_state" "$owner_runtime"
  owner_command="exec env -u NVIM_APPNAME HOME=$(shell_quote "$test_root/home") XDG_STATE_HOME=$(shell_quote "$owner_state") XDG_RUNTIME_DIR=$(shell_quote "$owner_runtime") PATH=$(shell_quote "$test_root/bin:$PATH") NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE --listen $(shell_quote "$owner_runtime/nvim.sock") -c $(shell_quote 'set runtimepath^=/home/ruohao/.config/nvim') -c $(shell_quote "cd $test_root/root") -c $(shell_quote "edit $test_root/root/main.lua") -c $(shell_quote 'lua require("ai").setup({ confirm = function(_, callback) callback(true) end })') -c $(shell_quote 'sleep 1d')"
  tmux -S "$socket" respawn-pane -k -t "$owner_pane" "$owner_command"
}
```

Call it as `start_owner_nvim owner-a "$owner_a"` and `start_owner_nvim owner-b "$owner_b"`.
Define `shell_quote()` before this function and reject newline, carriage return, NUL, and other controls in every generated path before quoting.
Wait for the Neovim listen socket with a bounded retry loop and fail after five seconds.

Drive commands with `nvim --server SOCKET --remote-expr 'execute("COMMAND")'` and assert all of these outcomes:

1. `NvimAIBackend codex` creates exactly one right-hand AI pane for owner A.
2. The AI pane has exact key, owner, root, backend, state, grant-hash, session, and empty OpenCode profile options.
3. Its left coordinate is greater than owner A's left coordinate and its width is 40 percent within tmux rounding.
4. Repeating `NvimAIOpen` focuses the same pane and creates none.
5. Owner B in the same physical root receives a different identity key and different AI pane.
6. Exiting owner A's Neovim leaves its AI pane and fake backend alive.
7. Respawning Neovim in the same dead owner pane reconnects to the same AI pane without another fake-backend launch sentinel.
8. `NvimAIBackend claude` and then `NvimAIBackend opencode` reuse that pane and retain independent session references.
9. The OpenCode pane exposes the exact nonsecret token, fingerprint, and version options, and its managed configuration tree is read-only.
10. Exiting and respawning owner A's Neovim again adopts that same OpenCode pane and exact profile tuple without another profile publication or fake-backend launch sentinel.
11. A visual `NvimAIPrompt` pastes the context reference, creates one review ID, relaunches writable with the same profile tuple, leaves the prompt unsubmitted, and leaves no tmux paste buffer.
12. Absence of the fake `turn-started` sentinel proves Neovim did not submit the prepared prompt; the harness then clears the fake TUI input, types `scope $test_root/outside`, and submits that test command explicitly.
13. The approved scope request canonicalizes `$test_root/outside`, relaunches once with the same profile tuple, survives a backend switch, and leaves no automatically continued prompt.
14. Revocation relaunches once and removes the grant.
15. A manually created duplicate pane with the same exact identity and profile metadata makes `NvimAIOpen` refuse and name both pane IDs.
16. Removing the duplicate restores normal focus behavior.
17. `NvimAIClose` removes only the owned AI pane, revokes grants, removes context files, clears the active profile reference, and retains backend session references.
18. Owner B and its companion remain untouched throughout owner A operations.

Use pane options and fake-backend sentinel files as authoritative evidence.
Do not scrape TUI text to infer backend state.
At the end, query `list-buffers -F '#{buffer_name}'` through the private socket and require no `dotfiles-nvim-ai-` buffer.
Print exactly `ok - nvim AI private tmux lifecycle` on success.

- [ ] **Step 3: Run the new harness and verify it fails before aggregate wiring**

Run:

```sh
chmod 700 /home/ruohao/.config/tmux/tests/nvim-ai.sh
shellcheck /home/ruohao/.config/tmux/tests/nvim-ai.sh
env -u TMUX -u TMUX_PANE /home/ruohao/.config/tmux/tests/nvim-ai.sh
```

Expected before completing harness support: shellcheck exits `0`, and the harness exits nonzero at the first unmet AI lifecycle assertion.
Expected after Tasks 1 through 11 are correctly integrated: both exit `0`, and the harness prints exactly `ok - nvim AI private tmux lifecycle`.

- [ ] **Step 4: Add every new source to both checker inventories**

Modify both the `static_lint_file` loop and the `nvim_file` readiness loop in `.config/dotfiles/check-terminal-stack`.
Insert these exact paths in sorted responsibility groups:

```sh
"$nvim_root/lua/ai/backends/claude.lua"
"$nvim_root/lua/ai/backends/codex.lua"
"$nvim_root/lua/ai/backends/init.lua"
"$nvim_root/lua/ai/backends/opencode.lua"
"$nvim_root/lua/ai/context.lua"
"$nvim_root/lua/ai/events.lua"
"$nvim_root/lua/ai/identity.lua"
"$nvim_root/lua/ai/init.lua"
"$nvim_root/lua/ai/review/baseline.lua"
"$nvim_root/lua/ai/review/reducer.lua"
"$nvim_root/lua/ai/review/tracker.lua"
"$nvim_root/lua/ai/review/ui.lua"
"$nvim_root/lua/ai/sandbox.lua"
"$nvim_root/lua/ai/scope.lua"
"$nvim_root/lua/ai/session.lua"
"$nvim_root/lua/ai/state.lua"
"$nvim_root/lua/ai/status.lua"
"$nvim_root/lua/ai/tools.lua"
"$nvim_root/lua/ai/transports/terminal.lua"
"$nvim_root/lua/ai/transports/tmux.lua"
"$nvim_root/lua/nvim-ai/health.lua"
"$nvim_root/scripts/nvim-ai-control.py"
"$nvim_root/scripts/nvim-ai-event.py"
"$nvim_root/scripts/nvim-ai-launch.py"
"$nvim_root/scripts/nvim-ai-review.py"
"$nvim_root/tests/ai_backends.lua"
"$nvim_root/tests/ai_context.lua"
"$nvim_root/tests/ai_identity.lua"
"$nvim_root/tests/ai_review.lua"
"$nvim_root/tests/ai_sandbox.lua"
"$nvim_root/tests/ai_scope.lua"
"$nvim_root/tests/ai_status.lua"
"$nvim_root/tests/ai_transport.lua"
"$nvim_root/tests/nvim-ai-sandbox.sh"
"$nvim_root/tests/nvim_ai_control.py"
"$nvim_root/tests/nvim_ai_launch.py"
"$nvim_root/tests/nvim_ai_review.py"
"$config_root/tmux/tests/nvim-ai.sh"
```

Retain the existing entries for modified startup, WhichKey, statusline, tmux status, and checker files.
Require the four Python scripts and two shell harnesses to be executable and nonsymlinked.

- [ ] **Step 5: Add exact Python, shell, Lua, sandbox, and private-tmux checker blocks**

Add these checker stages after existing static Neovim source checks and before configured startup:

```sh
ai_python_output="$check_tmp/nvim-ai-python.txt"
if PYTHONDONTWRITEBYTECODE=1 python3 -I -B -c \
  'import ast,pathlib,sys; [ast.parse(pathlib.Path(item).read_text(encoding="utf-8"), filename=item) for item in sys.argv[1:]]' \
  "$nvim_root/scripts/nvim-ai-control.py" \
  "$nvim_root/scripts/nvim-ai-event.py" \
  "$nvim_root/scripts/nvim-ai-launch.py" \
  "$nvim_root/scripts/nvim-ai-review.py" \
  "$nvim_root/tests/nvim_ai_control.py" \
  "$nvim_root/tests/nvim_ai_launch.py" \
  "$nvim_root/tests/nvim_ai_review.py" \
  > "$ai_python_output" 2>&1 \
  && [ ! -s "$ai_python_output" ]; then
  pass "Neovim AI Python sources parse without repository bytecode"
else
  sed 's/^/      /' "$ai_python_output" >&2
  fail "Neovim AI Python source parsing failed"
fi

ai_lua_passed=true
for ai_lua_test in ai_identity ai_backends ai_sandbox ai_transport ai_context ai_review ai_scope ai_status; do
  ai_lua_output="$check_tmp/nvim-$ai_lua_test.txt"
  if ! env -u TMUX -u TMUX_PANE -u NVIM_APPNAME \
    HOME="$check_tmp/nvim-ai-home" \
    XDG_STATE_HOME="$check_tmp/nvim-ai-state" \
    XDG_RUNTIME_DIR="$check_tmp/nvim-ai-runtime" \
    NVIM_LOG_FILE=/dev/null \
    nvim --clean --headless -u NONE -i NONE \
    -c "set runtimepath^=$nvim_root" \
    -l "$nvim_root/tests/$ai_lua_test.lua" \
    > "$ai_lua_output" 2>&1 \
    || nvim_log_has_error "$ai_lua_output"; then
    sed 's/^/      /' "$ai_lua_output" >&2
    ai_lua_passed=false
  fi
done
if [ "$ai_lua_passed" = true ]; then
  pass "Neovim AI focused Lua assertions pass"
else
  fail "Neovim AI focused Lua assertions failed"
fi
```

Create the three private directories once with mode 0700 before the Lua loop and remove no user path.
Add separate exact blocks for all three Python unittest scripts, `shellcheck` on both shell harnesses, the real Bubblewrap harness, and the private-tmux harness.
Each block captures stdout and stderr below `$check_tmp`, checks the exact success line, and records one checker pass or failure.
Do not skip confinement or lifecycle failures on Linux.
Do not invoke a real Codex, Claude, or OpenCode executable.

- [ ] **Step 6: Preserve the configured-startup argument ceiling**

In the existing configured Neovim command, change only this embedded Lua list:

```lua
{ "platform", "foundation", "key_helper" }
```

to:

```lua
{ "platform", "foundation", "key_helper", "ai_status" }
```

Do not add another `-c` or `--cmd` argument.
Keep the configured invocation at exactly ten command arguments, including the final `-c qa`.
Extend its assertions to require all seven `NvimAI*` commands, require zero managed pane or backend process at passive startup, and require no AI runtime or durable directory before the first AI command.

- [ ] **Step 7: Run every focused suite and the complete aggregate checker**

Run:

```sh
shellcheck /home/ruohao/.config/dotfiles/check-terminal-stack \
  /home/ruohao/.config/nvim/tests/nvim-ai-sandbox.sh \
  /home/ruohao/.config/tmux/tests/nvim-ai.sh
env -u TMUX -u TMUX_PANE /home/ruohao/.config/nvim/tests/nvim-ai-sandbox.sh
env -u TMUX -u TMUX_PANE /home/ruohao/.config/tmux/tests/nvim-ai.sh
/home/ruohao/.config/dotfiles/check-terminal-stack
```

Expected: every command exits `0`; the two harnesses print their exact `ok` lines; the checker ends with `Summary: 0 failure(s), 0 warning(s)`.
Confirm with `ps` that no fake backend, event helper, private tmux server, or test Neovim remains after the checker.
Report that fresh tmux servers load the status fragment automatically and an already running user tmux server needs the existing `prefix R` foundation reload once; do not issue that live-server reload from tests or implementation automation.

- [ ] **Step 8: Commit aggregate verification**

```sh
git add .config/tmux/tests/nvim-ai.sh \
  .config/dotfiles/check-terminal-stack
git commit -m "test(nvim): verify native AI companions"
```

- [ ] **Step 9: Request authorization before real-provider smoke tests**

Do not run a real provider command as part of automated execution.
After reporting the zero-failure checker result, ask the user for explicit authorization to make one paid or authenticated request with each installed backend.
If authorized, use this exact bounded manual matrix and make no commit from it:

1. Run `:checkhealth nvim-ai` and verify it makes no provider call.
2. Run `:NvimAIBackend codex`, `:NvimAIPrompt`, inspect the prepared prompt, submit it manually, request one harmless edit to a new `nvim-ai-smoke-codex.txt`, inspect it in review, reject the matching created file, and close the pane.
3. Repeat with Claude and `nvim-ai-smoke-claude.txt`, rejecting the matching created file through review.
4. Repeat with OpenCode and `nvim-ai-smoke-opencode.txt`, rejecting the matching created file through review.
5. For each backend, reopen the same identity, verify its exact conversation resumes, and close it again.
6. Verify all three exact smoke files are absent and no other worktree path changed.
7. Re-run `/home/ruohao/.config/dotfiles/check-terminal-stack` and require `Summary: 0 failure(s), 0 warning(s)`.

If authorization is denied, record the three real-provider smoke tests as intentionally unrun and leave the automated implementation complete.

## Deferred Workspace Restoration Plan

This implementation ends after milestones 1 through 5 and intentionally does not change the active workspace snapshot schema.
After the line-pin schema-2 work is accepted and integrated, write a separate plan against that exact new baseline for paused AI pane restoration.
That follow-up plan owns only these responsibilities:

- Reconcile the final schema-2 owner and pane records before naming fields.
- Serialize bounded companion identity, backend, session references, review ID, and paused state without prompt content, context bytes, tokens, passwords, or scope grants.
- Remap saved owner pane IDs transactionally during restore.
- Restore layout metadata and a paused diagnostic pane without starting Codex, Claude, OpenCode, the launcher, a fake backend, or a provider request.
- Reattach durable review state, degrade missing baseline to conflict-only, and require explicit `NvimAIOpen` to resume.
- Add schema validation, rollback, missing-backend, empty-grant, and no-sentinel-process tests to the then-current workspace suites.

Do not begin that follow-up by modifying `.config/tmux/scripts/workspace`, `.config/tmux/tests/workspace-state.sh`, `.config/tmux/tests/workspace-restore.sh`, `.config/nvim/lua/integrations/tmux_persistence.lua`, or `.config/nvim/tests/tmux_persistence.lua` from this plan's branch.
