#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
dotfiles_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
workspace_root=$(CDPATH='' cd -- "$dotfiles_dir/../.." && pwd)
helper=$workspace_root/.config/macos/window-drag-gesture

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

test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-window-drag-test.XXXXXX")
cleanup() {
  case "$test_tmp" in
    "${TMPDIR:-/tmp}"/dotfiles-window-drag-test.*) rm -rf "$test_tmp" ;;
  esac
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -x "$helper" ]; then
  pass 'window-drag preference helper is executable'
else
  fail 'window-drag preference helper is executable'
fi

if [ -r "$helper" ] && sh -n "$helper"; then
  pass 'window-drag preference helper has valid POSIX shell syntax'
else
  fail 'window-drag preference helper has valid POSIX shell syntax'
fi

if [ -x "$helper" ]; then
  initializing_state=$test_tmp/initializing-state
  initializing_journal=$test_tmp/initializing-journal
  mkdir -p "$initializing_state"
  printf '%s\n' false >"$initializing_state/value"
  run_capture "$test_tmp/initializing-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$initializing_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_TERM_AFTER_JOURNAL_CREATE=1 \
    "$helper" apply "$initializing_journal"
  require_status "$run_status" 143 \
    'helper surfaces TERM during journal initialization'
  if [ "$(cat "$initializing_state/value" 2>/dev/null || true)" = false ] \
    && [ ! -e "$initializing_journal" ]; then
    pass 'initialization interruption preserves state and removes the empty journal'
  else
    fail 'initialization interruption preserves state and removes the empty journal'
  fi

  present_state=$test_tmp/present-state
  present_journal=$test_tmp/present-journal
  mkdir -p "$present_state"
  printf '%s\n' false >"$present_state/value"
  run_capture "$test_tmp/present-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$present_state" \
    "$helper" apply "$present_journal"
  require_status "$run_status" 0 'helper enables an existing false preference'
  if [ "$(cat "$present_state/value" 2>/dev/null || true)" = true ] \
    && [ "$(cat "$present_journal/before.value" 2>/dev/null || true)" = false ] \
    && [ -f "$present_journal/before.present" ] \
    && [ "$(cat "$present_journal/after.value" 2>/dev/null || true)" = true ] \
    && [ "$(cat "$present_journal/status" 2>/dev/null || true)" = applied ]; then
    pass 'helper journals exact present before and after values'
  else
    fail 'helper journals exact present before and after values'
  fi
  run_capture "$test_tmp/present-can-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$present_state" \
    "$helper" can-restore "$present_journal"
  require_status "$run_status" 0 'helper permits rollback while its applied value is current'
  run_capture "$test_tmp/present-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$present_state" \
    "$helper" restore "$present_journal"
  require_status "$run_status" 0 'helper restores an existing false preference'
  if [ "$(cat "$present_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$present_journal/status" 2>/dev/null || true)" = restored ]; then
    pass 'rollback restores the exact previous Boolean value'
  else
    fail 'rollback restores the exact previous Boolean value'
  fi

  absent_state=$test_tmp/absent-state
  absent_journal=$test_tmp/absent-journal
  mkdir -p "$absent_state"
  run_capture "$test_tmp/absent-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$absent_state" \
    "$helper" apply "$absent_journal"
  require_status "$run_status" 0 'helper enables an initially absent preference'
  run_capture "$test_tmp/absent-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$absent_state" \
    "$helper" restore "$absent_journal"
  require_status "$run_status" 0 'helper rolls back an initially absent preference'
  if [ ! -e "$absent_state/value" ] \
    && [ ! -e "$absent_journal/before.present" ]; then
    pass 'rollback removes only the preference created by the transaction'
  else
    fail 'rollback removes only the preference created by the transaction'
  fi

  enabled_state=$test_tmp/enabled-state
  enabled_journal=$test_tmp/enabled-journal
  mkdir -p "$enabled_state"
  printf '%s\n' true >"$enabled_state/value"
  run_capture "$test_tmp/enabled-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$enabled_state" \
    "$helper" apply "$enabled_journal"
  require_status "$run_status" 0 'helper apply is idempotent when the preference is already true'
  run_capture "$test_tmp/enabled-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$enabled_state" \
    "$helper" restore "$enabled_journal"
  require_status "$run_status" 0 'helper restores an initially true preference'
  if [ "$(cat "$enabled_state/value" 2>/dev/null || true)" = true ]; then
    pass 'idempotent apply and rollback preserve an initially true value'
  else
    fail 'idempotent apply and rollback preserve an initially true value'
  fi

  changed_state=$test_tmp/changed-state
  changed_journal=$test_tmp/changed-journal
  mkdir -p "$changed_state"
  run_capture "$test_tmp/changed-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$changed_state" \
    "$helper" apply "$changed_journal"
  printf '%s\n' false >"$changed_state/value"
  run_capture "$test_tmp/changed-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$changed_state" \
    "$helper" restore "$changed_journal"
  require_status "$run_status" 3 'helper refuses to overwrite a later preference change'
  if [ "$(cat "$changed_state/value")" = false ] \
    && [ "$(cat "$changed_journal/status" 2>/dev/null || true)" = applied ]; then
    pass 'conflicted rollback preserves the later value and applied journal'
  else
    fail 'conflicted rollback preserves the later value and applied journal'
  fi

  race_state=$test_tmp/race-state
  race_journal=$test_tmp/race-journal
  mkdir -p "$race_state"
  printf '%s\n' false >"$race_state/value"
  run_capture "$test_tmp/race-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$race_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_CHANGE_BEFORE_WRITE=absent \
    "$helper" apply "$race_journal"
  require_status "$run_status" 3 'helper detects a change immediately before its write'
  if [ ! -e "$race_state/value" ]; then
    pass 'pre-write conflict preserves the concurrently changed state'
  else
    fail 'pre-write conflict preserves the concurrently changed state'
  fi
  if [ "$(cat "$race_journal/status" 2>/dev/null || true)" = failed ]; then
    pass 'pre-write conflict records a failed no-op journal'
  else
    fail 'pre-write conflict records a failed no-op journal'
  fi
  run_capture "$test_tmp/race-can-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$race_state" \
    "$helper" can-restore "$race_journal"
  require_status "$run_status" 0 \
    'failed pre-write conflict does not block transaction rollback'
  run_capture "$test_tmp/race-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$race_state" \
    "$helper" restore "$race_journal"
  require_status "$run_status" 0 \
    'failed pre-write conflict rollback is a no-op'
  if [ ! -e "$race_state/value" ]; then
    pass 'failed conflict rollback preserves the concurrent absent state'
  else
    fail 'failed conflict rollback preserves the concurrent absent state'
  fi

  initial_read_state=$test_tmp/initial-read-state
  initial_read_journal=$test_tmp/initial-read-journal
  mkdir -p "$initial_read_state"
  printf '%s\n' false >"$initial_read_state/value"
  run_capture "$test_tmp/initial-read-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$initial_read_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_FAIL_READ_AT=1 \
    "$helper" apply "$initial_read_journal"
  require_status "$run_status" 1 \
    'helper preserves an operational initial read failure as status 1'
  if [ "$(cat "$initial_read_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$initial_read_journal/status" 2>/dev/null || true)" = failed ] \
    && [ ! -e "$initial_read_journal/after.value" ]; then
    pass 'operational initial read failure preserves state and records failed'
  else
    fail 'operational initial read failure preserves state and records failed'
  fi

  read_failure_state=$test_tmp/read-failure-state
  read_failure_journal=$test_tmp/read-failure-journal
  mkdir -p "$read_failure_state"
  printf '%s\n' false >"$read_failure_state/value"
  run_capture "$test_tmp/read-failure-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$read_failure_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_FAIL_READ_AT=2 \
    "$helper" apply "$read_failure_journal"
  require_status "$run_status" 1 \
    'helper preserves an operational pre-write read failure as status 1'
  if [ "$(cat "$read_failure_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$read_failure_journal/status" 2>/dev/null || true)" = failed ]; then
    pass 'operational pre-write failure preserves state and records failed'
  else
    fail 'operational pre-write failure preserves state and records failed'
  fi
  run_capture "$test_tmp/read-failure-can-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$read_failure_state" \
    "$helper" can-restore "$read_failure_journal"
  require_status "$run_status" 0 \
    'operational pre-write failure does not block transaction rollback'
  run_capture "$test_tmp/read-failure-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$read_failure_state" \
    "$helper" restore "$read_failure_journal"
  require_status "$run_status" 0 \
    'operational pre-write failure rollback is a no-op'

  failure_state=$test_tmp/failure-state
  failure_journal=$test_tmp/failure-journal
  mkdir -p "$failure_state"
  printf '%s\n' false >"$failure_state/value"
  run_capture "$test_tmp/failure-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$failure_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_FAIL_WRITE=1 \
    "$helper" apply "$failure_journal"
  require_status "$run_status" 1 \
    'helper reports a deterministic preference write failure as status 1'
  if [ "$(cat "$failure_state/value")" = false ]; then
    pass 'failed preference write preserves the previous value'
  else
    fail 'failed preference write preserves the previous value'
  fi
  if [ "$(cat "$failure_journal/status" 2>/dev/null || true)" = failed ]; then
    pass 'deterministic pre-write failure records a failed journal'
  else
    fail 'deterministic pre-write failure records a failed journal'
  fi

  verify_read_state=$test_tmp/verify-read-state
  verify_read_journal=$test_tmp/verify-read-journal
  mkdir -p "$verify_read_state"
  printf '%s\n' false >"$verify_read_state/value"
  run_capture "$test_tmp/verify-read-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$verify_read_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_FAIL_READ_AT=3 \
    "$helper" apply "$verify_read_journal"
  require_status "$run_status" 1 \
    'post-write verification read failure remains operational'
  if [ "$(cat "$verify_read_state/value" 2>/dev/null || true)" = true ] \
    && [ "$(cat "$verify_read_journal/status" 2>/dev/null || true)" = preparing ]; then
    pass 'verification read failure leaves a recoverable preparing journal'
  else
    fail 'verification read failure leaves a recoverable preparing journal'
  fi
  run_capture "$test_tmp/verify-read-can-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$verify_read_state" \
    "$helper" can-restore "$verify_read_journal"
  require_status "$run_status" 0 \
    'verification read failure permits guarded rollback'
  run_capture "$test_tmp/verify-read-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$verify_read_state" \
    "$helper" restore "$verify_read_journal"
  require_status "$run_status" 0 \
    'verification read failure restores the previous value'
  if [ "$(cat "$verify_read_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$verify_read_journal/status" 2>/dev/null || true)" = restored ]; then
    pass 'verification read recovery finalizes the restored journal'
  else
    fail 'verification read recovery finalizes the restored journal'
  fi

  verify_conflict_state=$test_tmp/verify-conflict-state
  verify_conflict_journal=$test_tmp/verify-conflict-journal
  mkdir -p "$verify_conflict_state"
  printf '%s\n' false >"$verify_conflict_state/value"
  run_capture "$test_tmp/verify-conflict-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$verify_conflict_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_CHANGE_AFTER_WRITE=absent \
    "$helper" apply "$verify_conflict_journal"
  require_status "$run_status" 3 \
    'post-write state mismatch remains a conflict'
  if [ ! -e "$verify_conflict_state/value" ] \
    && [ "$(cat "$verify_conflict_journal/status" 2>/dev/null || true)" = preparing ]; then
    pass 'post-write conflict preserves the later state and preparing journal'
  else
    fail 'post-write conflict preserves the later state and preparing journal'
  fi
  run_capture "$test_tmp/verify-conflict-can-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$verify_conflict_state" \
    "$helper" can-restore "$verify_conflict_journal"
  require_status "$run_status" 3 \
    'post-write conflict blocks guarded rollback'
  run_capture "$test_tmp/verify-conflict-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$verify_conflict_state" \
    "$helper" restore "$verify_conflict_journal"
  require_status "$run_status" 3 \
    'post-write conflict blocks restore mutation'
  if [ ! -e "$verify_conflict_state/value" ] \
    && [ "$(cat "$verify_conflict_journal/status" 2>/dev/null || true)" = preparing ]; then
    pass 'blocked post-write rollback preserves state and journal'
  else
    fail 'blocked post-write rollback preserves state and journal'
  fi

  uncertain_state=$test_tmp/uncertain-state
  uncertain_journal=$test_tmp/uncertain-journal
  mkdir -p "$uncertain_state"
  printf '%s\n' false >"$uncertain_state/value"
  run_capture "$test_tmp/uncertain-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$uncertain_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_WRITE_THEN_FAIL=1 \
    "$helper" apply "$uncertain_journal"
  require_status "$run_status" 1 \
    'helper reports an uncertain write outcome as operational failure'
  if [ "$(cat "$uncertain_state/value" 2>/dev/null || true)" = true ] \
    && [ "$(cat "$uncertain_journal/status" 2>/dev/null || true)" = preparing ]; then
    pass 'uncertain write leaves a recoverable preparing journal'
  else
    fail 'uncertain write leaves a recoverable preparing journal'
  fi
  run_capture "$test_tmp/uncertain-can-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$uncertain_state" \
    "$helper" can-restore "$uncertain_journal"
  require_status "$run_status" 0 \
    'helper permits rollback after an uncertain write outcome'
  run_capture "$test_tmp/uncertain-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$uncertain_state" \
    "$helper" restore "$uncertain_journal"
  require_status "$run_status" 0 \
    'helper restores after an uncertain write outcome'
  if [ "$(cat "$uncertain_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$uncertain_journal/status" 2>/dev/null || true)" = restored ]; then
    pass 'uncertain write recovery restores the exact previous value'
  else
    fail 'uncertain write recovery restores the exact previous value'
  fi

  restore_retry_state=$test_tmp/restore-retry-state
  restore_retry_journal=$test_tmp/restore-retry-journal
  mkdir -p "$restore_retry_state"
  printf '%s\n' false >"$restore_retry_state/value"
  run_capture "$test_tmp/restore-retry-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$restore_retry_state" \
    "$helper" apply "$restore_retry_journal"
  require_status "$run_status" 0 \
    'helper prepares a transaction for interrupted restore recovery'
  run_capture "$test_tmp/restore-retry-first.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$restore_retry_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STOP_AFTER_RESTORE_WRITE=1 \
    "$helper" restore "$restore_retry_journal"
  require_status "$run_status" 75 \
    'helper exposes an interruption after the restore write'
  if [ "$(cat "$restore_retry_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$restore_retry_journal/status" 2>/dev/null || true)" = preparing ]; then
    pass 'interrupted restore leaves the exact before value recoverable'
  else
    fail 'interrupted restore leaves the exact before value recoverable'
  fi
  run_capture "$test_tmp/restore-retry-second.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$restore_retry_state" \
    "$helper" restore "$restore_retry_journal"
  require_status "$run_status" 0 \
    'helper retries an interrupted restore as an already-restored no-op'
  if [ "$(cat "$restore_retry_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$restore_retry_journal/status" 2>/dev/null || true)" = restored ]; then
    pass 'restore retry finalizes the journal without changing state'
  else
    fail 'restore retry finalizes the journal without changing state'
  fi

  invalid_state=$test_tmp/invalid-state
  invalid_journal=$test_tmp/invalid-journal
  mkdir -p "$invalid_state"
  printf '%s\n' invalid >"$invalid_state/value"
  run_capture "$test_tmp/invalid-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$invalid_state" \
    "$helper" apply "$invalid_journal"
  require_status "$run_status" 1 \
    'helper rejects a non-Boolean preference value as status 1'
  if [ "$(cat "$invalid_state/value")" = invalid ]; then
    pass 'schema rejection occurs before preference mutation'
  else
    fail 'schema rejection occurs before preference mutation'
  fi
  if [ "$(cat "$invalid_journal/status" 2>/dev/null || true)" = failed ]; then
    pass 'schema rejection records a failed journal'
  else
    fail 'schema rejection records a failed journal'
  fi

  string_state=$test_tmp/string-state
  string_journal=$test_tmp/string-journal
  mkdir -p "$string_state"
  printf '%s\n' true >"$string_state/value"
  run_capture "$test_tmp/string-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$string_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_INVALID_TYPE=1 \
    "$helper" apply "$string_journal"
  require_status "$run_status" 1 \
    'helper rejects a string true value as non-Boolean'
  if [ "$(cat "$string_state/value" 2>/dev/null || true)" = true ] \
    && [ "$(cat "$string_journal/status" 2>/dev/null || true)" = failed ]; then
    pass 'string true rejection preserves state and records failed'
  else
    fail 'string true rejection preserves state and records failed'
  fi

  interrupted_state=$test_tmp/interrupted-state
  interrupted_journal=$test_tmp/interrupted-journal
  mkdir -p "$interrupted_state"
  printf '%s\n' false >"$interrupted_state/value"
  run_capture "$test_tmp/interrupted-apply.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$interrupted_state" \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STOP_AFTER_WRITE=1 \
    "$helper" apply "$interrupted_journal"
  require_status "$run_status" 75 'helper exposes an interrupted post-write transaction'
  if [ "$(cat "$interrupted_state/value" 2>/dev/null || true)" = true ] \
    && [ "$(cat "$interrupted_journal/status" 2>/dev/null || true)" = preparing ]; then
    pass 'interrupted apply leaves a recoverable journal and applied value'
  else
    fail 'interrupted apply leaves a recoverable journal and applied value'
  fi
  run_capture "$test_tmp/interrupted-restore.output" env \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$interrupted_state" \
    "$helper" restore "$interrupted_journal"
  require_status "$run_status" 0 'helper restores an interrupted post-write transaction'
  if [ "$(cat "$interrupted_state/value" 2>/dev/null || true)" = false ] \
    && [ "$(cat "$interrupted_journal/status" 2>/dev/null || true)" = restored ]; then
    pass 'interrupted recovery restores the previous value and journal'
  else
    fail 'interrupted recovery restores the previous value and journal'
  fi
else
  fail 'helper surfaces TERM during journal initialization'
  fail 'initialization interruption preserves state and removes the empty journal'
  fail 'helper enables an existing false preference'
  fail 'helper journals exact present before and after values'
  fail 'helper permits rollback while its applied value is current'
  fail 'helper restores an existing false preference'
  fail 'rollback restores the exact previous Boolean value'
  fail 'helper enables an initially absent preference'
  fail 'helper rolls back an initially absent preference'
  fail 'rollback removes only the preference created by the transaction'
  fail 'helper apply is idempotent when the preference is already true'
  fail 'helper restores an initially true preference'
  fail 'idempotent apply and rollback preserve an initially true value'
  fail 'helper refuses to overwrite a later preference change'
  fail 'conflicted rollback preserves the later value and applied journal'
  fail 'helper detects a change immediately before its write'
  fail 'pre-write conflict preserves the concurrently changed state'
  fail 'pre-write conflict records a failed no-op journal'
  fail 'failed pre-write conflict does not block transaction rollback'
  fail 'failed pre-write conflict rollback is a no-op'
  fail 'failed conflict rollback preserves the concurrent absent state'
  fail 'helper preserves an operational initial read failure as status 1'
  fail 'operational initial read failure preserves state and records failed'
  fail 'helper preserves an operational pre-write read failure as status 1'
  fail 'operational pre-write failure preserves state and records failed'
  fail 'operational pre-write failure does not block transaction rollback'
  fail 'operational pre-write failure rollback is a no-op'
  fail 'helper reports a deterministic preference write failure as status 1'
  fail 'failed preference write preserves the previous value'
  fail 'deterministic pre-write failure records a failed journal'
  fail 'post-write verification read failure remains operational'
  fail 'verification read failure leaves a recoverable preparing journal'
  fail 'verification read failure permits guarded rollback'
  fail 'verification read failure restores the previous value'
  fail 'verification read recovery finalizes the restored journal'
  fail 'post-write state mismatch remains a conflict'
  fail 'post-write conflict preserves the later state and preparing journal'
  fail 'post-write conflict blocks guarded rollback'
  fail 'post-write conflict blocks restore mutation'
  fail 'blocked post-write rollback preserves state and journal'
  fail 'helper reports an uncertain write outcome as operational failure'
  fail 'uncertain write leaves a recoverable preparing journal'
  fail 'helper permits rollback after an uncertain write outcome'
  fail 'helper restores after an uncertain write outcome'
  fail 'uncertain write recovery restores the exact previous value'
  fail 'helper prepares a transaction for interrupted restore recovery'
  fail 'helper exposes an interruption after the restore write'
  fail 'interrupted restore leaves the exact before value recoverable'
  fail 'helper retries an interrupted restore as an already-restored no-op'
  fail 'restore retry finalizes the journal without changing state'
  fail 'helper rejects a non-Boolean preference value as status 1'
  fail 'schema rejection occurs before preference mutation'
  fail 'schema rejection records a failed journal'
  fail 'helper rejects a string true value as non-Boolean'
  fail 'string true rejection preserves state and records failed'
  fail 'helper exposes an interrupted post-write transaction'
  fail 'interrupted apply leaves a recoverable journal and applied value'
  fail 'helper restores an interrupted post-write transaction'
  fail 'interrupted recovery restores the previous value and journal'
fi

if [ "$failures" -ne 0 ]; then
  printf '1..%d\n' "$tests"
  printf '# %d test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '1..%d\n' "$tests"
printf '# all %d tests passed\n' "$tests"
