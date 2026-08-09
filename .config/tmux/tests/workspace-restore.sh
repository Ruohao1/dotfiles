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
  expected=$1
  actual=$2
  label=$3
  [ "$expected" = "$actual" ] || fail "$label: expected <$expected>, got <$actual>"
}

assert_contains() {
  needle=$1
  file=$2
  label=$3
  grep -F "$needle" "$file" >/dev/null 2>&1 || fail "$label: missing <$needle>"
}

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd -P)
workspace=$script_dir/../scripts/workspace
real_tmux=$(command -v tmux) || fail "tmux is required"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-workspace-restore.XXXXXX") \
  || fail "could not create test root"
socket=$test_root/tmux.sock
state=$test_root/state
runtime=$test_root/runtime
stdout=$test_root/stdout
stderr=$test_root/stderr
before=$test_root/before
after=$test_root/after
status=0

cleanup() {
  "$real_tmux" -S "$socket" kill-server >/dev/null 2>&1 || :
  case $test_root in
    "${TMPDIR:-/tmp}"/dotfiles-workspace-restore.*) rm -rf "$test_root" ;;
    *) printf 'refusing cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup 0 HUP INT TERM

run_workspace() {
  set +e
  HOME=$test_root/home \
    SHELL=/bin/sh \
    XDG_STATE_HOME=$state \
    XDG_RUNTIME_DIR=$runtime \
    TMUX_WORKSPACE_TESTING=1 \
    TMUX_WORKSPACE_SOCKET=$socket \
    "$workspace" "$@" >"$stdout" 2>"$stderr"
  status=$?
  set -e
}

private_tmux() {
  "$real_tmux" -S "$socket" "$@"
}

stop_private_server() {
  server_pid=$(private_tmux display-message -p '#{pid}') \
    || fail "could not read private tmux server PID"
  private_tmux kill-server >/dev/null 2>&1 || :
  wait_attempt=0
  while kill -0 "$server_pid" >/dev/null 2>&1 && [ "$wait_attempt" -lt 200 ]; do
    sleep 0.01
    wait_attempt=$((wait_attempt + 1))
  done
  if kill -0 "$server_pid" >/dev/null 2>&1; then
    fail "private tmux server did not exit"
  fi
  if [ -S "$socket" ]; then
    rm -f "$socket"
  fi
}

summarize() {
  private_tmux list-sessions \
    -F 's|#{session_name}|#{session_group}|#{session_path}|#{active_window_index}' |
    sort
  private_tmux list-windows -a \
    -F 'w|#{session_name}|#{window_index}|#{window_name}|#{window_zoomed_flag}|#{window_last_flag}' |
    sort
  private_tmux list-panes -a \
    -F 'p|#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}|#{pane_title}|#{pane_active}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' |
    sort
}

mkdir -p "$test_root/home" "$test_root/projects/alpha" "$test_root/projects/beta"
"$real_tmux" -f "$script_dir/../conf/options.conf" -S "$socket" \
  new-session -d -s alpha -c "$test_root/projects/alpha" -n editor
private_tmux split-window -d -t '=alpha:1' -c "$test_root/projects/beta"
private_tmux select-layout -t '=alpha:1' even-horizontal
private_tmux resize-pane -t '=alpha:1.1' -x 29
private_tmux select-pane -t '=alpha:1.1' -T left
private_tmux select-pane -t '=alpha:1.2' -T right
private_tmux new-window -d -t '=alpha:2' -n shell -c "$test_root/projects/beta"
private_tmux select-pane -t '=alpha:2.1' -T secondary
private_tmux new-session -d -s mirror -t '=alpha'
private_tmux new-session -d -s linked -c "$test_root/projects/beta" -n local
private_tmux select-pane -t '=linked:1.1' -T local
private_tmux link-window -d -s '=alpha:2' -t '=linked:2'
private_tmux select-pane -t '=alpha:1.2'
private_tmux resize-pane -Z -t '=alpha:1.2'
private_tmux select-window -t '=alpha:1'
private_tmux select-window -t '=alpha:2'
private_tmux select-window -t '=mirror:1'
private_tmux select-window -t '=mirror:2'
private_tmux select-window -t '=linked:2'
private_tmux select-window -t '=linked:1'

summarize >"$before"
run_workspace save
[ "$status" -eq 0 ] || sed -n '1,120p' "$stderr" >&2
assert_equal 0 "$status" "round-trip checkpoint"
generation=$(cat "$state/dotfiles/tmux/current")
stop_private_server

run_workspace restore
[ "$status" -eq 0 ] || sed -n '1,120p' "$stderr" >&2
assert_equal 0 "$status" "round-trip restore"
summarize >"$after"
if ! cmp -s "$before" "$after"; then
  diff -u "$before" "$after" >&2 || :
  fail "round-trip topology"
fi

assert_equal "$generation" \
  "$(private_tmux show-options -gqv @dotfiles_workspace_generation)" \
  "restored generation marker"
assert_equal alpha "$(private_tmux display-message -p -t '=mirror:' '#{session_group}')" \
  "restored group name"
alpha_window=$(private_tmux display-message -p -t '=alpha:2' '#{window_id}')
linked_window=$(private_tmux display-message -p -t '=linked:2' '#{window_id}')
assert_equal "$alpha_window" "$linked_window" "restored linked window identity"

counts_before=$(printf '%s|%s|%s' \
  "$(private_tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')" \
  "$(private_tmux list-windows -a -F '#{window_id}' | sort -u | wc -l | tr -d '[:space:]')" \
  "$(private_tmux list-panes -a -F '#{pane_id}' | sort -u | wc -l | tr -d '[:space:]')")
run_workspace restore
assert_equal 0 "$status" "idempotent restore"
counts_after=$(printf '%s|%s|%s' \
  "$(private_tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')" \
  "$(private_tmux list-windows -a -F '#{window_id}' | sort -u | wc -l | tr -d '[:space:]')" \
  "$(private_tmux list-panes -a -F '#{pane_id}' | sort -u | wc -l | tr -d '[:space:]')")
assert_equal "$counts_before" "$counts_after" "idempotent topology counts"

stop_private_server
corrupt_generation=zz-corrupt
mkdir -p "$state/dotfiles/tmux/snapshots/$corrupt_generation"
chmod 0700 "$state/dotfiles/tmux/snapshots/$corrupt_generation"
printf '%s\n' '{' >"$state/dotfiles/tmux/snapshots/$corrupt_generation/snapshot.json"
chmod 0600 "$state/dotfiles/tmux/snapshots/$corrupt_generation/snapshot.json"
printf '%s\n' "$corrupt_generation" >"$state/dotfiles/tmux/current"
run_workspace restore
assert_equal 0 "$status" "corrupt-current fallback restore"
assert_equal "$generation" \
  "$(private_tmux show-options -gqv @dotfiles_workspace_generation)" \
  "fallback generation marker"

stop_private_server
"$real_tmux" -f /dev/null -S "$socket" new-session -d -s local-only
session_count_before=$(private_tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')
run_workspace restore
assert_equal 0 "$status" "live server adoption"
session_count_after=$(private_tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')
assert_equal "$session_count_before" "$session_count_after" "adoption session count"
assert_equal 1 "$(private_tmux show-options -gqv @dotfiles_workspace_adopted)" \
  "adoption marker"

pass "workspace structural restore"
