# Neovim Managed OpenCode Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.
>
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unsafe OpenCode adapter policy with an audited OpenCode `v1.18.18` managed profile that preserves native Build and Plan behavior while excluding configuration-based permission overrides.

**Architecture:** A focused Lua module owns the exact version, permission, agent, environment, and compatibility contract.
A Python standard-library helper validates credentials and instructions and atomically publishes an immutable identity-specific profile.
The planned Bubblewrap launcher independently validates that profile, mounts it read-only after the writable backend-state bind, and gives the server and attach client one matching fingerprint.

**Tech Stack:** Neovim 0.12 Lua, `vim.system`, `vim.uv`, Python 3 standard library, Bubblewrap 0.11 or newer, OpenCode `v1.18.18`, and the existing headless Neovim and shell test harnesses.

## Global Constraints

- Implement the approved design in `.config/docs/superpowers/specs/2026-08-24-neovim-managed-opencode-profile-design.md`.
- Start from commit `6223541dfe2c2b966d16397f7d532942b893c73e` on branch `agent/nvim-ai-cli-companion`.
- Preserve the approved Task 1 commits and the Codex and Claude behavior in Task 2.
- Treat commits `00e78e0` and `28bf53c` as the unapproved Task 2 candidate to repair, not as an accepted boundary.
- Support only the exact normalized OpenCode version `1.18.18` until another version receives its own audited entry.
- Reuse only the installed OpenCode executable and validated `api` or `oauth` credentials.
- Do not load global or project OpenCode configuration, `account.json`, `mcp-auth.json`, custom agents, commands, skills, plugins, MCP definitions, or remote instructions.
- Preserve native Build and Plan definitions and native switching.
- Keep the top-level policy free of wildcard, `read`, and `edit` rules.
- Require `bash`, `webfetch`, `websearch`, `external_directory`, and `doom_loop` approval.
- Deny `task` and `skill`.
- Disable native user-facing `general` and `explore` subagents.
- Keep `compaction`, `title`, and `summary` available with effective denial of actionable tools.
- Snapshot `$HOME/AGENTS.md` before `<physical-root>/AGENTS.md`, deduplicate identical files, and inject no other instruction source.
- Require the inherited `HOME` to resolve to a canonical current-user-owned directory before masking its `.opencode` child.
- Keep every profile directory mode 0700 and every profile file mode 0600.
- Construct unpublished OpenCode generations beside the backend state directory beneath the trusted identity-specific `backends` parent, never inside the exact backend-state child exposed writable to OpenCode.
- Never put real credential contents in argv, environment, diagnostics, logs, tmux options, fingerprints, or tests.
- Use synthetic credentials only in automated tests and never contact a model provider.
- Fail closed without falling back to the user's ordinary OpenCode profile.
- Use TDD and commit after each independently reviewable task.
- Freeze every task commit for one fresh specification review and one separate quality review before beginning the next task.
- Never add an agent co-author trailer to a commit.

---

## File Map

### Managed OpenCode contract

- Create `.config/nvim/lua/ai/backends/opencode_managed.lua`.
  This module owns the exact audited version, canonical policy and configuration, profile request shape, launch environment, and semantic compatibility validation.
- Modify `.config/nvim/lua/ai/backends/opencode.lua`.
  This adapter delegates all OpenCode policy and profile decisions to `opencode_managed.lua` and retains only the common adapter methods.
- Modify `.config/nvim/lua/ai/backends/init.lua`.
  The registry provides isolated OpenCode probes and invokes the validated profile helper without exposing secret output.
- Modify `.config/nvim/tests/ai_backends.lua`.
  This test keeps the common three-backend contract and removes superseded OpenCode mount expectations.
- Create `.config/nvim/tests/ai_opencode_managed.lua`.
  This focused test owns exact OpenCode policy, version, probe semantics, launch shape, and profile-helper integration.

### Profile materialization

- Create `.config/nvim/scripts/nvim-ai-opencode-profile.py`.
  This helper strictly validates credentials and instruction sources and atomically publishes one immutable profile generation.
- Create `.config/nvim/tests/nvim_ai_opencode_profile.py`.
  This standard-library unit test owns duplicate-key rejection, credential filtering, instruction ordering, file races, bounds, modes, atomic publication, and secret-free diagnostics.

### Launcher enforcement

- Create `.config/nvim/lua/ai/sandbox.lua`.
  This module admits the exact `AiOpenCodeManagedProfile` shape into the launch manifest and rejects it for every other backend.
- Create `.config/nvim/scripts/nvim-ai-launch.py`.
  This launcher independently revalidates the profile, exact OpenCode environment, mount ordering, home mask, and server-to-attach agreement.
- Create `.config/nvim/tests/ai_sandbox.lua`.
  This test owns Lua manifest publication for managed OpenCode launches.
- Create `.config/nvim/tests/nvim_ai_launch.py`.
  This test owns Python validation, exact environment values, and nested read-only bind order.
- Create `.config/nvim/tests/nvim-ai-sandbox.sh`.
  This harness proves that the managed profile remains read-only while normal project and backend-state rules still work.
- Create `.config/nvim/tests/nvim-ai-opencode-compat.sh`.
  This real-binary harness proves that hostile configuration is ignored and native agent semantics remain correct without live credentials or network access.

---

### Task 1: Define the exact managed OpenCode contract

**Files:**

- Create: `.config/nvim/lua/ai/backends/opencode_managed.lua`
- Create: `.config/nvim/tests/ai_opencode_managed.lua`

**Interfaces:**

- Produces: `managed.version() -> "1.18.18"`.
- Produces: `managed.policy() -> table<string,string>` with a fresh table on every call.
- Produces: `managed.policy_json() -> string` with one canonical encoding.
- Produces: `managed.config() -> table` and `managed.config_json() -> string` with fresh values.
- Produces: `managed.profile_request(identity, paths, token) -> AiOpenCodeProfileRequest|nil, string|nil`.
- Produces: `managed.profile_reference(profile) -> { token, fingerprint, version }|nil, string|nil`.
- Produces: `managed.validate_compatibility(report) -> true|nil, string|nil`.
- Produces: `managed.environment(profile, password) -> table|nil, string|nil`.
- Consumes: `AiIdentity`, canonical backend paths, a 32-character lowercase hexadecimal token, and a parsed local compatibility report.

- [ ] **Step 1: Write the failing managed-contract test**

Create `.config/nvim/tests/ai_opencode_managed.lua` with these exact contract assertions:

```lua
local function eq(actual, expected, label)
  assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual)))
end

local managed = require("ai.backends.opencode_managed")

eq(managed.version(), "1.18.18", "audited OpenCode version")
eq(managed.policy(), {
  bash = "ask",
  doom_loop = "ask",
  external_directory = "ask",
  skill = "deny",
  task = "deny",
  webfetch = "ask",
  websearch = "ask",
}, "managed permission policy")
assert(managed.policy()["*"] == nil, "no wildcard permission")
assert(managed.policy().read == nil, "native read permission preserved")
assert(managed.policy().edit == nil, "native edit permission preserved")

local config = managed.config()
eq(config.autoupdate, false, "configuration also disables updates")
eq(config.permission, managed.policy(), "file and environment policies agree")
eq(managed.config_json(), '{"$schema":"https://opencode.ai/config.json","autoupdate":false,"permission":{"bash":"ask","doom_loop":"ask","external_directory":"ask","skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"},"agent":{"general":{"disable":true},"explore":{"disable":true},"compaction":{"permission":{"*":"deny"}},"summary":{"permission":{"*":"deny"}},"title":{"permission":{"*":"deny"}}}}', "canonical managed configuration")
eq(config.agent.general, { disable = true }, "general subagent disabled")
eq(config.agent.explore, { disable = true }, "explore subagent disabled")
for _, name in ipairs({ "compaction", "summary", "title" }) do
  eq(config.agent[name], { permission = { ["*"] = "deny" } }, name .. " remains tool-denied")
end
assert(config.agent.build == nil and config.agent.plan == nil, "native Build and Plan are not replaced")

local request = assert(managed.profile_request({
  key = string.rep("a", 32),
  root = "/work/repo",
}, {
  backend_state = "/state/identity/backends/opencode",
  global_opencode_data = "/home/user/.local/share/opencode",
  home_agents = "/home/user/AGENTS.md",
  profile_helper = "/config/nvim/scripts/nvim-ai-opencode-profile.py",
  python = "/usr/bin/python3",
}, string.rep("b", 32)))
eq(request.global_auth, "/home/user/.local/share/opencode/auth.json", "auth-only source")
eq(request.user_agents, "/home/user/AGENTS.md", "global instruction source")
eq(request.repo_agents, "/work/repo/AGENTS.md", "repository instruction source")
assert(vim.inspect(request):find("account.json", 1, true) == nil, "account data excluded")
assert(vim.inspect(request):find("mcp-auth.json", 1, true) == nil, "MCP auth excluded")

local managed_profile = {
  schema = 1,
  version = "1.18.18",
  profile_root = "/state/identity/backends/opencode/profiles/" .. string.rep("b", 32),
  fingerprint = string.rep("c", 64),
}
eq(assert(managed.profile_reference(managed_profile)), {
  token = string.rep("b", 32),
  fingerprint = string.rep("c", 64),
  version = "1.18.18",
}, "bounded durable profile reference")
eq(assert(managed.environment(managed_profile, "0123456789abcdef0123456789abcdef")), {
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
}, "exact managed launch environment")

local good = require("ai.backends.opencode_managed")._test.compatibility_fixture()
assert(managed.validate_compatibility(good))
for _, mutation in ipairs({ "version", "agents", "build_edit", "plan_edit", "risk", "hidden_tools" }) do
  local changed = vim.deepcopy(good)
  require("ai.backends.opencode_managed")._test.mutate_compatibility(changed, mutation)
  local ok, err = managed.validate_compatibility(changed)
  assert(ok == nil and type(err) == "string" and err ~= "", "compatibility mutation rejected: " .. mutation)
end

print("AI managed OpenCode assertions: ok")
```

The fixture must model exactly five remaining agents named `build`, `compaction`, `plan`, `summary`, and `title`.
It must model Build repository editing as allowed, Plan repository editing as denied, the five risk permissions as `ask`, `task` and `skill` as `deny`, and every actionable hidden-agent tool as unavailable.
Add table-driven rejection cases for a changed schema, version, profile-root component, token, fingerprint, password, configuration key, policy key, unknown compatibility field, and oversized report.

- [ ] **Step 2: Run the focused test and verify the module is missing**

Run:

```sh
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_opencode_managed.lua
```

Expected: exit nonzero with `module 'ai.backends.opencode_managed' not found`.

- [ ] **Step 3: Implement canonical policy, configuration, and profile requests**

Create `.config/nvim/lua/ai/backends/opencode_managed.lua` around these immutable values:

```lua
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

local POLICY_JSON = '{"bash":"ask","doom_loop":"ask","external_directory":"ask","skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"}'
local CONFIG_JSON = '{"$schema":"https://opencode.ai/config.json","autoupdate":false,"permission":{"bash":"ask","doom_loop":"ask","external_directory":"ask","skill":"deny","task":"deny","webfetch":"ask","websearch":"ask"},"agent":{"general":{"disable":true},"explore":{"disable":true},"compaction":{"permission":{"*":"deny"}},"summary":{"permission":{"*":"deny"}},"title":{"permission":{"*":"deny"}}}}'
```

Return deep copies from table accessors.
Return the fixed `POLICY_JSON` string instead of relying on Lua table iteration order.
Return the fixed `CONFIG_JSON` string, require `CONFIG` to normalize to that exact object in tests, and return a deep copy of `CONFIG` from the table accessor with no user-controlled interpolation.

`profile_request()` must return exactly these keys and reject every noncanonical path, control character, wrong identity key, and invalid token:

```lua
{
  schema = 1,
  token = token,
  identity_key = identity.key,
  root = identity.root,
  backend_state = paths.backend_state,
  global_auth = paths.global_opencode_data .. "/auth.json",
  user_agents = paths.home_agents,
  repo_agents = identity.root .. "/AGENTS.md",
  version = VERSION,
  config_json = managed.config_json(),
  policy_json = POLICY_JSON,
}
```

`profile_reference()` must accept only schema 1, the audited version, a profile root whose final two components are `profiles/TOKEN`, a 32-character lowercase hexadecimal token, and a 64-character lowercase hexadecimal fingerprint.
It returns only the token, fingerprint, and version so no credential path enters durable state or tmux metadata.

`environment()` must derive the canonical backend-state directory from the validated profile root and return exactly these values after validating the 32-character lowercase hexadecimal password:

```lua
{
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
```

- [ ] **Step 4: Implement semantic compatibility validation**

Require a report with this exact shape:

```lua
{
  version = "1.18.18",
  help = {
    root = { "--pure", "serve", "attach" },
    serve = { "--hostname", "--port", "OPENCODE_SERVER_PASSWORD" },
    attach = { "--dir", "--session" },
  },
  names = { "build", "compaction", "plan", "summary", "title" },
  agents = {
    build = { native = true, mode = "primary", tools = {}, permission = {} },
    plan = { native = true, mode = "primary", tools = {}, permission = {} },
    compaction = { native = true, hidden = true, tools = {}, permission = {} },
    summary = { native = true, hidden = true, tools = {}, permission = {} },
    title = { native = true, hidden = true, tools = {}, permission = {} },
  },
}
```

Implement a last-matching-rule evaluator for the literal probe path `src/nvim_ai_probe.lua`.
Treat a rule as matching when its permission is the requested permission or `*` and its pattern is `*` or the literal probe path.
Validate that Build resolves `edit` to `allow`, Plan resolves `edit` to `deny`, both primary agents resolve the five risk permissions to `ask`, and both resolve `task` and `skill` to `deny`.
Require every hidden agent to expose exactly the audited tool keys `invalid`, `question`, `bash`, `read`, `glob`, `grep`, `edit`, `write`, `task`, `webfetch`, `todowrite`, `websearch`, and `skill`, with every value equal to `false`.
Reject unknown report keys, missing fields, duplicate names, controls, and reports larger than 1 MiB before semantic evaluation.

- [ ] **Step 5: Run formatting and the focused test**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/backends/opencode_managed.lua \
  /home/ruohao/.config/nvim/tests/ai_opencode_managed.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_opencode_managed.lua
```

Expected: formatting exits `0`, and the test prints exactly `AI managed OpenCode assertions: ok`.

- [ ] **Step 6: Commit the managed contract**

```sh
git add .config/nvim/lua/ai/backends/opencode_managed.lua \
  .config/nvim/tests/ai_opencode_managed.lua
git commit -m "feat(nvim): define managed OpenCode policy"
```

### Task 2: Materialize strict credentials-only profiles

**Files:**

- Create: `.config/nvim/scripts/nvim-ai-opencode-profile.py`
- Create: `.config/nvim/tests/nvim_ai_opencode_profile.py`

**Interfaces:**

- Consumes stdin JSON matching `AiOpenCodeProfileRequest` for the `prepare` subcommand.
- Consumes stdin JSON `{ "global_auth": ABSOLUTE_PATH }` for the `inspect-auth` subcommand.
- Consumes this exact stdin object for the `inspect-profile` subcommand:

```json
{
  "schema": 1,
  "backend_state": "/state/identity/backends/opencode",
  "token": "32-lowercase-hex",
  "identity_key": "32-lowercase-hex",
  "root": "/canonical/physical/root",
  "version": "1.18.18",
  "fingerprint": "64-lowercase-hex"
}
```

- Produces one bounded JSON object on stdout and no other stdout content.
- Produces `prepare_profile(request) -> AiOpenCodeManagedProfile` for isolated unit tests.
- Produces `inspect_auth(path) -> { "auth": "authenticated"|"unauthenticated", "count": integer }`.
- Produces `inspect_profile(request) -> AiOpenCodeManagedProfile` without publishing or replacing a profile.
- Creates no subprocess and performs no network operation.

- [ ] **Step 1: Write failing Python profile tests**

Create `.config/nvim/tests/nvim_ai_opencode_profile.py` and import the helper through `importlib.util.spec_from_file_location`.
Use one mode-0700 temporary backend state, one mode-0600 synthetic `auth.json`, one mode-0644 user instruction file, and one mode-0644 repository instruction file.

Include these assertions:

```python
class CredentialTests(unittest.TestCase):
    def test_filters_to_exact_api_and_oauth_schemas(self):
        source = {
            "anthropic": {"type": "api", "key": "api-canary"},
            "openai": {
                "type": "oauth",
                "refresh": "refresh-canary",
                "access": "access-canary",
                "expires": 4102444800000,
                "accountId": "acct-test",
            },
            "https://managed.invalid": {
                "type": "wellknown",
                "key": "TOKEN",
                "token": "remote-config-canary",
            },
        }
        result = helper.filter_auth(json.dumps(source))
        self.assertEqual(sorted(result), ["anthropic", "openai"])
        self.assertNotIn("remote-config-canary", json.dumps(result))

    def test_rejects_duplicate_keys_before_decoding(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            helper.filter_auth('{"openai":{"type":"api","key":"one"},"openai":{"type":"api","key":"two"}}')

    def test_diagnostics_never_echo_secrets(self):
        canary = "credential-must-never-escape"
        with self.assertRaises(ValueError) as caught:
            helper.filter_auth(json.dumps({"openai": {"type": "api", "key": canary, "extra": canary}}))
        self.assertNotIn(canary, str(caught.exception))
```

Add profile tests that assert the exact generated tree, directory modes 0700, file modes 0600, broad-to-specific instruction ordering, inode-based deduplication, absent optional instructions, UTF-8 and NUL rejection, 256 KiB per-source limit, 512 KiB combined limit, and atomic directory publication.
Assert exact instruction bytes using `# User instructions\n\n` and `# Repository instructions\n\n` headings, the deterministic separator rule below, exact accepted source bytes, and an empty file when neither source exists.
Add race fixtures that replace a source with a symlink between `lstat`, `open`, `fstat`, read, and final `lstat`, and require refusal at every boundary.
Add output-boundary cases for a symlinked, wrong-owner, wrong-mode, or wrong-kind backend state, its trusted parent, and the `profiles` directory, plus staging or destination replacement after descriptor-bound identity capture and before publication.
Prepare two profiles with distinct supplied tokens and changed credential bytes while leaving configuration and instructions fixed, then assert distinct roots, changed filtered authentication, identical fingerprints, and no credential value in either report.
Add `inspect-profile` tests that re-open a published generation and reject a changed token, identity, root, version, fingerprint, configuration hash, instruction hash, owner, mode, or symlink component without returning file contents.

- [ ] **Step 2: Run the Python test and verify the helper is absent**

Run:

```sh
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_opencode_profile.py
```

Expected: exit nonzero because `.config/nvim/scripts/nvim-ai-opencode-profile.py` does not exist.

- [ ] **Step 3: Implement strict JSON and source readers**

Create `.config/nvim/scripts/nvim-ai-opencode-profile.py` with only these imports:

```python
import argparse
import ctypes
import hashlib
import json
import os
import pathlib
import stat
import sys
```

Decode JSON with an `object_pairs_hook` that rejects duplicate keys at every nesting level.
Require the exact request keys for each operation and reject unknown or missing fields before accessing the filesystem.
Reject non-object roots, more than 128 providers, provider identifiers outside 1 to 256 UTF-8 bytes, controls, identifiers that collide after trailing-slash removal, unknown record types other than excluded `wellknown`, and unknown fields in accepted records.
Require exact `api` fields `type`, `key`, and optional `metadata`.
Require exact `oauth` fields `type`, `refresh`, `access`, `expires`, and optional `accountId` and `enterpriseUrl`.
Require a nonnegative integer `expires`, credential strings at most 256 KiB, metadata maps at most 128 entries, metadata keys and values at most 8 KiB, and generated authentication JSON at most 1 MiB.

Implement source reads with `os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)`, `os.fstat`, bounded reads, a second `os.fstat`, close, and final `os.lstat` identity comparison.
Require the authentication file to be current-user-owned mode 0600.
Treat a missing authentication file as unauthenticated, but reject every other open or metadata failure.
Require instruction files to be current-user-owned regular nonsymlinks without group or other write bits.
Return `unauthenticated` without publishing a profile when no accepted record remains.
Normalize provider identifiers by removing trailing slashes, sort them by UTF-8 byte order, encode accepted records with fixed field order and compact UTF-8 JSON plus one final line feed, and sort optional metadata keys by UTF-8 byte order.
Require `config_json` and `policy_json` to equal the audited canonical byte strings and require the decoded policy inside the configuration to equal the separately supplied policy.

- [ ] **Step 4: Implement deterministic profile construction and atomic publication**

Publish this exact tree beneath `BACKEND_STATE/profiles/TOKEN`:

```text
profiles/TOKEN/
├── credentials/
│   └── auth.json
├── empty-home-opencode/
├── manifest.json
└── xdg-config/
    └── opencode/
        ├── AGENTS.md
        └── opencode.json
```

Build it first as the mode-0700 sibling `dirname(BACKEND_STATE)/.opencode-profile-TOKEN.tmp`, outside the exact backend-state child made writable inside backend sandboxes.
Require the canonical backend-state parent to be a current-user-owned mode-0700 nonsymlink directory and require it to share one filesystem with `BACKEND_STATE/profiles`.
Retain descriptor-bound identities for that trusted parent, the staging generation, the backend state, and the profiles directory through publication.
Use exclusive file creation, complete write loops, `fsync` on every file, and `fsync` on every directory from leaves to `profiles`.
Publish `TOKEN` from the trusted sibling parent into `BACKEND_STATE/profiles` with one final Linux `renameat2(RENAME_NOREPLACE)` call through `ctypes`, fail closed when that primitive is unavailable, and never fall back to replacement-capable `os.rename`.
Refuse an existing staging or destination path instead of replacing it.
On failure, remove only entries proven to be children of the helper-created staging directory and leave every pre-existing path untouched.
Reject any unexpected entry when inspecting a published profile and require `empty-home-opencode` to remain empty.
Build the instruction snapshot by considering the user file first and repository file second, deduplicating the second only when its stable device and inode equal the first.
For each present source, append its fixed heading and exact accepted source bytes, append one line feed when those bytes do not already end in one, then append one separator line feed.
When neither source exists, write an empty `AGENTS.md`.

Compute the profile fingerprint as lowercase SHA-256 over this sequence, encoding every component as an unsigned 64-bit big-endian byte length followed by the component bytes:

```text
schema byte "1"
version UTF-8 bytes
identity key ASCII bytes
canonical root UTF-8 bytes
canonical configuration bytes
instruction snapshot bytes
```

Do not include authentication bytes, authentication metadata, source paths, or the generation token in the fingerprint.
Write `manifest.json` as compact UTF-8 JSON with one final line feed and exact ordered keys `schema`, `version`, `identity_key`, `root`, `fingerprint`, `config_sha256`, and `instructions_sha256`.

Return this exact secret-free report:

```json
{
  "schema": 1,
  "version": "1.18.18",
  "profile_root": "/state/identity/backends/opencode/profiles/TOKEN",
  "fingerprint": "64-lowercase-hex",
  "config_source": "/state/identity/backends/opencode/profiles/TOKEN/xdg-config",
  "auth_source": "/state/identity/backends/opencode/profiles/TOKEN/credentials/auth.json",
  "home_mask_source": "/state/identity/backends/opencode/profiles/TOKEN/empty-home-opencode",
  "auth": "authenticated",
  "credential_count": 2
}
```

The CLI must read at most 1 MiB from stdin, use `--operation prepare|inspect-auth|inspect-profile`, print only the encoded report, and return a bounded generic error on stderr with exit `2` for validation failures.
`inspect-profile` must securely re-open the exact immutable generation below `BACKEND_STATE/profiles/TOKEN`, repeat the ownership, mode, no-symlink, bounded-read, canonical-JSON, accepted-credential, hash, and fingerprint checks, and return the same secret-free public report without reading any source outside that generation.

- [ ] **Step 5: Run Python static and unit checks**

Run:

```sh
python3 -I -B -c 'import ast,pathlib; ast.parse(pathlib.Path("/home/ruohao/.config/nvim/scripts/nvim-ai-opencode-profile.py").read_text(encoding="utf-8"))'
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_opencode_profile.py
```

Expected: parsing exits `0`, and the test suite reports `OK` with no canary credential in stdout or stderr.

- [ ] **Step 6: Commit the profile materializer**

```sh
git add .config/nvim/scripts/nvim-ai-opencode-profile.py \
  .config/nvim/tests/nvim_ai_opencode_profile.py
git commit -m "feat(nvim): build private OpenCode profiles"
```

### Task 3: Wire managed profiles and exact compatibility into Task 2

**Files:**

- Modify: `.config/nvim/lua/ai/backends/init.lua`
- Modify: `.config/nvim/lua/ai/backends/opencode.lua`
- Modify: `.config/nvim/lua/ai/backends/opencode_managed.lua`
- Modify: `.config/nvim/tests/ai_backends.lua`
- Modify: `.config/nvim/tests/ai_opencode_managed.lua`

**Interfaces:**

- Consumes: `deps.prepare_opencode_profile(request) -> AiOpenCodeManagedProfile|nil, string|nil`.
- Consumes: `deps.inspect_opencode_auth(path) -> "authenticated"|"unauthenticated"|"unknown", string|nil`.
- Consumes: `deps.opencode_compatibility(executable) -> report|nil, string|nil`.
- Consumes: `deps.inspect_opencode_profile(request) -> AiOpenCodeManagedProfile|nil, string|nil`.
- Produces: OpenCode `AiBackendLaunch.managed_profile = AiOpenCodeManagedProfile`.
- Produces: `adapter:profile_reference(launch) -> { token, fingerprint, version }|nil, string|nil`.
- Produces: `adapter:validate_profile(reference, identity, paths) -> AiOpenCodeManagedProfile|nil, string|nil`.
- Produces: OpenCode health only when the exact version, help, semantic report, and filtered authentication all pass.

- [ ] **Step 1: Extend failing adapter tests with the exact launch shape**

Inject one prepared profile report and assert these exact OpenCode values:

```lua
eq(opencode_launch.server_argv, {
  "/usr/bin/opencode", "--pure", "serve", "--hostname", "127.0.0.1", "--port", "43123",
}, "managed OpenCode server")
eq(opencode_launch.attach_argv, {
  "/usr/bin/opencode", "--pure", "attach", "http://127.0.0.1:43123", "--dir", "/work/repo",
}, "managed OpenCode attach")
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
}, "exact managed OpenCode environment")
eq(opencode_launch.read_only_inputs, {}, "raw global OpenCode inputs excluded")
eq(opencode_launch.protected_paths, {
  "/state/identity/backends/opencode/profiles/" .. string.rep("b", 32),
  "/usr/bin/opencode",
}, "managed profile and executable protected")
eq(opencode_launch.managed_profile.fingerprint, string.rep("c", 64), "profile fingerprint")

local resume_paths = vim.deepcopy(paths)
resume_paths.opencode_profile = {
  token = string.rep("b", 32),
  fingerprint = string.rep("c", 64),
  version = "1.18.18",
}
local opencode_resume = assert(opencode:resume_session(identity, resume_paths, "ses_test123"))
eq(opencode_resume.attach_argv, {
  "/usr/bin/opencode", "--pure", "attach", "http://127.0.0.1:43123",
  "--dir", "/work/repo", "--session", "ses_test123",
}, "managed OpenCode exact resume")
eq(opencode_resume.managed_profile.profile_root, opencode_launch.managed_profile.profile_root, "resume reuses profile")
```

Assert that neither launch construction nor health invokes `opencode auth list`.
Assert that the helper receives only the approved global `auth.json`, `$HOME/AGENTS.md`, physical-root `AGENTS.md`, fixed configuration, version, identity, state, and random token fields.
Assert that an unauthenticated helper result, helper exception, unknown version, malformed agent JSON, missing `--pure`, or secret-bearing helper diagnostic disables OpenCode with a bounded generic error.
Assert that `profile_reference()` returns only token, fingerprint, and version and that `validate_profile()` refuses every mismatch between its input reference, identity, backend state, and the helper's `inspect-profile` result.
Assert that an already-active OpenCode relaunch reuses its successfully inspected profile without invoking `prepare`, while a first activation prepares a fresh profile and any invalid supplied reference fails without fresh-profile fallback.

- [ ] **Step 2: Run both Lua tests and verify the old adapter fails**

Run:

```sh
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_backends.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_opencode_managed.lua
```

Expected: at least one assertion fails because the current adapter still mounts global configuration data and lacks managed-profile fields.

- [ ] **Step 3: Add isolated OpenCode probe execution**

Extend `read_only_probe()` with an optional exact environment and working directory.
For ordinary backend probes, retain the current safe local behavior.
For OpenCode semantic probes, start from an empty environment and pass only `HOME`, the four XDG variables, `OPENCODE_PERMISSION`, `OPENCODE_CONFIG_CONTENT` containing `managed.config_json()`, and these exact fixed controls:

```lua
{
  OPENCODE_DISABLE_AUTOUPDATE = "true",
  OPENCODE_DISABLE_CLAUDE_CODE = "true",
  OPENCODE_DISABLE_EXTERNAL_SKILLS = "true",
  OPENCODE_DISABLE_LSP_DOWNLOAD = "true",
  OPENCODE_DISABLE_PROJECT_CONFIG = "true",
  OPENCODE_PURE = "true",
}
```
Create one current-user-owned mode-0700 empty probe home and one empty probe XDG configuration tree.
Mount both read-only at fixed `/probe` paths, put only XDG data, cache, and state beneath private `/tmp`, and run every probe through validated Bubblewrap with `--unshare-net`, a read-only `/`, no tmux or Neovim variables, and a two-second timeout per command.
Reject any probe log or filesystem evidence of configuration dependency installation, plugin loading, update, LSP download, or network setup.

Collect these commands:

```lua
{
  version = { executable, "--version" },
  root_help = { executable, "--help" },
  serve_help = { executable, "serve", "--help" },
  attach_help = { executable, "attach", "--help" },
  names = { executable, "--pure", "agent", "list" },
  build = { executable, "--pure", "debug", "agent", "build" },
  plan = { executable, "--pure", "debug", "agent", "plan" },
  compaction = { executable, "--pure", "debug", "agent", "compaction" },
  summary = { executable, "--pure", "debug", "agent", "summary" },
  title = { executable, "--pure", "debug", "agent", "title" },
  general = { executable, "--pure", "debug", "agent", "general" },
  explore = { executable, "--pure", "debug", "agent", "explore" },
}
```

Parse JSON only from stdout for the five expected `debug agent` commands.
Require the version probe to exit `0` and contain exactly `1.18.18` followed by at most one line feed, with no prefix, suffix, prerelease, or build metadata.
Require `general` and `explore` to exit nonzero with the bounded exact `Agent NAME not found` category, not arbitrary failure text.
Parse only top-level `NAME (MODE)` headers from `agent list`, sort them, and require the exact five-name set.
Never place raw probe output into the returned health error.
Cache only a fully successful sanitized compatibility report, keyed by the canonical executable path and its revalidated stable metadata.
Invalidate the cache on any metadata change and never cache authentication state, instruction sources, credentials, or managed-profile validation.

- [ ] **Step 4: Invoke the profile helper with a clear environment**

Resolve and revalidate canonical Python and helper paths before every invocation.
Invoke this exact argv array with the canonical request JSON on stdin:

```lua
{
  paths.python,
  "-I",
  "-B",
  paths.profile_helper,
  "--operation",
  "prepare",
}
```

Use `clear_env=true`, `text=true`, `timeout=5000`, and an environment containing only `LANG=C.UTF-8`.
Require exit `0`, stdout at most 64 KiB, empty stderr, exact report keys, canonical descendant paths, matching version, matching token component, and a 64-character lowercase hexadecimal fingerprint.
On failure, accept only a bounded generic stderr category and never forward raw output.
Tests must place a canary in synthetic credentials and fail if any helper or adapter stdout, stderr, or diagnostic contains it.
Use the same isolated invocation boundary with `--operation inspect-profile` for adapter profile revalidation, but pass only the exact nonsecret reference, identity, root, version, and backend-state fields.

- [ ] **Step 5: Replace the OpenCode adapter launch construction**

Delete the old wildcard permission constant, all global OpenCode configuration handling, and the `account.json` and `mcp-auth.json` mounts.
Require `paths.home_agents` to be the fixed `AGENTS.md` child of the canonical current-user-owned inherited home and require `paths.global_opencode_data` to come from the original user XDG data root or its standard home fallback.
Make a first OpenCode activation prepare a fresh managed profile and return it as `managed_profile`.
When `paths.opencode_profile` is present for a coordinator-driven relaunch of the already-active OpenCode pane, securely inspect and reuse that exact generation instead of resnapshotting credentials or instructions.
When the supplied reference is invalid, fail closed without preparing a replacement.
When no reference is supplied for a new activation or an explicit close-and-reopen, prepare a fresh generation.
Build environment values only through `managed.environment(profile, password)`.
Protect only the canonical executable and exact generated profile root.
Admit `paths.opencode_profile` only for the OpenCode adapter, reject it for Codex and Claude, and strip helper-only `auth` and `credential_count` fields before constructing the exact seven-field launch profile.
Keep exact session validation and event capabilities unchanged.

Change `adapter:health()` to require, in order, executable validation, exact version compatibility, semantic compatibility, and filtered authentication inspection.
Return `installed=true`, empty capabilities, and a bounded incompatibility error whenever any required managed control fails.

- [ ] **Step 6: Run Task 1, Task 2, formatting, and backend regressions**

Run:

```sh
stylua /home/ruohao/.config/nvim/lua/ai/backends \
  /home/ruohao/.config/nvim/tests/ai_backends.lua \
  /home/ruohao/.config/nvim/tests/ai_opencode_managed.lua
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_opencode_profile.py
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_opencode_managed.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_backends.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_identity.lua
git diff --check
```

Expected: every command exits `0`, the focused tests print their exact success lines, Python reports `OK`, and `git diff --check` is silent.

- [ ] **Step 7: Commit the repaired Task 2 boundary**

```sh
git add .config/nvim/lua/ai/backends/init.lua \
  .config/nvim/lua/ai/backends/opencode.lua \
  .config/nvim/lua/ai/backends/opencode_managed.lua \
  .config/nvim/tests/ai_backends.lua \
  .config/nvim/tests/ai_opencode_managed.lua
git commit -m "fix(nvim): enforce managed OpenCode profiles"
```

Freeze this commit for a fresh specification review against both approved OpenCode design files and a separate quality review before beginning Task 4.

### Task 4: Enforce the managed profile in the Bubblewrap launcher

**Files:**

- Create: `.config/nvim/lua/ai/sandbox.lua`
- Create: `.config/nvim/scripts/nvim-ai-launch.py`
- Create: `.config/nvim/tests/ai_sandbox.lua`
- Create: `.config/nvim/tests/nvim_ai_launch.py`
- Create: `.config/nvim/tests/nvim-ai-sandbox.sh`

**Base boundary:**

These files are absent at the starting commit.
Implement every nonconflicting requirement and failing fixture from Task 3, `Build and prove the Bubblewrap launch boundary`, in `.config/docs/superpowers/plans/2026-08-23-neovim-native-ai-cli-companion.md` as the base of this task.
Replace only its historical OpenCode input mounts, OpenCode environment allowlist, and OpenCode fixture with the managed-profile requirements below.
The resulting commit must satisfy the complete base confinement contract and the managed OpenCode additions together.

**Interfaces:**

- Consumes: `AiBackendLaunch.managed_profile` only when `backend == "opencode"`.
- Produces: strict nested manifest object `launch.managed_profile` with no credential contents.
- Produces: identical validated environment and managed mounts for OpenCode server and attach Bubblewrap children.
- Preserves: every existing Task 3 root, grant, Git, tmux, helper, context, and backend-state invariant.

- [ ] **Step 1: Add failing Lua and Python manifest assertions**

Create the base Lua, Python, and shell fixtures from the main plan's Task 3 test steps, replacing every historical OpenCode fixture with this exact managed profile shape:

```python
"managed_profile": {
    "schema": 1,
    "version": "1.18.18",
    "profile_root": "/state/ai/backend/profiles/" + "b" * 32,
    "fingerprint": "c" * 64,
    "config_source": "/state/ai/backend/profiles/" + "b" * 32 + "/xdg-config",
    "auth_source": "/state/ai/backend/profiles/" + "b" * 32 + "/credentials/auth.json",
    "home_mask_source": "/state/ai/backend/profiles/" + "b" * 32 + "/empty-home-opencode",
},
```

Assert that Codex and Claude reject a non-null managed profile.
Assert that OpenCode rejects a null profile, changed version, wrong fingerprint, path outside `backend_state_dir`, symlink component, wrong mode, wrong owner, changed manifest hash, noncanonical configuration JSON, and authentication output with zero accepted credentials.
Assert rejection of an extra profile entry, nonempty home mask, pre-existing isolated `account.json` or `mcp-auth.json`, noncanonical or wrong-owner inherited home, and host-home destination mutation.
Assert that mutating any managed environment value or adding any inherited or adapter `OPENCODE_*` key fails environment construction.

- [ ] **Step 2: Run focused tests and verify the base launcher is missing**

Run:

```sh
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_sandbox.lua
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_launch.py
```

Expected: the Lua test fails because `ai.sandbox` is missing and the Python test fails because `nvim-ai-launch.py` is missing.

- [ ] **Step 3: Extend strict Lua manifest publication**

Implement the main plan's complete strict Lua manifest publication contract, then require `managed_profile` to be absent for direct backends and present for OpenCode `server_attach` launches.
Copy only its exact seven public fields into the mode-0600 launch manifest.
Resolve and protect the canonical profile helper path alongside the launcher, review helper, control helper, and event helper.
Reject a profile root outside `backend_state_dir/profiles`, a token component outside 32 lowercase hexadecimal characters, and source paths outside that exact profile root.

- [ ] **Step 4: Independently revalidate profile contents in Python**

Implement the main plan's complete Python manifest, path, ownership, Git, grant, helper, control, event, and environment validation contract first.
Before building Bubblewrap argv, additionally open and validate every component from the canonical backend-state directory through the profile root without following symlinks.
Require inherited `HOME` to be an absolute canonical current-user-owned directory before constructing the `.opencode` mask destination.
Require every directory in that private subtree to be current-user-owned mode 0700 and every profile file to be current-user-owned mode 0600.
Require the exact published tree and an empty `empty-home-opencode` directory, with no extra entry at any level.
Read at most 1 MiB from `manifest.json`, `xdg-config/opencode/opencode.json`, `xdg-config/opencode/AGENTS.md`, and `credentials/auth.json` through descriptor-stable bounded reads.
Recompute the configuration hash, instruction hash, and public fingerprint from the manifest values and reject every mismatch.
Strictly decode configuration and authentication JSON with duplicate-key rejection.
Require the exact configuration object and at least one accepted `api` or `oauth` credential.
Before either child starts, require the isolated `$XDG_DATA_HOME/opencode/account.json` and `$XDG_DATA_HOME/opencode/mcp-auth.json` destinations to be absent and refuse a wrong-kind, symlink, or existing file instead of consuming it.
Never place decoded credential values in an exception.

- [ ] **Step 5: Apply exact environment validation and mount order**

Implement the main plan's complete Bubblewrap construction and base parent-environment allowlist, then extend the adapter environment allowlist with exactly these keys:

```python
OPENCODE_KEYS = {
    "OPENCODE_DISABLE_AUTOUPDATE",
    "OPENCODE_DISABLE_CLAUDE_CODE",
    "OPENCODE_DISABLE_EXTERNAL_SKILLS",
    "OPENCODE_DISABLE_LSP_DOWNLOAD",
    "OPENCODE_DISABLE_PROJECT_CONFIG",
    "OPENCODE_PERMISSION",
    "OPENCODE_PURE",
    "OPENCODE_SERVER_PASSWORD",
    "OPENCODE_SERVER_USERNAME",
    "XDG_CACHE_HOME",
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
    "XDG_STATE_HOME",
}
```

Require every boolean control to equal `true`, username to equal `opencode`, permission to equal the canonical policy JSON, password to match 32 lowercase hexadecimal characters, and every XDG path to be its exact canonical backend-state destination.
Reject any inherited or adapter-provided `OPENCODE_*` key outside the exact set instead of silently dropping it.

After the writable backend-state bind, append these nested read-only overlays in this order:

```python
argv += ["--ro-bind", os.path.dirname(profile["profile_root"]), os.path.dirname(profile["profile_root"])]
argv += ["--ro-bind", profile["profile_root"], profile["profile_root"]]
argv += ["--ro-bind", profile["config_source"], env["XDG_CONFIG_HOME"]]
argv += ["--ro-bind", profile["auth_source"], env["XDG_DATA_HOME"] + "/opencode/auth.json"]
argv += ["--ro-bind", profile["home_mask_source"], os.path.join(parent_env["HOME"], ".opencode")]
```

Create missing mount destinations only inside the Bubblewrap namespace, never in the inherited home, and refuse existing destination symlinks or wrong-kind objects.
Apply existing Git, tmux, context, runtime, and helper masks after any project or grant bind.
Use the same validated environment and managed profile for the server and attach children.

- [ ] **Step 6: Extend the real Bubblewrap filesystem harness**

Create the full provider-free Bubblewrap harness from the main plan's Task 3 Step 6 and add a synthetic managed profile under its harness-owned backend state.
Make the fake backend attempt to replace `opencode.json`, `AGENTS.md`, filtered `auth.json`, the profile manifest, and a file below the home `.opencode` mask.
Make it also attempt to create, rename, and remove entries in the complete `profiles` directory and in the sibling unpublished-generation namespace beneath the identity-specific `backends` parent.
Require every attempt to fail while backend cache writes and the existing project/grant policy behave exactly as before.
Pass the expected profile manifest path as fixed fake-backend argv and assert that the fake server and attach modes read the same fingerprint without exposing credential contents.

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

Expected: every static check exits `0`, Lua prints its exact success line, Python reports `OK`, and the shell harness prints its exact success line.
Verify that no Python `__pycache__` exists or is staged.

- [ ] **Step 8: Commit launcher enforcement**

```sh
git add .config/nvim/lua/ai/sandbox.lua \
  .config/nvim/scripts/nvim-ai-launch.py \
  .config/nvim/tests/ai_sandbox.lua \
  .config/nvim/tests/nvim_ai_launch.py \
  .config/nvim/tests/nvim-ai-sandbox.sh
git commit -m "feat(nvim): confine managed OpenCode profiles"
```

### Task 5: Prove hostile configuration isolation end to end

**Files:**

- Create: `.config/nvim/tests/nvim-ai-opencode-compat.sh`
- Modify: `.config/nvim/tests/ai_opencode_managed.lua`
- Modify: `.config/nvim/tests/nvim_ai_opencode_profile.py`
- Modify: `.config/nvim/tests/nvim_ai_launch.py`

**Interfaces:**

- Consumes: installed canonical OpenCode and requires exact version `1.18.18` for real-binary assertions.
- Produces: no provider request, no live-auth access, no persistent OpenCode state, and one exact success line.
- Proves: managed configuration, native Build and Plan behavior, subagent removal, hidden-agent safety, credentials-only transfer, and exact instruction snapshots with the real audited binary.

- [ ] **Step 1: Write the failing hostile-fixture harness**

Create one mode-0700 harness root with these sources:

```text
host-home/.config/opencode/opencode.json
host-home/.config/opencode/AGENTS.md
host-home/.config/opencode/agents/hostile.md
host-home/.config/opencode/commands/hostile.md
host-home/.config/opencode/plugins/hostile.js
host-home/.config/opencode/skills/hostile/SKILL.md
host-home/.opencode/agents/hostile.md
host-home/.opencode/commands/hostile.md
host-home/.opencode/plugins/hostile.js
host-home/.opencode/skills/hostile/SKILL.md
host-home/.claude/CLAUDE.md
host-home/.claude/skills/hostile/SKILL.md
host-home/.agents/skills/hostile/SKILL.md
host-home/AGENTS.md
host-home/.local/share/opencode/auth.json
host-home/.local/share/opencode/account.json
host-home/.local/share/opencode/mcp-auth.json
project/opencode.json
project/.opencode/agents/hostile.md
project/.opencode/commands/hostile.md
project/.opencode/plugins/hostile.js
project/.opencode/skills/hostile/SKILL.md
project/AGENTS.md
project/nested/AGENTS.md
project/CLAUDE.md
project/CONTEXT.md
```

Make both hostile JSON configurations set wildcard allow, shell allow, web allow, external-directory allow, `task=allow`, `skill=allow`, custom Build and Plan permissions, a custom primary agent, plugins, MCP, remote instructions, and provider configuration.
Put approved broad guidance in `host-home/AGENTS.md` and approved repository guidance in `project/AGENTS.md`.
Make `account.json`, `mcp-auth.json`, the `wellknown` auth record, and every disallowed file contain a unique canary string.
Use only synthetic `api` and `oauth` credentials for the two accepted records.

- [ ] **Step 2: Prepare a real managed profile and run OpenCode without network**

Invoke the profile helper with the harness paths and capture its secret-free report.
Start each OpenCode inspection command through validated Bubblewrap with a read-only `/`, private `/tmp`, `--unshare-net`, project cwd, writable isolated data/cache/state, read-only managed configuration, read-only filtered authentication, and the empty home `.opencode` mask.
Run `debug config`, `agent list`, and `debug agent` for `build`, `plan`, `compaction`, `summary`, and `title`.
Run `debug agent general` and `debug agent explore` and require the bounded not-found category.
Do not invoke `run`, the default TUI, a provider command, or any session operation.

- [ ] **Step 3: Assert the complete effective boundary**

Require exact five-agent enumeration.
Require native Build and Plan names, descriptions, modes, and native markers.
Resolve the ordered permission rules for `src/nvim_ai_probe.lua` and assert Build edit allow, Plan edit deny, five risk approvals, and task/skill denial.
Require all actionable hidden-agent tools false.
Require the resolved managed configuration sections to equal the canonical policy and agent entries and contain none of the hostile canaries, plugins, MCP definitions, provider settings, remote instruction fields, custom defaults, or custom agents.
Require the combined `AGENTS.md` to contain exact user guidance before exact repository guidance and none of the disallowed `CLAUDE.md`, `CONTEXT.md`, remote-URL, nested-instruction, global-config, `.opencode`, `.claude`, or `.agents` canaries.
Require filtered `auth.json` to contain only the two accepted synthetic records.
Require `account.json` and `mcp-auth.json` destinations to be absent.
Require the complete isolated XDG configuration tree to reject writes, not only its `opencode` child.
Hash the complete managed configuration tree before and after every command and require equality.
Run with debug logs and reject `Npm.reify`, `npm-install`, `background dependency install failed`, external plugin load, and download markers.

- [ ] **Step 4: Run the new harness and all focused regressions**

Run:

```sh
chmod 700 /home/ruohao/.config/nvim/tests/nvim-ai-opencode-compat.sh
shellcheck /home/ruohao/.config/nvim/tests/nvim-ai-opencode-compat.sh
bash /home/ruohao/.config/nvim/tests/nvim-ai-opencode-compat.sh
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_opencode_profile.py
python3 -I -B /home/ruohao/.config/nvim/tests/nvim_ai_launch.py
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_opencode_managed.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_backends.lua
NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  -c 'set runtimepath^=/home/ruohao/.config/nvim' \
  -l /home/ruohao/.config/nvim/tests/ai_identity.lua
bash /home/ruohao/.config/nvim/tests/nvim-ai-sandbox.sh
git diff --check
```

Expected: shellcheck exits `0`, the OpenCode harness prints exactly `Managed OpenCode compatibility assertions: ok`, every focused suite passes, and no output contains a credential or hostile canary.

- [ ] **Step 5: Commit end-to-end compatibility coverage**

```sh
git add .config/nvim/tests/nvim-ai-opencode-compat.sh \
  .config/nvim/tests/ai_opencode_managed.lua \
  .config/nvim/tests/nvim_ai_opencode_profile.py \
  .config/nvim/tests/nvim_ai_launch.py
git commit -m "test(nvim): prove managed OpenCode isolation"
```

Freeze the completed managed OpenCode and Task 3 boundary for fresh specification and quality reviews.
After both reviews pass, resume `.config/docs/superpowers/plans/2026-08-23-neovim-native-ai-cli-companion.md` at Task 4.

---

## Completion Gate

The repair plan is complete only when all five task commits are present, all five task-level specification and quality review pairs pass, every listed command succeeds, and the worktree is clean.
The returned token, fingerprint, and version reference must remain available for the main plan's transport and session-coordinator reopen checks.
Do not begin the main plan's Task 4 while any managed OpenCode or launcher finding remains open.
