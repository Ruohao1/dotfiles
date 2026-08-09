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
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-workspace-state.XXXXXX") || fail "could not create test root"
socket=$test_root/tmux.sock
state=$test_root/state
runtime=$test_root/runtime
stdout=$test_root/stdout
stderr=$test_root/stderr
status=0

cleanup() {
  "$real_tmux" -S "$socket" kill-server >/dev/null 2>&1 || :
  case $test_root in
    "${TMPDIR:-/tmp}"/dotfiles-workspace-state.*) rm -rf "$test_root" ;;
    *) printf 'refusing cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup 0 HUP INT TERM

run_workspace() {
  set +e
  HOME=$test_root/home \
    XDG_STATE_HOME=$state \
    XDG_RUNTIME_DIR=$runtime \
    TMUX_WORKSPACE_TESTING=1 \
    TMUX_WORKSPACE_SOCKET=$socket \
    "$workspace" "$@" >"$stdout" 2>"$stderr"
  status=$?
  set -e
}

run_workspace --help
assert_equal 0 "$status" "help status"
assert_contains 'tmux-workspace save' "$stdout" "help save command"
assert_contains 'tmux-workspace doctor' "$stdout" "help doctor command"

run_workspace unknown
assert_equal 2 "$status" "unknown command status"

run_workspace save
assert_equal 0 "$status" "empty-server checkpoint"
generation=$(cat "$state/dotfiles/tmux/current")
manifest=$state/dotfiles/tmux/snapshots/$generation/snapshot.json
jq -e '.schema == 1 and .sessions == [] and .windows == [] and .panes == []' \
  "$manifest" >/dev/null || fail "empty snapshot schema"
assert_equal 700 "$(stat -c %a "$state/dotfiles/tmux")" "Linux state directory mode"
assert_equal 600 "$(stat -c %a "$manifest")" "Linux manifest mode"

printf '%s\n' broken >"$state/dotfiles/tmux/current"
printf '%s\n' '{' >"$manifest"
run_workspace status
assert_equal 1 "$status" "invalid current pointer status"
assert_contains 'no valid snapshot' "$stderr" "invalid current diagnostic"

set +e
HOME=$test_root/home XDG_STATE_HOME=$state XDG_RUNTIME_DIR=$runtime \
  TMUX_WORKSPACE_TESTING=1 "$workspace" status >"$stdout" 2>"$stderr"
status=$?
set -e
assert_equal 2 "$status" "test mode requires private socket"
assert_contains 'TMUX_WORKSPACE_SOCKET is required in test mode' "$stderr" \
  "private socket guard"

pass "workspace state boundary"
