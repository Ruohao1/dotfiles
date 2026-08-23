# Tmux Shutdown Empty Snapshot Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent automatic tmux checkpoints from replacing a healthy workspace when the tmux server is unavailable, activate the repair in the login supervisor, and recover the protected pre-reboot workspace safely.

**Architecture:** The workspace helper will distinguish explicit checkpoints from supervisor-owned automatic checkpoints while keeping its public command-line interface unchanged.
Capture will expose whether its initial session inventory reached tmux, and automatic saves will discard their private staging generation without publication when it did not.
Recovery remains a separate operation because structural restore deliberately does not merge into a running tmux server.

**Tech Stack:** POSIX shell, tmux 3.7b, jq 1.8.2, systemd user services, ShellCheck, and the existing bare dotfiles Git repository.

## Global Constraints

- Automatic periodic and shutdown checkpoints must not replace a valid snapshot when tmux is unavailable.
- Explicit `tmux-workspace save` calls must retain the ability to publish an intentionally empty schema-1 snapshot.
- A skipped automatic checkpoint must not publish or prune a generation, update `current`, update the ready marker, or mark a live server.
- A skipped automatic checkpoint must remove only its own validated staging directory and release only its own checkpoint lock.
- Preserve the schema-1 format, restoration behavior, process resumption, retention count, manual save confirmation, and public command-line interface.
- Exercise only test-owned private tmux sockets during automated tests.
- Do not connect to, reload, stop, or otherwise mutate the live tmux server during automated verification.
- Preserve the protected recovery copy at `/home/ruohao/.local/state/dotfiles/tmux/recovery/20260823T001129Z-1488000216` until live restoration is verified.
- Never add an agent co-author trailer to a commit.

---

## File Map

- Modify `.config/tmux/scripts/workspace`.
  This executable owns snapshot capture, publication policy, supervisor checkpoints, and structural restore.
- Modify `.config/tmux/tests/workspace-restore.sh`.
  This executable owns the private-socket end-to-end supervisor and structural restore contract.
- Read only `.config/tmux/tests/workspace-state.sh`.
  This existing suite proves that an explicit save can still publish an empty snapshot.
- Read only `.config/docs/superpowers/specs/2026-08-23-tmux-shutdown-empty-snapshot-design.md`.
  This is the approved behavior contract.
- Read only `.config/systemd/user/tmux-workspace.service`.
  This unit must be restarted after implementation so its running shell loads the repaired helper.

### Task 1: Reject unavailable-server automatic checkpoints

**Files:**

- Modify: `.config/tmux/tests/workspace-restore.sh:238-277`
- Modify: `.config/tmux/scripts/workspace:16-33`
- Modify: `.config/tmux/scripts/workspace:386-409`
- Modify: `.config/tmux/scripts/workspace:714-738`
- Modify: `.config/tmux/scripts/workspace:1593-1619`
- Modify: `.config/tmux/scripts/workspace:1650-1653`
- Test: `.config/tmux/tests/workspace-restore.sh`
- Test: `.config/tmux/tests/workspace-state.sh`

**Interfaces:**

- Consumes: `save_snapshot POLICY`, where `POLICY` is exactly `explicit` or `automatic`.
- Produces: `capture_reached_server`, an internal shell flag reset to `0` for each capture and set to `1` only when the initial `tmux list-sessions` inventory succeeds.
- Produces: explicit saves with unchanged empty-snapshot behavior.
- Produces: automatic saves that return success without publication when `capture_reached_server=0`.

- [ ] **Step 1: Add the failing shutdown-order regression**

In `.config/tmux/tests/workspace-restore.sh`, replace the existing `stop_private_server` call immediately after the first supervisor lock assertion with this complete block, leaving the following `rm -f "$runtime/dotfiles-tmux/ready"` line in place:

```sh
unavailable_supervisor_stdout=$test_root/unavailable-supervisor.stdout
unavailable_supervisor_stderr=$test_root/unavailable-supervisor.stderr
HOME=$test_root/home \
  SHELL=/bin/sh \
  XDG_STATE_HOME=$state \
  XDG_RUNTIME_DIR=$runtime \
  TMUX_WORKSPACE_TESTING=1 \
  TMUX_WORKSPACE_SOCKET=$socket \
  TMUX_WORKSPACE_INTERVAL=300 \
  "$workspace" supervise \
  >"$unavailable_supervisor_stdout" \
  2>"$unavailable_supervisor_stderr" &
unavailable_supervisor_pid=$!
wait_attempt=0
while [ ! -d "$runtime/dotfiles-tmux/supervisor.lock" ] \
  && [ "$wait_attempt" -lt 200 ]; do
  sleep 0.01
  wait_attempt=$((wait_attempt + 1))
done
[ -d "$runtime/dotfiles-tmux/supervisor.lock" ] \
  || fail "unavailable-server supervisor lock"
kill -0 "$unavailable_supervisor_pid" >/dev/null 2>&1 \
  || fail "unavailable-server supervisor exited before capture"

unavailable_generation_before=$(cat "$state/dotfiles/tmux/current")
unavailable_manifest=$state/dotfiles/tmux/snapshots/$unavailable_generation_before/snapshot.json
unavailable_pointer_before=$test_root/unavailable-current.before
unavailable_manifest_before=$test_root/unavailable-manifest.before
unavailable_ready_before=$test_root/unavailable-ready.before
cp "$state/dotfiles/tmux/current" "$unavailable_pointer_before"
cp "$unavailable_manifest" "$unavailable_manifest_before"
cp "$runtime/dotfiles-tmux/ready" "$unavailable_ready_before"
unavailable_generation_count_before=$(
  find "$state/dotfiles/tmux/snapshots" -mindepth 1 -maxdepth 1 -type d \
    ! -name '.staging-*' | wc -l | tr -d '[:space:]'
)

stop_private_server
kill -TERM "$unavailable_supervisor_pid"
wait "$unavailable_supervisor_pid"

assert_equal "$unavailable_generation_before" \
  "$(cat "$state/dotfiles/tmux/current")" \
  "unavailable-server final checkpoint generation"
cmp -s "$unavailable_pointer_before" "$state/dotfiles/tmux/current" \
  || fail "unavailable-server final checkpoint changed current pointer bytes"
cmp -s "$unavailable_manifest_before" "$unavailable_manifest" \
  || fail "unavailable-server final checkpoint changed manifest bytes"
cmp -s "$unavailable_ready_before" "$runtime/dotfiles-tmux/ready" \
  || fail "unavailable-server final checkpoint changed ready marker bytes"
unavailable_generation_count_after=$(
  find "$state/dotfiles/tmux/snapshots" -mindepth 1 -maxdepth 1 -type d \
    ! -name '.staging-*' | wc -l | tr -d '[:space:]'
)
assert_equal "$unavailable_generation_count_before" \
  "$unavailable_generation_count_after" \
  "unavailable-server completed generation count"
unavailable_staging_count=$(
  find "$state/dotfiles/tmux/snapshots" -mindepth 1 -maxdepth 1 -type d \
    -name '.staging-*' | wc -l | tr -d '[:space:]'
)
assert_equal 0 "$unavailable_staging_count" \
  "unavailable-server staging generation count"
[ ! -e "$runtime/dotfiles-tmux/supervisor.lock" ] \
  || fail "unavailable-server supervisor lock remained after stop"
```

- [ ] **Step 2: Run the structural restore test and verify the regression fails**

Run outside a restricted local-socket sandbox:

```sh
env -u TMUX -u TMUX_PANE \
  /home/ruohao/.config/tmux/tests/workspace-restore.sh
```

Expected: exit `1` with `not ok - unavailable-server final checkpoint generation`, because the current helper publishes a new zero-session generation after the private tmux server disappears.

- [ ] **Step 3: Add checkpoint policy and tmux reachability state**

In `.config/tmux/scripts/workspace`, add this global immediately after `staging_dir=`:

```sh
capture_reached_server=0
```

At the beginning of `capture_snapshot()`, immediately after `destination=$1`, reset the flag:

```sh
capture_reached_server=0
```

Set the flag inside the successful initial inventory branch:

```sh
if tmux_run list-sessions -F '#{session_id}' >"$session_ids_file" 2>/dev/null; then
  capture_reached_server=1
  tmux_run list-windows -a -F '#{window_id}' | sort -u >"$window_ids_file"
  tmux_run list-panes -a -F '#{pane_id}' | sort -u >"$pane_ids_file"
  tmux_run list-windows -a \
    -F '#{session_id}|#{window_id}|#{window_index}|#{window_active}|#{window_last_flag}' \
    >"$links_file"
fi
```

- [ ] **Step 4: Make publication policy explicit at every save call site**

Replace `save_snapshot()` with this complete function:

```sh
save_snapshot() {
  checkpoint_policy=$1
  case $checkpoint_policy in
    explicit|automatic) ;;
    *) die 'invalid checkpoint policy' 2 ;;
  esac

  prepare_roots
  acquire_lock checkpoint || die 'checkpoint already in progress' 1
  generation=$(new_generation)
  staging_dir=$workspace_state/snapshots/.staging-$$-$generation
  [ ! -e "$staging_dir" ] \
    || die "staging generation already exists: $generation" 1
  mkdir "$staging_dir"
  chmod 0700 "$staging_dir"

  capture_snapshot "$staging_dir/snapshot.json"

  if [ "$checkpoint_policy" = automatic ] \
    && [ "$capture_reached_server" -eq 0 ]; then
    case $staging_dir in
      "$workspace_state"/snapshots/.staging-*) rm -rf "$staging_dir" ;;
      *) die 'refusing to discard an unsafe staging generation' 1 ;;
    esac
    staging_dir=
    release_lock
    return 0
  fi

  publish_generation "$generation"
  if tmux_run list-sessions >/dev/null 2>&1; then
    if ! tmux_run set-option -g @dotfiles_workspace_generation "$generation" \
      \; set-option -guq @dotfiles_workspace_adopted; then
      append_warning 'the live tmux server could not be marked with its checkpoint generation'
    fi
  fi
  if [ -f "$workspace_runtime/ready" ] && [ ! -L "$workspace_runtime/ready" ]; then
    publish_ready "$generation"
  fi
  release_lock
  printf '%s\n' "$generation"
}
```

Replace the two supervisor calls with automatic policy calls:

```sh
if [ "$supervisor_stop" -eq 0 ]; then
  save_snapshot automatic >/dev/null
fi
```

```sh
save_snapshot automatic >/dev/null \
  || printf '%s\n' 'tmux-workspace: final checkpoint failed' >&2
```

Replace the public `save` case call with an explicit policy call:

```sh
save)
  [ "$#" -eq 1 ] || { usage 0; exit 2; }
  save_snapshot explicit
  ;;
```

- [ ] **Step 5: Run static validation**

Run:

```sh
sh -n /home/ruohao/.config/tmux/scripts/workspace
sh -n /home/ruohao/.config/tmux/tests/workspace-restore.sh
shellcheck /home/ruohao/.config/tmux/scripts/workspace \
  /home/ruohao/.config/tmux/tests/workspace-restore.sh
```

Expected: every command exits `0` with no diagnostics.

- [ ] **Step 6: Run focused state and end-to-end tests**

Run outside a restricted local-socket sandbox:

```sh
env -u TMUX -u TMUX_PANE \
  /home/ruohao/.config/tmux/tests/workspace-state.sh
env -u TMUX -u TMUX_PANE \
  /home/ruohao/.config/tmux/tests/workspace-restore.sh
```

Expected: the first test ends with `ok - workspace state boundary` and proves explicit empty saves still work.
The second test ends with `ok - workspace structural restore` and proves both live-server final saves and unavailable-server final no-ops.

- [ ] **Step 7: Run the aggregate automated terminal-stack checker**

Run outside a restricted local-socket sandbox:

```sh
/home/ruohao/.config/dotfiles/check-terminal-stack
```

Expected: exit `0` with `Summary: 0 failure(s)`.

- [ ] **Step 8: Review and commit only the implementation files**

Run:

```sh
cd /home/ruohao
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao diff --check
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao diff -- \
  .config/tmux/scripts/workspace \
  .config/tmux/tests/workspace-restore.sh
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao add -- \
  .config/tmux/scripts/workspace \
  .config/tmux/tests/workspace-restore.sh
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao diff --cached --check
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao diff --cached --name-status
/usr/bin/git --git-dir=/home/ruohao/.cfg --work-tree=/home/ruohao commit \
  -m 'fix(tmux): preserve workspace when server disappears'
```

Expected: the staged name-status lists exactly the two implementation files and the commit has no co-author trailer.

### Task 2: Activate and verify the repaired supervisor

**Files:**

- Read only: `.config/systemd/user/tmux-workspace.service`
- Read only: `.config/tmux/scripts/workspace`
- Runtime: the live `tmux-workspace.service`

**Interfaces:**

- Consumes: committed repaired helper from Task 1.
- Produces: a running user service whose shell process has loaded the repaired functions.
- Preserves: every live tmux session, window, pane, and client.

- [ ] **Step 1: Capture the live topology without changing it**

Run:

```sh
activation_root=/tmp/tmux-workspace-supervisor-activation
test ! -e "$activation_root"
install -d -m 700 "$activation_root"
tmux list-sessions \
  -F 'session=#{session_id}|name=#{session_name}|windows=#{session_windows}|attached=#{session_attached}' \
  >"$activation_root/sessions.before"
tmux list-windows -a \
  -F 'window=#{window_id}|session=#{session_name}|index=#{window_index}|panes=#{window_panes}' \
  >"$activation_root/windows.before"
tmux list-panes -a \
  -F 'pane=#{pane_id}|session=#{session_name}|window=#{window_index}|index=#{pane_index}' \
  >"$activation_root/panes.before"
```

Expected: all commands exit `0` and the guarded activation directory contains the three topology baselines.

- [ ] **Step 2: Restart only the workspace supervisor**

Run from the current user session:

```sh
systemctl --user restart tmux-workspace.service
```

Expected: exit `0` without disconnecting any tmux client.
The old supervisor may checkpoint the still-running server before exit, and the new supervisor loads the repaired helper.

- [ ] **Step 3: Verify service health and unchanged live topology**

Run:

```sh
activation_root=/tmp/tmux-workspace-supervisor-activation
test -d "$activation_root"
test ! -L "$activation_root"
systemctl --user is-active tmux-workspace.service
/home/ruohao/.config/tmux/scripts/workspace doctor
/home/ruohao/.config/tmux/scripts/workspace status
tmux list-sessions \
  -F 'session=#{session_id}|name=#{session_name}|windows=#{session_windows}|attached=#{session_attached}' \
  >"$activation_root/sessions.after"
tmux list-windows -a \
  -F 'window=#{window_id}|session=#{session_name}|index=#{window_index}|panes=#{window_panes}' \
  >"$activation_root/windows.after"
tmux list-panes -a \
  -F 'pane=#{pane_id}|session=#{session_name}|window=#{window_index}|index=#{pane_index}' \
  >"$activation_root/panes.after"
cmp "$activation_root/sessions.before" "$activation_root/sessions.after"
cmp "$activation_root/windows.before" "$activation_root/windows.after"
cmp "$activation_root/panes.before" "$activation_root/panes.after"
find "$activation_root" -depth -delete
```

Expected: the service reports `active`, doctor reports `tmux-workspace doctor: ok`, status reports `Supervisor: running, ready`, and the three topology listings are byte-identical to Step 1.

### Task 3: Restore the protected pre-reboot workspace

**Files:**

- Read only: `/home/ruohao/.local/state/dotfiles/tmux/recovery/20260823T001129Z-1488000216/snapshot.json`
- Runtime: `/home/ruohao/.local/state/dotfiles/tmux/current`
- Runtime: `/home/ruohao/.local/state/dotfiles/tmux/snapshots/20260823T001129Z-1488000216/`
- Runtime: `${XDG_RUNTIME_DIR}/dotfiles-tmux/ready`
- Runtime: the default tmux server and `tmux-workspace.service`

**Interfaces:**

- Consumes: the protected schema-1 generation with exactly one session, two windows, and six panes.
- Produces: the default tmux server restored from generation `20260823T001129Z-1488000216`.
- Preserves: a protected copy of both the pre-reboot generation and the final post-reboot generation.

- [ ] **Step 1: Stop before recovery unless running outside tmux**

Run in the shell that will perform recovery:

```sh
test -z "${TMUX-}" && test -z "${TMUX_PANE-}"
```

Expected: exit `0`.
If it exits nonzero, detach from tmux and open a normal shell before continuing because stopping the default server would terminate the recovery process.

- [ ] **Step 2: Validate the protected generation and save the post-reboot workspace**

Run:

```sh
workspace=/home/ruohao/.config/tmux/scripts/workspace
state_root=/home/ruohao/.local/state/dotfiles/tmux
recovery_root=$state_root/recovery
generation=20260823T001129Z-1488000216
protected_generation=$recovery_root/$generation
test -d "$protected_generation"
test ! -L "$protected_generation"
test -f "$protected_generation/snapshot.json"
test ! -L "$protected_generation/snapshot.json"
test -z "$(find "$protected_generation" -type l -print -quit)"
jq -e '.schema == 1 and (.sessions | length) == 1 and (.windows | length) == 2 and (.panes | length) == 6' \
  "$protected_generation/snapshot.json" >/dev/null
post_reboot_generation=$("$workspace" save)
post_reboot_source=$state_root/snapshots/$post_reboot_generation
post_reboot_protected=$recovery_root/post-reboot-$post_reboot_generation
test ! -e "$post_reboot_protected"
cp -a "$post_reboot_source" "$post_reboot_protected"
cmp "$post_reboot_source/snapshot.json" \
  "$post_reboot_protected/snapshot.json"
```

Expected: every command exits `0`, and the post-reboot live workspace has a protected copy outside rolling retention.

- [ ] **Step 3: Stop the supervisor and default tmux server**

Run:

```sh
systemctl --user stop tmux-workspace.service
systemctl --user is-active tmux-workspace.service | grep -Fx inactive
tmux kill-server
```

Expected: the service reports `inactive`, `tmux kill-server` exits `0`, and the recovery shell remains alive because it is outside tmux.

- [ ] **Step 4: Publish the protected generation as the restore target**

Run:

```sh
state_root=/home/ruohao/.local/state/dotfiles/tmux
recovery_root=$state_root/recovery
generation=20260823T001129Z-1488000216
protected_generation=$recovery_root/$generation
snapshot_root=$state_root/snapshots
target_generation=$snapshot_root/$generation
if [ -e "$target_generation" ]; then
  test -d "$target_generation"
  test ! -L "$target_generation"
  diff -qr "$protected_generation" "$target_generation"
else
  cp -a "$protected_generation" "$target_generation"
fi
chmod 0700 "$target_generation"
find "$target_generation" -type f -exec chmod 0600 {} +
pointer_staging=$state_root/.current-recovery-$$
printf '%s\n' "$generation" >"$pointer_staging"
chmod 0600 "$pointer_staging"
mv "$pointer_staging" "$state_root/current"
runtime_root=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dotfiles-tmux
case $runtime_root in
  /run/user/"$(id -u)"/dotfiles-tmux) ;;
  *) printf 'unexpected tmux runtime root: %s\n' "$runtime_root" >&2; exit 1 ;;
esac
rm -f "$runtime_root/ready"
```

Expected: the protected snapshot is byte-identical to the normal snapshot copy, `current` contains exactly `20260823T001129Z-1488000216`, and the stale ready marker is absent.

- [ ] **Step 5: Start restoration and verify the recovered topology**

Run:

```sh
generation=20260823T001129Z-1488000216
systemctl --user start tmux-workspace.service
restore_attempt=0
while [ "$restore_attempt" -lt 30 ]; do
  restored_generation=$(tmux show-options -gqv \
    @dotfiles_workspace_generation 2>/dev/null || :)
  [ "$restored_generation" = "$generation" ] && break
  sleep 1
  restore_attempt=$((restore_attempt + 1))
done
test "$restored_generation" = "$generation"
test "$(tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')" -eq 1
test "$(tmux list-windows -a -F '#{window_id}' | sort -u | wc -l | tr -d '[:space:]')" -eq 2
test "$(tmux list-panes -a -F '#{pane_id}' | sort -u | wc -l | tr -d '[:space:]')" -eq 6
/home/ruohao/.config/tmux/scripts/workspace status
```

Expected: the selected generation marker matches, topology counts are `1`, `2`, and `6`, status reports the restored generation with a running and ready supervisor, and the protected recovery directories remain intact.

- [ ] **Step 6: Attach through the normal wrapper**

Run:

```sh
cd /home/ruohao/.config
t
```

Expected: `t` attaches the restored session instead of creating a fresh one.
