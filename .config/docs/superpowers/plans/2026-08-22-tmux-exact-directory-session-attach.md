# tmux Exact-Directory Session Attachment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `t` attach the unique existing tmux session rooted at the caller's exact physical current directory before applying its existing Git-root fallback.

**Architecture:** Extend the POSIX shell wrapper with a read-only discovery pass that normalizes the caller's directory and every existing `session_path` before comparison.
A focused end-to-end test will exercise unique reuse, precedence, outside-Git reuse, symbolic-link normalization, and duplicate rejection through a private tmux socket, while the existing Git naming and collision path remains unchanged.

**Tech Stack:** POSIX shell, tmux 3.7c, Git, ShellCheck, and the existing bare dotfiles Git repository.

## Global Constraints

- Run exact-directory discovery only after workspace restoration is ready and before Git repository discovery.

- Compare physical absolute directories derived with `cd -P` and `pwd -P`.

- Match tmux `session_path`, not an individual pane's current directory.

- Attach a unique match by exact session name and pass the normalized current directory to `tmux attach-session -c`.

- Reject multiple exact matches with a diagnostic that includes the directory and every matching session name.

- Treat an absent tmux server, no sessions, a disappeared session, or an inaccessible stale session path as no exact match.

- Preserve the existing Git-root naming, hash-based basename collision handling, create-race handling, native tmux fallback, inside-tmux rejection, argument rejection, and workspace readiness checks.

- Keep the implementation in POSIX shell and add no persistent registry or dependency.

- Exercise only the test-owned tmux socket beneath the guarded temporary directory and never address the user's normal tmux server.

- Preserve unrelated tracked and untracked user files and never add an agent co-author trailer.

---

## File Map

- Modify `.local/bin/t`.
  This executable owns current-directory normalization, session discovery, exact attachment, and the unchanged Git-root fallback.

- Modify `.config/tmux/tests/project-session.sh`.
  This executable owns isolated behavioral coverage through temporary repositories, a tmux command shim, and a private tmux socket.

- Read only `.config/docs/superpowers/specs/2026-08-22-tmux-exact-directory-session-attach-design.md`.
  This is the approved behavior contract.

- Read only `.config/dotfiles/check-terminal-stack`.
  This remains the final integration gate and does not need a source change.

### Task 1: Reuse the unique exact-directory session safely

**Files:**

- Modify: `.config/tmux/tests/project-session.sh:158-225`
- Modify: `.local/bin/t:13-98`
- Test: `.config/tmux/tests/project-session.sh`
- Test: `.config/dotfiles/check-terminal-stack`

**Interfaces:**

- Consumes: the caller's current directory, `tmux list-sessions -F '#{session_name}'`, and `tmux display-message -p -t "=<name>:" '#{session_path}'`.
- Produces: `normalize_directory(path)`, which prints a physical absolute directory or returns nonzero.
- Produces: `attach_session(name, directory)`, which replaces the wrapper with an exact-name `tmux attach-session` process.
- Produces: `attach_current_directory_session(directory)`, which returns `0` on no match, attaches on one match, and exits through `die` on multiple matches.

- [ ] **Step 1: Add the failing exact-directory end-to-end cases**

Insert the following complete block in `.config/tmux/tests/project-session.sh` immediately before `shared_one_root=$(init_repository "$test_root/one/shared")`:

```sh
exact_root=$(init_repository "$test_root/exact/exact match")
private_tmux new-session -d -s manual_exact -c "$exact_root"
exact_session_count=$(private_tmux list-sessions -F '#{session_name}' | wc -l | tr -d '[:space:]')

run_t "$exact_root"
assert_equal 0 "$run_status" "exact-directory launch"
expected_exact_attach=$(printf 'attach\n<-c>\n<%s>\n<-t>\n<=manual_exact>' "$exact_root")
assert_equal "$expected_exact_attach" "$(cat "$attach_log")" "exact-directory attach arguments"
assert_equal "$exact_session_count" "$(private_tmux list-sessions -F '#{session_name}' | wc -l | tr -d '[:space:]')" "exact-directory session count"
assert_empty "$native_log" "exact-directory native fallback"
assert_empty "$stderr_file" "exact-directory diagnostics"
if private_tmux has-session -t '=exact_match' 2>/dev/null; then
  fail "exact-directory launch created generated-name duplicate"
fi

precedence_root=$(init_repository "$test_root/precedence/repository")
precedence_nested=$precedence_root/src/special
mkdir -p "$precedence_nested"
private_tmux new-session -d -s precedence_root -c "$precedence_root"
private_tmux new-session -d -s precedence_nested -c "$precedence_nested"

run_t "$precedence_nested"
assert_equal 0 "$run_status" "nested exact-directory launch"
expected_precedence_attach=$(printf 'attach\n<-c>\n<%s>\n<-t>\n<=precedence_nested>' "$precedence_nested")
assert_equal "$expected_precedence_attach" "$(cat "$attach_log")" "nested exact-directory precedence"
assert_empty "$native_log" "nested exact-directory native fallback"

outside_exact_directory=$test_root/outside-exact
mkdir -p "$outside_exact_directory"
private_tmux new-session -d -s outside_exact -c "$outside_exact_directory"

run_t "$outside_exact_directory"
assert_equal 0 "$run_status" "outside-Git exact-directory launch"
expected_outside_exact_attach=$(printf 'attach\n<-c>\n<%s>\n<-t>\n<=outside_exact>' "$outside_exact_directory")
assert_equal "$expected_outside_exact_attach" "$(cat "$attach_log")" "outside-Git exact-directory attach"
assert_empty "$native_log" "outside-Git exact-directory native fallback"

physical_directory=$test_root/physical-target
symbolic_directory=$test_root/symbolic-target
mkdir -p "$physical_directory"
ln -s "$physical_directory" "$symbolic_directory"
private_tmux new-session -d -s symbolic_exact -c "$physical_directory"

run_t "$symbolic_directory"
assert_equal 0 "$run_status" "symbolic exact-directory launch"
expected_symbolic_attach=$(printf 'attach\n<-c>\n<%s>\n<-t>\n<=symbolic_exact>' "$physical_directory")
assert_equal "$expected_symbolic_attach" "$(cat "$attach_log")" "symbolic exact-directory normalization"
assert_empty "$native_log" "symbolic exact-directory native fallback"

duplicate_root=$(init_repository "$test_root/duplicates/duplicate project")
private_tmux new-session -d -s duplicate_one -c "$duplicate_root"
private_tmux new-session -d -s duplicate_two -c "$duplicate_root"
duplicate_session_count=$(private_tmux list-sessions -F '#{session_name}' | wc -l | tr -d '[:space:]')

run_t "$duplicate_root"
assert_equal 1 "$run_status" "duplicate exact-directory launch"
assert_contains "t: multiple sessions use directory '$duplicate_root':" "$stderr_file" "duplicate exact-directory diagnostic"
assert_contains "'duplicate_one'" "$stderr_file" "first duplicate session name"
assert_contains "'duplicate_two'" "$stderr_file" "second duplicate session name"
assert_empty "$attach_log" "duplicate exact-directory attach"
assert_empty "$native_log" "duplicate exact-directory native fallback"
assert_equal "$duplicate_session_count" "$(private_tmux list-sessions -F '#{session_name}' | wc -l | tr -d '[:space:]')" "duplicate exact-directory session count"
if private_tmux has-session -t '=duplicate_project' 2>/dev/null; then
  fail "duplicate exact-directory launch created another session"
fi
```

- [ ] **Step 2: Run the focused test and verify the current wrapper fails**

Run:

```sh
env -u TMUX -u TMUX_PANE /home/ruohao/.config/tmux/tests/project-session.sh
```

Expected: exit `1` at `exact-directory attach arguments`, because the attachment log targets `=exact_match` instead of `=manual_exact` and the private server contains both sessions at the same path.

- [ ] **Step 3: Replace the launcher with the exact-directory discovery flow**

Replace `.local/bin/t` with this complete content:

```sh
#!/bin/sh
set -eu

die() {
  printf 't: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'usage: t' >&2
}

normalize_directory() {
  CDPATH='' cd -P "$1" 2>/dev/null && pwd -P
}

attach_session() {
  exec tmux attach-session -c "$2" -t "=$1"
}

session_root() {
  tmux display-message -p -t "=$1:" '#{session_path}' 2>/dev/null
}

attach_current_directory_session() {
  exact_directory=$1

  if ! exact_session_names=$(tmux list-sessions -F '#{session_name}' 2>/dev/null); then
    return 0
  fi

  exact_match_count=0
  exact_match=
  exact_match_list=

  while IFS= read -r exact_candidate; do
    [ -n "$exact_candidate" ] || continue
    exact_root=$(session_root "$exact_candidate") || continue
    exact_normalized_root=$(normalize_directory "$exact_root") || continue
    [ "$exact_normalized_root" = "$exact_directory" ] || continue

    exact_match_count=$((exact_match_count + 1))
    exact_match=$exact_candidate
    if [ -z "$exact_match_list" ]; then
      exact_match_list="'$exact_candidate'"
    else
      exact_match_list="$exact_match_list, '$exact_candidate'"
    fi
  done <<EOF
$exact_session_names
EOF

  case $exact_match_count in
    0)
      return 0
      ;;
    1)
      attach_session "$exact_match" "$exact_directory"
      ;;
    *)
      die "multiple sessions use directory '$exact_directory': $exact_match_list"
      ;;
  esac
}

claim_or_attach() {
  candidate=$1

  if tmux has-session -t "=$candidate" 2>/dev/null; then
    existing_root=$(session_root "$candidate") || die "could not inspect session '$candidate'"
    if [ "$existing_root" = "$project_root" ]; then
      attach_session "$candidate" "$project_root"
    fi
    return 1
  fi

  if tmux new-session -d -s "$candidate" -c "$project_root" 2>/dev/null; then
    attach_session "$candidate" "$project_root"
  fi

  if tmux has-session -t "=$candidate" 2>/dev/null; then
    existing_root=$(session_root "$candidate") || die "could not inspect session '$candidate' after a create race"
    if [ "$existing_root" = "$project_root" ]; then
      attach_session "$candidate" "$project_root"
    fi
    return 1
  fi

  die "could not create session '$candidate'"
}

if [ -n "${TMUX-}" ]; then
  die "already inside tmux"
fi

if [ "$#" -ne 0 ]; then
  usage
  exit 2
fi

if ! command -v tmux >/dev/null 2>&1; then
  printf '%s\n' 't: tmux is not installed or not in PATH' >&2
  exit 127
fi

workspace_helper=$HOME/.config/tmux/scripts/workspace
[ -x "$workspace_helper" ] \
  || die "workspace helper is missing or not executable: $workspace_helper"
"$workspace_helper" ensure \
  || die "workspace restoration did not become ready"

if ! current_directory=$(normalize_directory .); then
  die "could not normalize current directory"
fi
attach_current_directory_session "$current_directory"

if ! command -v git >/dev/null 2>&1; then
  printf '%s\n' 't: git is not installed or not in PATH' >&2
  exit 127
fi

if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  exec tmux
fi

if ! project_root=$(normalize_directory "$git_root"); then
  die "could not normalize Git root '$git_root'"
fi

project_name=${project_root##*/}
session_base=$(printf '%s' "$project_name" | LC_ALL=C sed 's/[^A-Za-z0-9_-][^A-Za-z0-9_-]*/_/g')
if [ -z "$session_base" ]; then
  session_base=project
fi

if claim_or_attach "$session_base"; then
  exit 0
fi

full_hash=$(printf '%s' "$project_root" | git hash-object --stdin 2>/dev/null) || die "could not hash Git root '$project_root'"
short_hash=$(printf '%.8s' "$full_hash")
collision_name=$session_base-$short_hash

if claim_or_attach "$collision_name"; then
  exit 0
fi

die "session '$collision_name' belongs to another project"
```

- [ ] **Step 4: Run the focused regression test after the implementation**

Run:

```sh
env -u TMUX -u TMUX_PANE /home/ruohao/.config/tmux/tests/project-session.sh
```

Expected: exit `0` with exactly `ok - project session launcher` on standard output and no standard error.

- [ ] **Step 5: Validate POSIX syntax and static analysis**

Run:

```sh
sh -n /home/ruohao/.local/bin/t
sh -n /home/ruohao/.config/tmux/tests/project-session.sh
shellcheck --shell=sh /home/ruohao/.local/bin/t /home/ruohao/.config/tmux/tests/project-session.sh
```

Expected: every command exits `0` and prints no findings.

- [ ] **Step 6: Run the neighboring tmux regression tests**

Run:

```sh
/home/ruohao/.config/tmux/tests/fresh-start.sh
/home/ruohao/.config/tmux/tests/workspace-state.sh
/home/ruohao/.config/tmux/tests/workspace-restore.sh
```

Expected:

```text
ok - tmux fresh-start foundation
ok - workspace state boundary
ok - workspace structural restore
```

- [ ] **Step 7: Run the complete terminal-stack integration gate**

Run:

```sh
/home/ruohao/.config/dotfiles/check-terminal-stack
```

Expected: exit `0` and finish with `Summary: 0 failure(s), 0 warning(s)`.

- [ ] **Step 8: Review the exact implementation diff**

Run:

```sh
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao diff --check -- .local/bin/t .config/tmux/tests/project-session.sh
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao diff -- .local/bin/t .config/tmux/tests/project-session.sh
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao status --short --untracked-files=no
```

Expected: the check prints nothing, the diff contains only the approved wrapper and focused test changes, and tracked status lists only `.local/bin/t` and `.config/tmux/tests/project-session.sh`.

- [ ] **Step 9: Commit the verified wrapper change**

Run:

```sh
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao add -- .local/bin/t .config/tmux/tests/project-session.sh
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao commit -m 'fix(tmux): reuse exact-directory sessions' -- .local/bin/t .config/tmux/tests/project-session.sh
```

Expected: one commit containing only the launcher behavior and its end-to-end regression coverage.
