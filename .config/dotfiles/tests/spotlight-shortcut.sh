#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
dotfiles_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
workspace_root=$(CDPATH='' cd -- "$dotfiles_dir/../.." && pwd)
helper=$workspace_root/.config/macos/spotlight-shortcut

failures=0
tests=0

pass() {
  tests=$((tests + 1))
  printf 'ok %d - %s\n' "$tests" "$1"
}

fail() {
  tests=$((tests + 1))
  failures=$((failures + 1))
  printf 'not ok %d - %s\n' "$tests" "$1" >&2
}

require_status() {
  actual=$1
  expected=$2
  label=$3
  if [ "$actual" -eq "$expected" ]; then
    pass "$label"
  else
    fail "$label"
    printf '  expected status: %s\n' "$expected" >&2
    printf '  actual status:   %s\n' "$actual" >&2
  fi
}

run_capture() {
  output_file=$1
  shift
  set +e
  "$@" >"$output_file" 2>&1
  run_status=$?
  set -e
}

test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-spotlight-test.XXXXXX")
cleanup() {
  case "$test_tmp" in
    "${TMPDIR:-/tmp}"/dotfiles-spotlight-test.*) rm -rf "$test_tmp" ;;
  esac
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -x "$helper" ]; then
  pass 'Spotlight shortcut helper is executable'
else
  fail 'Spotlight shortcut helper is executable'
fi

if [ -r "$helper" ] && sh -n "$helper"; then
  pass 'Spotlight shortcut helper has valid POSIX shell syntax'
else
  fail 'Spotlight shortcut helper has valid POSIX shell syntax'
fi

if [ -x "$helper" ]; then
  state=$test_tmp/state
  journal=$test_tmp/journal
  mkdir -p "$state"
  printf '%s\n' 'original Spotlight shortcut' >"$state/entry"
  run_capture "$test_tmp/apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$state" \
    "$helper" apply "$journal"
  require_status "$run_status" 0 'helper applies the Spotlight shortcut transactionally'
  if [ "$(cat "$journal/before.entry" 2>/dev/null || true)" = \
      'original Spotlight shortcut' ] \
    && [ -f "$journal/before.present" ] \
    && cmp -s "$state/entry" "$journal/after.entry" \
    && [ "$(cat "$journal/status" 2>/dev/null || true)" = applied ]; then
    pass 'helper journals the exact before and after shortcut values'
  else
    fail 'helper journals the exact before and after shortcut values'
  fi

  run_capture "$test_tmp/can-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$state" \
    "$helper" can-restore "$journal"
  require_status "$run_status" 0 'helper permits rollback while its applied value is current'

  run_capture "$test_tmp/restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$state" \
    "$helper" restore "$journal"
  require_status "$run_status" 0 'helper restores a previous Spotlight shortcut'
  if [ "$(cat "$state/entry" 2>/dev/null || true)" = \
      'original Spotlight shortcut' ] \
    && [ "$(cat "$journal/status" 2>/dev/null || true)" = restored ]; then
    pass 'helper restores the exact previous shortcut value'
  else
    fail 'helper restores the exact previous shortcut value'
  fi

  absent_state=$test_tmp/absent-state
  absent_journal=$test_tmp/absent-journal
  mkdir -p "$absent_state"
  run_capture "$test_tmp/absent-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$absent_state" \
    "$helper" apply "$absent_journal"
  require_status "$run_status" 0 'helper applies when no previous shortcut entry exists'
  run_capture "$test_tmp/absent-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$absent_state" \
    "$helper" restore "$absent_journal"
  require_status "$run_status" 0 'helper rolls back an originally absent shortcut entry'
  if [ ! -e "$absent_state/entry" ]; then
    pass 'rollback removes only the shortcut created by the transaction'
  else
    fail 'rollback removes only the shortcut created by the transaction'
  fi

  changed_state=$test_tmp/changed-state
  changed_journal=$test_tmp/changed-journal
  mkdir -p "$changed_state"
  printf '%s\n' 'shortcut before bootstrap' >"$changed_state/entry"
  run_capture "$test_tmp/changed-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$changed_state" \
    "$helper" apply "$changed_journal"
  printf '%s\n' 'shortcut changed after bootstrap' >"$changed_state/entry"
  run_capture "$test_tmp/changed-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$changed_state" \
    "$helper" restore "$changed_journal"
  require_status "$run_status" 3 'helper refuses to overwrite a later shortcut change'
  if [ "$(cat "$changed_state/entry")" = 'shortcut changed after bootstrap' ]; then
    pass 'conflicted rollback preserves the later shortcut change'
  else
    fail 'conflicted rollback preserves the later shortcut change'
  fi

  failure_state=$test_tmp/failure-state
  failure_journal=$test_tmp/failure-journal
  mkdir -p "$failure_state"
  printf '%s\n' 'shortcut before failed write' >"$failure_state/entry"
  run_capture "$test_tmp/failure.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$failure_state" \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_FAIL_WRITE=1 \
    "$helper" apply "$failure_journal"
  if [ "$run_status" -ne 0 ]; then
    pass 'helper reports a failed preference write'
  else
    fail 'helper reports a failed preference write'
  fi
  if [ "$(cat "$failure_state/entry")" = 'shortcut before failed write' ]; then
    pass 'failed preference write preserves the previous shortcut'
  else
    fail 'failed preference write preserves the previous shortcut'
  fi

  invalid_state=$test_tmp/invalid-state
  invalid_journal=$test_tmp/invalid-journal
  mkdir -p "$invalid_state"
  printf '%s\n' 'shortcut before invalid schema' >"$invalid_state/entry"
  run_capture "$test_tmp/invalid.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$invalid_state" \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_INVALID_SCHEMA=1 \
    "$helper" apply "$invalid_journal"
  if [ "$run_status" -ne 0 ]; then
    pass 'helper rejects an unsupported preference schema'
  else
    fail 'helper rejects an unsupported preference schema'
  fi
  if [ "$(cat "$invalid_state/entry")" = 'shortcut before invalid schema' ]; then
    pass 'schema rejection occurs before preference mutation'
  else
    fail 'schema rejection occurs before preference mutation'
  fi

  interrupted_state=$test_tmp/interrupted-state
  interrupted_journal=$test_tmp/interrupted-journal
  mkdir -p "$interrupted_state"
  printf '%s\n' 'shortcut before interruption' >"$interrupted_state/entry"
  run_capture "$test_tmp/interrupted-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$interrupted_state" \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STOP_AFTER_WRITE=1 \
    "$helper" apply "$interrupted_journal"
  require_status "$run_status" 75 \
    'helper exposes an interrupted post-write transaction to the test harness'
  if [ "$(cat "$interrupted_journal/status" 2>/dev/null || true)" = preparing ] \
    && cmp -s "$interrupted_state/entry" "$interrupted_journal/after.entry"; then
    pass 'interrupted helper leaves enough journal data for guarded recovery'
  else
    fail 'interrupted helper leaves enough journal data for guarded recovery'
  fi
  run_capture "$test_tmp/interrupted-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$interrupted_state" \
    "$helper" restore "$interrupted_journal"
  require_status "$run_status" 0 \
    'helper restores a shortcut interrupted after preference mutation'
  if [ "$(cat "$interrupted_state/entry" 2>/dev/null || true)" = \
      'shortcut before interruption' ]; then
    pass 'interrupted transaction recovery restores the previous shortcut'
  else
    fail 'interrupted transaction recovery restores the previous shortcut'
  fi
else
  fail 'helper applies the Spotlight shortcut transactionally'
  fail 'helper journals the exact before and after shortcut values'
  fail 'helper permits rollback while its applied value is current'
  fail 'helper restores a previous Spotlight shortcut'
  fail 'helper restores the exact previous shortcut value'
  fail 'helper applies when no previous shortcut entry exists'
  fail 'helper rolls back an originally absent shortcut entry'
  fail 'rollback removes only the shortcut created by the transaction'
  fail 'helper refuses to overwrite a later shortcut change'
  fail 'conflicted rollback preserves the later shortcut change'
  fail 'helper reports a failed preference write'
  fail 'failed preference write preserves the previous shortcut'
  fail 'helper rejects an unsupported preference schema'
  fail 'schema rejection occurs before preference mutation'
  fail 'helper exposes an interrupted post-write transaction to the test harness'
  fail 'interrupted helper leaves enough journal data for guarded recovery'
  fail 'helper restores a shortcut interrupted after preference mutation'
  fail 'interrupted transaction recovery restores the previous shortcut'
fi

if [ "$failures" -ne 0 ]; then
  printf '# %d test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '# all %d tests passed\n' "$tests"
