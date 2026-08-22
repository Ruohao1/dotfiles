# tmux Fresh-Start Foundation Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `t` start a fresh tmux server without foundation errors and keep `allow-passthrough` enabled as the global default for every pane.

**Architecture:** Correct the pane option at its source by setting it in the global window option table.
A focused shell test will exercise the live tmux entry file on a uniquely owned socket, and the existing terminal-stack checker will invoke that test and query the corrected option scope.

**Tech Stack:** POSIX shell, tmux 3.7c, ShellCheck, and the existing bare dotfiles Git repository.

## Global Constraints

- Preserve the shared tmux entry point, platform selection, aggregate source command, failure sentinel, `t` launcher, and workspace restoration flow.
- Apply `allow-passthrough=on` to every current and future pane without requiring a current window during server startup.
- Exercise only uniquely owned private tmux sockets under guarded temporary directories.
- Never connect to, reload, or stop the user's normal tmux server.
- Distinguish startup-command failure, emitted startup diagnostics, foundation-marker failure, platform-marker failure, passthrough-scope failure, and cleanup failure.
- Preserve successful isolated reload and idempotence behavior.

---

### Task 1: Correct the passthrough scope with a focused fresh-start regression test

**Files:**

- Create: `tmux/tests/fresh-start.sh`
- Modify: `tmux/conf/options.conf:15`
- Test: `tmux/tests/fresh-start.sh`

**Interfaces:**

- Consumes: the live `tmux/tmux.conf` entry file and its shared modules beneath `tmux/conf/`.
- Produces: an executable zero-argument test that exits `0` only when fresh startup is clean, both foundation markers are correct, global window `allow-passthrough` is `on`, and its private server is removed.

- [ ] **Step 1: Write the failing fresh-start test**

Create `tmux/tests/fresh-start.sh` with this complete content:

```sh
#!/bin/sh
set -eu

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_equal() {
  assert_expected=$1
  assert_actual=$2
  assert_label=$3
  if [ "$assert_expected" != "$assert_actual" ]; then
    fail "$assert_label: expected <$assert_expected>, got <$assert_actual>"
  fi
}

assert_empty() {
  assert_file=$1
  assert_label=$2
  if [ -s "$assert_file" ]; then
    sed 's/^/      /' "$assert_file" >&2
    fail "$assert_label: expected no output"
  fi
}

script_directory=$(CDPATH='' cd -P "$(dirname "$0")" && pwd -P)
repository_root=$(CDPATH='' cd -P "$script_directory/../../.." && pwd -P)
config_root=$repository_root/.config
tmux_entry=$config_root/tmux/tmux.conf

[ -r "$tmux_entry" ] || fail "tmux entry is not readable: $tmux_entry"
real_tmux=$(command -v tmux) || fail "tmux is required"

case "$(uname -s)" in
  Darwin) expected_platform=macos ;;
  Linux) expected_platform=linux ;;
  *) fail "unsupported platform from uname -s" ;;
esac

test_root=
socket_path=

cleanup() {
  if [ -n "$socket_path" ]; then
    "$real_tmux" -S "$socket_path" kill-server >/dev/null 2>&1 || :
  fi
  if [ -n "$test_root" ] && [ "$test_root" != / ]; then
    case ${test_root##*/} in
      dotfiles-tmux-fresh-start.*)
        rm -rf "$test_root"
        ;;
      *)
        printf 'refusing to remove unexpected test path: %s\n' "$test_root" >&2
        ;;
    esac
  fi
}

trap cleanup 0 HUP INT TERM

test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tmux-fresh-start.XXXXXX") \
  || fail "could not create a temporary directory"
socket_path=$test_root/tmux.sock
stdout_file=$test_root/stdout
stderr_file=$test_root/stderr
state_root=$test_root/state
cache_root=$test_root/cache
runtime_root=$test_root/runtime
mkdir -p "$state_root" "$cache_root" "$runtime_root"

if ! env -u TMUX -u TMUX_PANE -u NVIM_APPNAME \
  HOME="$repository_root" \
  SHELL=/bin/sh \
  XDG_CONFIG_HOME="$config_root" \
  XDG_DATA_HOME="${XDG_DATA_HOME:-$repository_root/.local/share}" \
  XDG_STATE_HOME="$state_root" \
  XDG_CACHE_HOME="$cache_root" \
  XDG_RUNTIME_DIR="$runtime_root" \
  TERM=xterm-ghostty \
  TERM_PROGRAM=ghostty \
  "$real_tmux" -S "$socket_path" -f "$tmux_entry" \
    new-session -d -s terminal-stack-fresh-start \
    >"$stdout_file" 2>"$stderr_file"; then
  sed 's/^/      /' "$stdout_file" >&2
  sed 's/^/      /' "$stderr_file" >&2
  fail "fresh tmux server did not start"
fi

assert_empty "$stdout_file" "fresh tmux stdout"
assert_empty "$stderr_file" "fresh tmux stderr"

foundation_loaded=
attempts=0
while [ "$attempts" -lt 5 ]; do
  foundation_loaded=$("$real_tmux" -S "$socket_path" \
    show-options -gqv @dotfiles_foundation_loaded 2>/dev/null || :)
  [ "$foundation_loaded" = 1 ] && break
  attempts=$((attempts + 1))
  sleep 1
done
assert_equal 1 "$foundation_loaded" "fresh foundation marker"

actual_platform=$("$real_tmux" -S "$socket_path" \
  show-options -gqv @dotfiles_platform 2>/dev/null || :)
assert_equal "$expected_platform" "$actual_platform" "fresh platform marker"

passthrough=$("$real_tmux" -S "$socket_path" \
  show-options -wgqv allow-passthrough 2>/dev/null) \
  || fail "could not read global allow-passthrough"
assert_equal on "$passthrough" "fresh global allow-passthrough"

"$real_tmux" -S "$socket_path" kill-server \
  || fail "fresh private tmux server did not stop"
case "$socket_path" in
  "$test_root"/tmux.sock)
    rm -f "$socket_path"
    ;;
  *)
    fail "refusing to remove unexpected tmux socket: $socket_path"
    ;;
esac
[ ! -e "$socket_path" ] \
  || fail "fresh private tmux socket remained after shutdown"
socket_path=

pass "tmux fresh-start foundation"
```

- [ ] **Step 2: Make the focused test executable**

Run:

```sh
chmod +x tmux/tests/fresh-start.sh
```

Expected: `test -x tmux/tests/fresh-start.sh` exits `0`.

- [ ] **Step 3: Run the regression test against the broken configuration**

Run:

```sh
tmux/tests/fresh-start.sh
```

Expected: exit `1` with `not ok - fresh foundation marker: expected <1>, got <0>`.

- [ ] **Step 4: Apply the minimal configuration fix**

Replace the incorrect line in `tmux/conf/options.conf`:

```tmux
set -s allow-passthrough on
```

with the explicit global window default:

```tmux
set -gw allow-passthrough on
```

- [ ] **Step 5: Run the focused regression test after the fix**

Run:

```sh
tmux/tests/fresh-start.sh
```

Expected: exit `0` with `ok - tmux fresh-start foundation` and no foundation diagnostics.

- [ ] **Step 6: Validate both changed shell/config files**

Run:

```sh
shellcheck tmux/tests/fresh-start.sh
```

Expected: exit `0` and ShellCheck prints no findings.

- [ ] **Step 7: Commit the focused repair**

Run:

```sh
/usr/bin/git --git-dir="$HOME/.cfg" --work-tree="$HOME" add -- \
  .config/tmux/conf/options.conf \
  .config/tmux/tests/fresh-start.sh
/usr/bin/git --git-dir="$HOME/.cfg" --work-tree="$HOME" commit \
  -m 'fix(tmux): load passthrough on fresh startup' -- \
  .config/tmux/conf/options.conf \
  .config/tmux/tests/fresh-start.sh
```

Expected: one commit containing only the option-scope correction and focused regression test.

### Task 2: Integrate fresh-start coverage into the terminal-stack checker

**Files:**

- Modify: `dotfiles/check-terminal-stack:6080-6090`
- Modify: `dotfiles/check-terminal-stack:8158-8185`
- Modify: `dotfiles/check-terminal-stack:8999-9000`
- Modify: `dotfiles/check-terminal-stack:10565-10566`
- Test: `dotfiles/check-terminal-stack`
- Test: `tmux/tests/project-session.sh`
- Test: `tmux/tests/workspace-state.sh`
- Test: `tmux/tests/workspace-restore.sh`

**Interfaces:**

- Consumes: the zero-argument `tmux/tests/fresh-start.sh` executable from Task 1.
- Produces: a full checker that fails when the focused fresh-start test fails and reads `allow-passthrough` from the global window option table during initial and reload assertions.

- [ ] **Step 1: Register and run the focused test from the full checker**

Define the test path beside the other tmux paths:

```sh
tmux_fresh_start_test="$tmux_root/tests/fresh-start.sh"
```

Require the file beside the other tmux requirements:

```sh
require_file "$tmux_fresh_start_test" || true
```

Run it immediately before the existing `/dev/null` private-server bootstrap:

```sh
if [ -x "$tmux_fresh_start_test" ]; then
  if "$tmux_fresh_start_test" \
    > "$check_tmp/tmux-fresh-start.txt" 2>&1; then
    pass "live tmux entry passes a fresh private-server startup"
  else
    sed 's/^/      /' "$check_tmp/tmux-fresh-start.txt" >&2
    fail "live tmux entry failed a fresh private-server startup"
  fi
else
  fail "tmux fresh-start test is missing or not executable: $tmux_fresh_start_test"
fi
```

Change both passthrough assertions from the inferred server query:

```sh
require_tmux_option_value "$check_socket" server allow-passthrough on
```

to the explicit global window query:

```sh
require_tmux_option_value "$check_socket" window allow-passthrough on
```

- [ ] **Step 2: Run static validation on the checker**

Run:

```sh
shellcheck dotfiles/check-terminal-stack tmux/tests/fresh-start.sh
```

Expected: exit `0` with no findings.

- [ ] **Step 3: Run the complete automated terminal-stack checker**

Run:

```sh
dotfiles/check-terminal-stack
```

Expected: exit `0`, `PASS  live tmux entry passes a fresh private-server startup`, and `Summary: 0 failure(s)`.
Warnings about not running inside Ghostty or tmux are acceptable outside those programs.

- [ ] **Step 4: Run the existing tmux regression suite**

Run:

```sh
tmux/tests/project-session.sh
tmux/tests/workspace-state.sh
tmux/tests/workspace-restore.sh
```

Expected: each command exits `0` and ends with its respective `ok - project session launcher`, `ok - workspace state boundary`, or `ok - workspace structural restore` line.

- [ ] **Step 5: Review the exact implementation diff**

Run:

```sh
/usr/bin/git --git-dir="$HOME/.cfg" --work-tree="$HOME" diff -- \
  .config/tmux/conf/options.conf \
  .config/tmux/tests/fresh-start.sh \
  .config/dotfiles/check-terminal-stack
```

Expected: only the global option-scope correction, focused fresh-start test, checker invocation, and two corrected scope assertions appear.

- [ ] **Step 6: Commit the checker integration**

Run:

```sh
/usr/bin/git --git-dir="$HOME/.cfg" --work-tree="$HOME" add -- \
  .config/dotfiles/check-terminal-stack
/usr/bin/git --git-dir="$HOME/.cfg" --work-tree="$HOME" commit \
  -m 'test(tmux): cover fresh foundation startup' -- \
  .config/dotfiles/check-terminal-stack
```

Expected: one commit containing only the checker integration and corrected scope assertions.
