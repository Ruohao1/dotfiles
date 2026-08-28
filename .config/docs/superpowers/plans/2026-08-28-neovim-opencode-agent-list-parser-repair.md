# Neovim OpenCode Agent-List Parser Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the managed OpenCode `1.18.18` names parser so it accepts one structurally valid permission JSON array after every exact agent header while retaining only sanitized names.

**Architecture:** Keep the existing twelve-command asynchronous controller and sanitized compatibility report unchanged.
Replace only the private names parser with a grammar-aware header-and-JSON scanner, update its deterministic fixture to match the installed CLI, and preserve the detailed `debug agent` probes as the sole semantic permission authority.

**Tech Stack:** Neovim Lua, `vim.json`, `vim.islist`, Stylua, Lua compiler syntax checks, Python `unittest`, ShellCheck, Bash, Bubblewrap, Git, and Linear Coordination Contract v2.

## Global Constraints

- Work only in `/tmp/dotfiles-nvim-ai-cli-companion` on branch `agent/nvim-ai-cli-companion`.
- Begin from the committed design at `f8de3ef48d4f505db9bf17b85156412428af0d12` and the plan commit containing this document.
- Treat the six existing implementation paths as one frozen candidate set until an exact implementation lease names the two writable repair paths.
- The current six-path binary-diff SHA-256 before repair is `7f00ed5f44735c9458f19aaf488cd19bc96a3d09b9acbf2c66c68858932cf557`.
- The current production parser SHA-256 is `ff4f25ce92f391b87ec9f0cbe6be9073e2405c9e1617e9d7f72b8099cbe68140`.
- The current parser-test SHA-256 is `d57d32a7a259219e064727c9b222985eb205f34201be3864c27fc5420b160c32`.
- Do not change `.config/nvim/lua/ai/backends/init.lua`, `.config/nvim/lua/ai/backends/opencode.lua`, `.config/nvim/tests/ai_backends.lua`, or `.config/nvim/tests/ai_opencode_managed.lua` during the parser repair.
- Do not read, mutate, or delete `/tmp/nvim-ai-opencode-retention-939b6cab552b1091`, and treat its expected mode-0700 presence as distinct from any root created by a future candidate gate.
- Do not invoke OpenCode during implementation, deterministic testing, review, or static diagnosis.
- Do not run the consumed R5 or R9 managed-gate candidates again under any command spelling.
- Do not run hostile-HOME until one fresh reviewed candidate passes its own fresh managed gate and immediate audit.
- Do not contact a provider, use the network, start a default tmux server, write live home, inspect credentials, print raw probe output, or read retained database, log, configuration, stdout, or stderr bytes.
- Run every Neovim test with `NVIM_LOG_FILE=/dev/null`.
- Run every Lua compiler check with `-o /dev/null` so no `luac.out` can be created.
- Keep implementation bytes unstaged and uncommitted until both immutable reviews and both newly leased one-shot gates pass the same exact hashes.
- If any implementation byte changes after reviews begin, close those reviews, create a new candidate revision, and create fresh immutable review children.
- Use `apply_patch` for source edits, use Stylua only on the two authorized Lua paths, and never include an em dash or coauthor trailer.
- Run real gates serially, never concurrently, and never retry a failed one-shot gate automatically.
- Preserve the exact final success markers `AI OpenCode background validation assertions: ok`, `AI managed OpenCode assertions: ok`, and `Managed OpenCode compatibility assertions: ok`.

## File Structure

- Modify `.config/nvim/lua/ai/backends/opencode_validation.lua` only to add the fixed agent-list mode set, structurally decode one permission array per header, and return sorted unique names.
- Modify `.config/nvim/tests/ai_opencode_validation.lua` only to emit realistic pretty permission JSON, prove list permissions are structurally checked but semantically discarded, and cover malformed framing.
- Keep `.config/nvim/tests/ai_opencode_managed.lua` unchanged so the fresh real gate proves the repair through the existing production path rather than a repair-specific bypass.
- Keep the approved design and this plan committed before any implementation byte changes.

---

### Task 1: Build the realistic parser repair test first

**Files:**

- Modify: `.config/nvim/tests/ai_opencode_validation.lua:49-205`
- Modify: `.config/nvim/lua/ai/backends/opencode_validation.lua:15-112`

**Interfaces:**

- Consumes: `validation._test.parse_results(results)` and `validation._test.new_parser()` from the existing test-only boundary.
- Produces: A private `parse_names(result)` that returns one sorted string list on success and `nil` on every structural failure without exporting raw data.
- Produces: An unchanged public sanitized report containing names and the existing detailed-agent summaries.

- [ ] **Step 1: Acquire the exact implementation lease**

Move ISQ-46 to its implementation revision and grant one writer authority over only `.config/nvim/lua/ai/backends/opencode_validation.lua` and `.config/nvim/tests/ai_opencode_validation.lua`.
Record the current HEAD, tree, both writable-file hashes, four frozen-file hashes, six-path diff hash, empty index, expected preserved R9 root, and prohibition on OpenCode or real-gate execution.
Stop if the Linear readback differs from local state or another issue owns either writable path.

- [ ] **Step 2: Replace the names fixture with the installed `1.18.18` shape**

Insert these helpers immediately before `fixture_results()` in `.config/nvim/tests/ai_opencode_validation.lua`:

```lua
local function pretty_permission_json(rules)
  assert(type(rules) == "table" and vim.islist(rules), "permission fixture must be a list")
  if #rules == 0 then
    return "[]"
  end

  local lines = { "[" }
  for index, rule in ipairs(rules) do
    assert(type(rule) == "table", "permission fixture rule must be a table")
    assert(type(rule.permission) == "string", "permission fixture permission")
    assert(type(rule.pattern) == "string", "permission fixture pattern")
    assert(type(rule.action) == "string", "permission fixture action")
    lines[#lines + 1] = "  {"
    lines[#lines + 1] = string.format(
      '    "permission": %s,',
      vim.json.encode(rule.permission)
    )
    lines[#lines + 1] = string.format('    "pattern": %s,', vim.json.encode(rule.pattern))
    lines[#lines + 1] = string.format('    "action": %s', vim.json.encode(rule.action))
    lines[#lines + 1] = "  }" .. (index < #rules and "," or "")
  end
  lines[#lines + 1] = "]"
  return table.concat(lines, "\n")
end

local function agent_list_stdout(report)
  local entries = {
    { name = "build", mode = "primary" },
    { name = "compaction", mode = "subagent" },
    { name = "plan", mode = "primary" },
    { name = "summary", mode = "subagent" },
    { name = "title", mode = "subagent" },
  }
  local lines = {}
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = string.format("%s (%s)", entry.name, entry.mode)
    lines[#lines + 1] = pretty_permission_json(report.agents[entry.name].permission)
  end
  return table.concat(lines, "\n") .. "\n"
end
```

Replace the current `names` result inside `fixture_results()` with this exact block:

```lua
    names = {
      code = 0,
      signal = 0,
      stdout = agent_list_stdout(report),
      stderr = "",
    },
```

- [ ] **Step 3: Add positive structural and negative framing assertions**

Insert this block after the existing `test parser export uses the module-local parser` assertion:

```lua
local crlf_results, crlf_report = fixture_results()
crlf_results.names.stdout = crlf_results.names.stdout:gsub("\n", "\r\n")
local crlf_parsed, crlf_error = validation._test.parse_results(crlf_results)
assert(crlf_parsed, crlf_error)
eq(crlf_parsed, crlf_report, "CRLF agent list parses through the pinned grammar")

local ignored_list_permissions, ignored_list_report = fixture_results()
local replacement_count
ignored_list_permissions.names.stdout, replacement_count = ignored_list_permissions.names.stdout:gsub(
  '"action": "allow"',
  '"action": "deny"',
  1
)
eq(replacement_count, 1, "agent-list permission fixture changed exactly once")
local ignored_list_parsed, ignored_list_error = validation._test.parse_results(
  ignored_list_permissions
)
assert(ignored_list_parsed, ignored_list_error)
eq(
  ignored_list_parsed,
  ignored_list_report,
  "agent-list permissions are structural while debug-agent permissions remain semantic"
)

local function expect_names_parse_failure(label, stdout)
  local results = fixture_results()
  results.names.stdout = stdout
  local parser = validation._test.new_parser()
  for index = 1, 4 do
    local command = expected_commands[index]
    local accepted, category = parser:accept(command, results[command.name])
    assert(accepted, category)
  end

  local accepted, category = parser:accept(expected_commands[5], results.names)
  assert(accepted == nil, label .. " was accepted")
  eq(category, "parse-failure", label .. " category")
  assert(not category:find("secret-canary", 1, true), label .. " leaked canary bytes")
  eq(parser:debug_state(), {
    index = 4,
    version = true,
    name_count = 0,
    agent_count = 0,
    finished = false,
  }, label .. " retains no names or raw result")
end

expect_names_parse_failure("empty list", "")
expect_names_parse_failure("leading text", "secret-canary\nbuild (primary)\n[]\n")
expect_names_parse_failure("missing permission block", "build (primary)\nplan (primary)\n[]\n")
expect_names_parse_failure("malformed permission JSON", "build (primary)\n{secret-canary}\n")
expect_names_parse_failure("non-list permission JSON", "build (primary)\n{}\n")
expect_names_parse_failure("multiple permission values", "build (primary)\n[]\n[]\n")
expect_names_parse_failure(
  "duplicate agent header",
  "build (primary)\n[]\nbuild (primary)\n[]\n"
)
expect_names_parse_failure("unsupported agent mode", "build (future)\n[]\n")
expect_names_parse_failure("trailing text", "build (primary)\n[]\nsecret-canary\n")
expect_names_parse_failure(
  "raw header inside unfinished JSON",
  "build (primary)\n[\nplan (primary)\n[]\n"
)
expect_names_parse_failure("bare carriage return", "build (primary)\n[]\r")
expect_names_parse_failure("truncated final JSON", "build (primary)\n[\n{}\n")
```

- [ ] **Step 4: Run the realistic fixture to verify RED**

Run:

```bash
env NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exit nonzero with bounded `parse-failure` while processing the realistic names fixture, and no `AI OpenCode background validation assertions: ok` marker.
This command is provider-free and must not start OpenCode or Bubblewrap.

- [ ] **Step 5: Implement the strict header-and-JSON parser**

Insert this constant immediately after `AGENT_COMMANDS` in `.config/nvim/lua/ai/backends/opencode_validation.lua`:

```lua
local AGENT_LIST_MODES = {
  all = true,
  primary = true,
  subagent = true,
}
```

Replace the current `parse_names()` with these exact helpers and function:

```lua
local function valid_permission_json(lines)
  if type(lines) ~= "table" or #lines == 0 then
    return false
  end
  local encoded = table.concat(lines, "\n")
  local decoded_ok, decoded = pcall(vim.json.decode, encoded)
  encoded = nil
  if not decoded_ok or type(decoded) ~= "table" or not vim.islist(decoded) then
    return false
  end
  decoded = nil
  return true
end

local function parse_names(result)
  if result.code ~= 0 or result.stderr ~= "" or #result.stdout > MAX_HELP_BYTES then
    return nil
  end

  local output = result.stdout:gsub("\r\n", "\n")
  if output == "" or output:find("\r", 1, true) then
    return nil
  end
  if output:sub(-1) ~= "\n" then
    output = output .. "\n"
  end

  local names = {}
  local seen = {}
  local permission_lines
  local function finish_entry()
    if not valid_permission_json(permission_lines) then
      return false
    end
    permission_lines = nil
    return true
  end

  for line in output:gmatch("(.-)\n") do
    local name, mode = line:match("^([%w_-]+) %(([%w_-]+)%)$")
    if name then
      if not AGENT_LIST_MODES[mode] or seen[name] then
        return nil
      end
      if permission_lines and not finish_entry() then
        return nil
      end
      seen[name] = true
      names[#names + 1] = name
      permission_lines = {}
    else
      if not permission_lines then
        return nil
      end
      permission_lines[#permission_lines + 1] = line
    end
  end

  if not finish_entry() then
    return nil
  end
  output = nil
  table.sort(names)
  return names
end
```

Do not export either helper and do not add permission data to `parser:debug_state()` or the compatibility report.

- [ ] **Step 6: Run the focused suite to verify GREEN**

Run the same Neovim command from Step 4.

Expected: exit `0` with the exact final line `AI OpenCode background validation assertions: ok`.
Expected: no OpenCode, Bubblewrap, `nvim.log`, `luac.out`, or new `nvim-ai-opencode-*` root exists afterward.

- [ ] **Step 7: Format and parse-check only the two repair paths**

Run:

```bash
stylua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode_validation.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
luac -p -o /dev/null \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode_validation.lua
luac -p -o /dev/null \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --check
```

Expected: every command exits `0`, `diff --check` is silent, and only the two authorized hashes differ from the R9 candidate.

- [ ] **Step 8: Freeze the uncommitted parser-repair candidate**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion status --short --branch --untracked-files=all
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --cached --quiet
sha256sum \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/init.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/lua/ai/backends/opencode_validation.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_backends.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_managed.lua \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
```

Expected: exactly the existing four tracked implementation modifications and two untracked validation paths remain, the index is empty, the four frozen hashes still match R9, and the two repaired hashes are recorded as the new candidate.
Compute and record the canonical cumulative six-path binary-diff SHA-256 with the existing tracked-plus-no-index command used by ISQ-40.
Do not stage or commit implementation bytes yet because immutable reviews and one-shot gates must inspect these exact uncommitted hashes first.

### Task 2: Prove the complete provider-free regression envelope

**Files:**

- Verify: `.config/nvim/lua/ai/backends/opencode_validation.lua`
- Verify: `.config/nvim/tests/ai_opencode_validation.lua`
- Verify unchanged: the other four candidate paths and all launcher, profile, and sandbox harnesses.

**Interfaces:**

- Consumes: The frozen parser-repair hashes from Task 1.
- Produces: One provider-free evidence bundle with exact output markers, process audit, residue audit, and closing fingerprints.

- [ ] **Step 1: Run the three provider-free Neovim suites serially**

Run:

```bash
env NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_validation.lua
env NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_backends.lua
env NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_sandbox.lua
```

Expected: all three exit `0` with their existing exact final markers, and no installed AI CLI process starts.

- [ ] **Step 2: Run the profile and static shell checks**

Run:

```bash
python3 -I -B \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim_ai_opencode_profile.py
shellcheck \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-sandbox.sh
shellcheck \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-opencode-compat.sh
bash -n \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-sandbox.sh
bash -n \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-opencode-compat.sh
```

Expected: the Python suite reports 66 tests and `OK`, while ShellCheck and Bash syntax checks exit `0` silently.

- [ ] **Step 3: Run the two AF_UNIX provider-free host checks under one exact lease**

Record a Linear lease for coordinator execution of exactly these commands, permitting only fixture-owned temporary directories, AF_UNIX sockets, and short-lived local test processes.
Obtain host approval and run serially:

```bash
python3 -I -B \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim_ai_launch.py
bash \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-sandbox.sh
```

Expected: the launcher reports 78 tests and `OK`, and the harness prints exactly `ok - nvim AI Bubblewrap boundary`.
Stop after the first failure and do not continue to the second command or a real gate.

- [ ] **Step 4: Audit provider-free processes, residue, and fingerprints**

Verify no owned `opencode`, `bwrap`, `nvim`, test Python, or private tmux process remains.
Verify no `nvim-ai-launch-*`, `nvim-ai-sandbox.*`, `nvim.log`, `luac.out`, or index lock remains.
Verify the only pre-existing matching OpenCode root is `/tmp/nvim-ai-opencode-retention-939b6cab552b1091`, still a current-user-owned mode-0700 nonsymlink directory, without traversing or reading its contents.
Recompute all six hashes and the canonical cumulative diff hash and require exact equality with the Task 1 candidate.

- [ ] **Step 5: Update the implementation issue with the frozen candidate**

Record the new revision, exact six hashes, cumulative diff, HEAD, tree, status, empty index, every exact success marker, and the clean process and residue audit in ISQ-46.
Expire all writer and host-validation leases and move ISQ-46 to `In Review` before creating reviewer children.

### Task 3: Obtain two fresh immutable reviews

**Files:**

- Review: `.config/nvim/lua/ai/backends/init.lua`
- Review: `.config/nvim/lua/ai/backends/opencode.lua`
- Review: `.config/nvim/lua/ai/backends/opencode_validation.lua`
- Review: `.config/nvim/tests/ai_backends.lua`
- Review: `.config/nvim/tests/ai_opencode_managed.lua`
- Review: `.config/nvim/tests/ai_opencode_validation.lua`

**Interfaces:**

- Consumes: One frozen candidate revision and its provider-free evidence from Task 2.
- Produces: Two closed review children whose PASS verdicts name the same six hashes and cumulative diff.

- [ ] **Step 1: Create both review children in one coordination pass**

Create one `ISQRD-AGENT-REVIEW-v2` child for the specification lens and one for the quality lens, make each block ISQ-46, and include the exact candidate fingerprints in both descriptions.
Assign different reviewers and grant read-only authority over the design, plan, candidate, Linear hierarchy, metadata-only retained-root state, and provider-free in-memory checks.
Forbid repository mutation, repair, Git metadata, OpenCode invocation, real gates, hostile-HOME, provider access, network, live home, and retained-root content reads.

- [ ] **Step 2: Require the specification review to prove design coverage**

The reviewer must verify the exact header grammar, supported modes, one JSON array per header, complete decoder consumption, CRLF and bare-CR behavior, duplicate rejection, sorted sanitized names, discarded permissions, unchanged debug-agent semantic authority, unchanged compatibility report, no raw retention, and every design test case.
The reviewer must record PASS or CHANGES REQUESTED with complete evidence on its own child and set that assignment Done.

- [ ] **Step 3: Require the quality review to attack parser boundaries**

The reviewer must adversarially test missing blocks, invalid modes, malformed and truncated JSON, non-list roots, multiple values, forged headers, braces and header text inside JSON strings, empty arrays, blank JSON whitespace, duplicate names, output bounds, decoder exceptions, incremental-state sanitization, and exact failure ordering.
The reviewer must also confirm the other four candidate paths did not change, every deterministic marker is genuine, and the old R9 root remains untouched.
The reviewer must record PASS or CHANGES REQUESTED with complete evidence on its own child and set that assignment Done.

- [ ] **Step 4: Resolve findings without reusing reviews**

If either review requests changes, close both review assignments, move ISQ-46 to a new implementation revision with exact writer authority, add the smallest failing assertion first, repair only the two authorized paths, rerun Tasks 1 and 2, and create two new review children for the new hashes.
Do not edit a candidate while any review child for that candidate remains open.

- [ ] **Step 5: Read back both PASS verdicts and reopen coordinator execution**

Proceed only when both review issues are Done with `Verdict: PASS`, both name the exact same six hashes and cumulative diff, ISQ-46 is unchanged, the index is empty, and a closing read-only process and residue audit is clean.
No prior R9 review transfers to this repaired candidate.

### Task 4: Run one fresh managed gate for the repaired candidate

**Files:**

- Execute once: `.config/nvim/tests/ai_opencode_managed.lua`
- Inspect read-only: the six frozen candidate paths and exact process and residue state.

**Interfaces:**

- Consumes: The doubly reviewed parser-repair candidate from Task 3.
- Produces: One fresh managed-gate result and immediate bounded cleanup audit.

- [ ] **Step 1: Open one exact fresh managed-gate lease**

Update ISQ-46 to `In Progress` with coordinator `/root` as holder of one invocation of exactly this command:

```bash
env NVIM_LOG_FILE=/dev/null nvim --clean --headless -u NONE -i NONE \
  --cmd 'set runtimepath^=/tmp/dotfiles-nvim-ai-cli-companion/.config/nvim' \
  -l /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/ai_opencode_managed.lua
```

State explicitly that this is a fresh gate for the new repaired hashes, not a retry of R5 or R9.
Permit only this Neovim process, Bubblewrap, the installed OpenCode executable, and test-owned guarded temporary state.
Forbid network, providers, live home, default tmux, hostile-HOME, repository writes, Git metadata, and automatic retry.

- [ ] **Step 2: Perform the immediate preflight**

Read back the exact lease and both PASS reviews.
Reconfirm the branch, HEAD, tree, six hashes, cumulative diff, expected status, empty index, absent index lock, no active OpenCode, Bubblewrap, or Neovim process, and no unexpected new OpenCode root.
Expect the preserved R9 root to remain present and untouched.
Stop and expire the lease on any mismatch.

- [ ] **Step 3: Obtain host approval and run the command exactly once**

Expected: exit `0` within the existing outer 70-second bound with the exact final line `AI managed OpenCode assertions: ok`.
Do not run the command again under any spelling after either success or failure.
If it fails, prove every owned process is gone, preserve only the exact new guarded root named by the test, record bounded categories and timings, expire the lease, and stop before hostile-HOME.

- [ ] **Step 4: Audit immediately after the managed gate**

Verify no owned OpenCode, Bubblewrap, or Neovim process remains.
Verify every newly created successfully cleaned command root is absent and no `nvim.log`, `luac.out`, or index lock exists.
Verify the old preserved R9 root is unchanged and distinguish it from any root named by this fresh run.
Recompute every candidate fingerprint and stop on drift.
Only a clean success may open Task 5's separate lease.

### Task 5: Run the hostile-HOME harness under a separate lease

**Files:**

- Execute once: `.config/nvim/tests/nvim-ai-opencode-compat.sh`
- Inspect read-only: the six frozen candidate paths and exact process and residue state.

**Interfaces:**

- Consumes: A successful fresh managed gate and clean audit from Task 4.
- Produces: The final installed-OpenCode isolation proof for the same unchanged candidate.

- [ ] **Step 1: Open the hostile-HOME lease only after managed success**

Record one serial lease for coordinator `/root` to run ShellCheck and then invoke the existing harness once.
Permit only harness-owned temporary state, Bubblewrap, the installed OpenCode executable, and short-lived local test processes.
Forbid providers, network, live home, default tmux, repository writes, Git metadata, and automatic retry.

- [ ] **Step 2: Run the static check and harness serially**

Obtain host approval and run:

```bash
shellcheck \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-opencode-compat.sh
bash \
  /tmp/dotfiles-nvim-ai-cli-companion/.config/nvim/tests/nvim-ai-opencode-compat.sh
```

Expected: ShellCheck exits `0` silently and the harness exits `0` with exactly `Managed OpenCode compatibility assertions: ok`.
Do not invoke the harness a second time after either success or failure.

- [ ] **Step 3: Perform the final process and residue audit**

Verify no owned OpenCode, Bubblewrap, Neovim, Python, Bash, or private tmux process remains.
Verify no harness-owned temporary root, socket, log, compiler output, or index lock remains.
Verify the old preserved R9 root remains mode `0700`, current-user-owned, nonsymlink, and untouched without reading its contents.
Recompute all six hashes and the cumulative diff and require exact equality with both PASS reviews and the managed-gate record.

### Task 6: Commit the reviewed and proven candidate under an exact Git lease

**Files:**

- Commit: `.config/nvim/lua/ai/backends/init.lua`
- Commit: `.config/nvim/lua/ai/backends/opencode.lua`
- Commit: `.config/nvim/lua/ai/backends/opencode_validation.lua`
- Commit: `.config/nvim/tests/ai_backends.lua`
- Commit: `.config/nvim/tests/ai_opencode_managed.lua`
- Commit: `.config/nvim/tests/ai_opencode_validation.lua`

**Interfaces:**

- Consumes: The exact unchanged candidate approved by both reviews and proven by both fresh gates.
- Produces: One implementation commit, a clean worktree, and a Linear handoff that unblocks ISQ-40 and the main Neovim companion plan.

- [ ] **Step 1: Revalidate the complete coordination and local state**

Read the full active coordination contract, ISQ-22, ISQ-40, ISQ-46, both fresh review children, and all blocking relations.
Require both PASS verdicts, both gate success markers, clean audits, exact hashes, exact cumulative diff, correct branch and worktree, empty index, no active process, no unexpected residue, and no competing writer.
Stop on any mismatch rather than repairing under the Git lease.

- [ ] **Step 2: Acquire one exact Git-metadata lease**

Grant coordinator `/root` authority to stage and commit only the six reviewed paths at their approved hashes.
Forbid implementation edits, extra paths, amend, rebase, merge, reset, push, provider calls, live-home writes, retained-root mutation, and unrelated Git metadata.
Expire the lease on commit, failure, or any staged mismatch.

- [ ] **Step 3: Stage and inspect only the reviewed paths**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion add -- \
  .config/nvim/lua/ai/backends/init.lua \
  .config/nvim/lua/ai/backends/opencode.lua \
  .config/nvim/lua/ai/backends/opencode_validation.lua \
  .config/nvim/tests/ai_backends.lua \
  .config/nvim/tests/ai_opencode_managed.lua \
  .config/nvim/tests/ai_opencode_validation.lua
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --cached --name-status
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --cached --check
git -C /tmp/dotfiles-nvim-ai-cli-companion diff --cached --stat
```

Expected: exactly six paths are staged, every staged blob matches the approved hash, and the cached whitespace check is silent.

- [ ] **Step 4: Commit the exact candidate**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion commit \
  -m "fix(nvim): validate OpenCode in background"
```

Expected: one commit is created with the committed plan as its first parent, exactly the six reviewed paths, and no coauthor trailer.

- [ ] **Step 5: Verify the committed handoff**

Run:

```bash
git -C /tmp/dotfiles-nvim-ai-cli-companion status --short --branch --untracked-files=all
git -C /tmp/dotfiles-nvim-ai-cli-companion show --format=fuller --name-status --no-renames HEAD
git -C /tmp/dotfiles-nvim-ai-cli-companion diff HEAD^ HEAD --check
```

Expected: the worktree and index are clean, the commit contains exactly the six implementation paths, the commit diff is whitespace-clean, and the old preserved R9 root remains outside the repository and untouched.

- [ ] **Step 6: Close the repair and resume the parent workflow**

Record the implementation commit SHA, tree SHA, six committed blob hashes, all deterministic markers, both reviewer identities and PASS verdicts, both one-shot gate markers, and final audits in ISQ-46 and ISQ-40.
Set the completed review and implementation assignments Done only after readback confirms their durable evidence.
Resume the main Neovim companion plan at its next blocked task without deleting the preserved R9 audit root or changing live configuration.
