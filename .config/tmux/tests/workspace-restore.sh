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

run_workspace_missing_executable() {
  missing_executable=$1
  shift
  set +e
  HOME=$test_root/home \
    SHELL=/bin/sh \
    XDG_STATE_HOME=$state \
    XDG_RUNTIME_DIR=$runtime \
    TMUX_WORKSPACE_TESTING=1 \
    TMUX_WORKSPACE_SOCKET=$socket \
    TMUX_WORKSPACE_TEST_MISSING_EXECUTABLE=$missing_executable \
    "$workspace" "$@" >"$stdout" 2>"$stderr"
  status=$?
  set -e
}

run_codex_hook() {
  hook_pane=$1
  hook_payload=$2
  set +e
  printf '%s\n' "$hook_payload" |
    HOME=$test_root/home \
      SHELL=/bin/sh \
      XDG_STATE_HOME=$state \
      XDG_RUNTIME_DIR=$runtime \
      TMUX_WORKSPACE_TESTING=1 \
      TMUX_WORKSPACE_SOCKET=$socket \
      TMUX_PANE=$hook_pane \
      "$workspace" codex-hook >"$stdout" 2>"$stderr"
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
missing_generation=missing-cwd
missing_generation_dir=$state/dotfiles/tmux/snapshots/$missing_generation
mkdir -p "$missing_generation_dir"
chmod 0700 "$missing_generation_dir"
jq --arg path "$test_root/projects/removed" '
  (.sessions[].path) = $path
  | (.panes[].path) = $path
' "$state/dotfiles/tmux/snapshots/$generation/snapshot.json" \
  >"$missing_generation_dir/snapshot.json"
chmod 0600 "$missing_generation_dir/snapshot.json"
printf '%s\n' "$missing_generation" >"$state/dotfiles/tmux/current"
run_workspace restore
[ "$status" -eq 0 ] || sed -n '1,120p' "$stderr" >&2
assert_equal 0 "$status" "missing working directory fallback restore"
assert_equal "$test_root/home" \
  "$(private_tmux list-panes -a -F '#{pane_current_path}' | sort -u)" \
  "missing working directories fall back to HOME"
assert_contains 'a saved working directory is missing; HOME was used' \
  "$state/dotfiles/tmux/last-warning" \
  "missing working directory warning"
stop_private_server
rm -rf "$missing_generation_dir"

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
"$real_tmux" -f "$script_dir/../conf/options.conf" -S "$socket" \
  new-session -d -s local-only
private_tmux rename-window -t '=local-only:1' local
private_tmux set-option -w -t '=local-only:1' automatic-rename off
session_count_before=$(private_tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')
run_workspace restore
assert_equal 0 "$status" "live server adoption"
session_count_after=$(private_tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')
assert_equal "$session_count_before" "$session_count_after" "adoption session count"
assert_equal 1 "$(private_tmux show-options -gqv @dotfiles_workspace_adopted)" \
  "adoption marker"

supervisor_stdout=$test_root/supervisor.stdout
supervisor_stderr=$test_root/supervisor.stderr
HOME=$test_root/home \
  SHELL=/bin/sh \
  XDG_STATE_HOME=$state \
  XDG_RUNTIME_DIR=$runtime \
  TMUX_WORKSPACE_TESTING=1 \
  TMUX_WORKSPACE_SOCKET=$socket \
  TMUX_WORKSPACE_INTERVAL=1 \
  "$workspace" supervise >"$supervisor_stdout" 2>"$supervisor_stderr" &
supervisor_pid=$!
wait_attempt=0
while [ ! -f "$runtime/dotfiles-tmux/ready" ] && [ "$wait_attempt" -lt 200 ]; do
  sleep 0.01
  wait_attempt=$((wait_attempt + 1))
done
[ -f "$runtime/dotfiles-tmux/ready" ] || fail "supervisor ready marker"
kill -0 "$supervisor_pid" >/dev/null 2>&1 || fail "supervisor exited before ready"
summarize >"$test_root/ready-summary"
sleep 2
summarize >"$test_root/periodic-summary"
if ! cmp -s "$test_root/ready-summary" "$test_root/periodic-summary"; then
  diff -u "$test_root/ready-summary" "$test_root/periodic-summary" >&2 || :
  fail "periodic checkpoint changed tmux topology"
fi
generation_before_stop=$(cat "$state/dotfiles/tmux/current")
if ! kill -0 "$supervisor_pid" >/dev/null 2>&1; then
  sed -n '1,120p' "$supervisor_stderr" >&2
  fail "supervisor exited before clean stop"
fi
kill -TERM "$supervisor_pid"
wait "$supervisor_pid"
generation_after_stop=$(cat "$state/dotfiles/tmux/current")
[ "$generation_before_stop" != "$generation_after_stop" ] \
  || fail "supervisor final checkpoint did not advance generation"
[ ! -e "$runtime/dotfiles-tmux/supervisor.lock" ] \
  || fail "supervisor lock remained after clean stop"

stop_private_server
rm -f "$runtime/dotfiles-tmux/ready"
set +e
HOME=$test_root/home SHELL=/bin/sh XDG_STATE_HOME=$state XDG_RUNTIME_DIR=$runtime \
  TMUX_WORKSPACE_TESTING=1 TMUX_WORKSPACE_SOCKET=$socket \
  "$workspace" ensure >"$test_root/ensure-one.stdout" 2>"$test_root/ensure-one.stderr" &
ensure_one_pid=$!
HOME=$test_root/home SHELL=/bin/sh XDG_STATE_HOME=$state XDG_RUNTIME_DIR=$runtime \
  TMUX_WORKSPACE_TESTING=1 TMUX_WORKSPACE_SOCKET=$socket \
  "$workspace" ensure >"$test_root/ensure-two.stdout" 2>"$test_root/ensure-two.stderr" &
ensure_two_pid=$!
wait "$ensure_one_pid"
ensure_one_status=$?
wait "$ensure_two_pid"
ensure_two_status=$?
set -e
assert_equal 0 "$ensure_one_status" "first concurrent ensure"
assert_equal 0 "$ensure_two_status" "second concurrent ensure"
[ -f "$runtime/dotfiles-tmux/ready" ] || fail "concurrent ensure ready marker"
assert_equal 1 \
  "$(private_tmux list-sessions -F '#{session_id}' | wc -l | tr -d '[:space:]')" \
  "single restored session after concurrent ensure"
assert_equal "$(cat "$runtime/dotfiles-tmux/ready")" \
  "$(private_tmux show-options -gqv @dotfiles_workspace_generation)" \
  "ready marker matches restored generation"

stop_private_server
shim_directory=$test_root/bin
codex_log_directory=$test_root/codex-logs
mkdir -p "$shim_directory" "$codex_log_directory" \
  "$test_root/home/.config/tmux/scripts"
ln -s "$workspace" "$test_root/home/.config/tmux/scripts/workspace"
cp "$(command -v sleep)" "$shim_directory/codex"
chmod 0755 "$shim_directory/codex"
PATH=$shim_directory:$PATH
CODEX_TEST_LOG_DIRECTORY=$codex_log_directory
export PATH CODEX_TEST_LOG_DIRECTORY

"$real_tmux" -f "$script_dir/../conf/options.conf" -S "$socket" \
  new-session -d -s codex-work -c "$test_root/projects/alpha" \
  -n conversations 'codex 300'
private_tmux split-window -d -t '=codex-work:1' \
  -c "$test_root/projects/alpha" 'codex 300'
codex_alpha_pane=$(private_tmux display-message -p -t '=codex-work:1.1' '#{pane_id}')
codex_beta_pane=$(private_tmux display-message -p -t '=codex-work:1.2' '#{pane_id}')
wait_attempt=0
alpha_command=
beta_command=
while [ "$wait_attempt" -lt 200 ]; do
  alpha_command=$(private_tmux display-message -p \
    -t "$codex_alpha_pane" '#{pane_current_command}')
  beta_command=$(private_tmux display-message -p \
    -t "$codex_beta_pane" '#{pane_current_command}')
  [ "$alpha_command" = codex ] && [ "$beta_command" = codex ] && break
  sleep 0.01
  wait_attempt=$((wait_attempt + 1))
done
assert_equal codex \
  "$alpha_command" \
  "alpha pane command"
assert_equal codex \
  "$beta_command" \
  "beta pane command"

alpha_payload='{"session_id":"thr_alpha","transcript_path":"/ignored/a.jsonl","cwd":"/same","hook_event_name":"SessionStart","model":"gpt-5.6-sol","source":"startup"}'
beta_payload='{"session_id":"thr_beta","transcript_path":"/ignored/b.jsonl","cwd":"/same","hook_event_name":"SessionStart","model":"gpt-5.6-sol","source":"resume"}'
run_codex_hook "$codex_alpha_pane" "$alpha_payload"
assert_equal 0 "$status" "alpha SessionStart hook"
[ ! -s "$stdout" ] || fail "SessionStart hook wrote model context"
run_codex_hook "$codex_beta_pane" "$beta_payload"
assert_equal 0 "$status" "beta SessionStart hook"
assert_equal thr_alpha \
  "$(private_tmux show-options -pqv -t "$codex_alpha_pane" @dotfiles_codex_session_id)" \
  "alpha pane exact session"
assert_equal thr_beta \
  "$(private_tmux show-options -pqv -t "$codex_beta_pane" @dotfiles_codex_session_id)" \
  "beta pane exact session"

stale_end='{"session_id":"thr_stale","transcript_path":"/ignored/stale.jsonl","cwd":"/same","hook_event_name":"SessionEnd","model":"gpt-5.6-sol","reason":"other"}'
run_codex_hook "$codex_alpha_pane" "$stale_end"
assert_equal 0 "$status" "stale SessionEnd hook"
assert_equal thr_alpha \
  "$(private_tmux show-options -pqv -t "$codex_alpha_pane" @dotfiles_codex_session_id)" \
  "stale SessionEnd preserves current conversation"
alpha_end='{"session_id":"thr_alpha","transcript_path":"/ignored/a.jsonl","cwd":"/same","hook_event_name":"SessionEnd","model":"gpt-5.6-sol","reason":"other"}'
run_codex_hook "$codex_alpha_pane" "$alpha_end"
assert_equal 0 "$status" "matching SessionEnd hook"
assert_equal '' \
  "$(private_tmux show-options -pqv -t "$codex_alpha_pane" @dotfiles_codex_session_id)" \
  "matching SessionEnd clears identifier"
run_codex_hook "$codex_alpha_pane" "$alpha_payload"
assert_equal 0 "$status" "alpha SessionStart re-registration"

run_workspace save
assert_equal 0 "$status" "Codex metadata checkpoint"
codex_generation=$(cat "$state/dotfiles/tmux/current")
codex_manifest=$state/dotfiles/tmux/snapshots/$codex_generation/snapshot.json
jq -e '
  any(.panes[]; .process.kind == "codex" and .process.codex_session_id == "thr_alpha")
  and any(.panes[]; .process.kind == "codex" and .process.codex_session_id == "thr_beta")
' "$codex_manifest" >/dev/null || fail "distinct same-cwd Codex metadata"

private_tmux set-option -pu -t "$codex_beta_pane" @dotfiles_codex_session_id
run_workspace save
assert_equal 0 "$status" "Codex picker fallback checkpoint"
codex_generation=$(cat "$state/dotfiles/tmux/current")
codex_manifest=$state/dotfiles/tmux/snapshots/$codex_generation/snapshot.json
jq -e '
  any(.panes[]; .process.kind == "codex" and .process.codex_session_id == "thr_alpha")
  and any(.panes[]; .process.kind == "codex" and .process.codex_session_id == null)
' "$codex_manifest" >/dev/null || fail "Codex picker fallback metadata"

stop_private_server
cat >"$shim_directory/codex" <<'SHIM'
#!/bin/sh
set -eu

case $* in
  'resume thr_alpha') output=$CODEX_TEST_LOG_DIRECTORY/alpha ;;
  'resume') output=$CODEX_TEST_LOG_DIRECTORY/picker ;;
  *) output=$CODEX_TEST_LOG_DIRECTORY/unexpected ;;
esac
for argument
do
  printf '%s\n' "$argument"
done >"$output"
SHIM
chmod 0755 "$shim_directory/codex"
run_workspace restore
[ "$status" -eq 0 ] || sed -n '1,120p' "$stderr" >&2
assert_equal 0 "$status" "Codex process restore"
wait_attempt=0
while { [ ! -f "$codex_log_directory/alpha" ] \
  || [ ! -f "$codex_log_directory/picker" ]; } \
  && [ "$wait_attempt" -lt 200 ]; do
  sleep 0.01
  wait_attempt=$((wait_attempt + 1))
done
[ -f "$codex_log_directory/alpha" ] || fail "exact Codex resume call"
[ -f "$codex_log_directory/picker" ] || fail "Codex picker resume call"
assert_equal "$(printf 'resume\nthr_alpha')" \
  "$(cat "$codex_log_directory/alpha")" \
  "exact Codex resume argv"
assert_equal resume "$(cat "$codex_log_directory/picker")" \
  "Codex picker argv"
[ ! -e "$codex_log_directory/unexpected" ] || fail "unexpected Codex resume argv"
if grep -R -F '/ignored/a.jsonl' "$state/dotfiles/tmux" >/dev/null 2>&1 \
  || grep -R -F '/ignored/b.jsonl' "$state/dotfiles/tmux" >/dev/null 2>&1; then
  fail "Codex transcript path entered persistence state"
fi

stop_private_server
rm -f "$codex_log_directory/alpha" "$codex_log_directory/picker"
run_workspace_missing_executable codex restore
[ "$status" -eq 0 ] || sed -n '1,120p' "$stderr" >&2
assert_equal 0 "$status" "missing Codex executable restore"
assert_equal sh \
  "$(private_tmux list-panes -a -F '#{pane_current_command}' | sort -u)" \
  "missing Codex leaves restored shells open"
assert_contains 'codex is unavailable; the restored shell was left open' \
  "$state/dotfiles/tmux/last-warning" \
  "missing Codex warning"
[ ! -e "$codex_log_directory/alpha" ] \
  && [ ! -e "$codex_log_directory/picker" ] \
  || fail "missing Codex restore dispatched a process"

stop_private_server
real_nvim=$(command -v nvim) || fail "nvim is required"
nvim_project=$test_root/projects/nvim
mkdir -p "$nvim_project"
printf '%s\n' "return 'first'" >"$nvim_project/first.lua"
printf '%s\n' "return 'second'" >"$nvim_project/second.lua"
NVIM_TEST_REAL=$real_nvim
NVIM_TEST_CONFIG=$script_dir/../../nvim
NVIM_TEST_FIRST=$nvim_project/first.lua
NVIM_TEST_SECOND=$nvim_project/second.lua
export NVIM_TEST_REAL NVIM_TEST_CONFIG NVIM_TEST_FIRST NVIM_TEST_SECOND
cat >"$shim_directory/nvim-source" <<'SHIM'
#!/bin/sh
set -eu
exec "$NVIM_TEST_REAL" -i NONE -u NONE \
  --cmd "set runtimepath^=$NVIM_TEST_CONFIG" \
  --cmd "lua require('integrations.tmux_persistence').setup()" \
  -c "edit $NVIM_TEST_FIRST" \
  -c "vsplit $NVIM_TEST_SECOND"
SHIM
chmod 0755 "$shim_directory/nvim-source"
HOME=$test_root/home XDG_STATE_HOME=$state XDG_RUNTIME_DIR=$runtime \
  PATH=$PATH "$real_tmux" -f "$script_dir/../conf/options.conf" -S "$socket" \
  new-session -d -s nvim-work -c "$nvim_project" -n editor nvim-source
nvim_pane=$(private_tmux display-message -p -t '=nvim-work:1.1' '#{pane_id}')
wait_attempt=0
nvim_server=
while [ "$wait_attempt" -lt 300 ]; do
  nvim_server=$(private_tmux show-options -pqv -t "$nvim_pane" \
    @dotfiles_nvim_server 2>/dev/null || :)
  [ -n "$nvim_server" ] && break
  sleep 0.01
  wait_attempt=$((wait_attempt + 1))
done
[ -n "$nvim_server" ] || fail "Neovim RPC registration"
assert_equal nvim \
  "$(private_tmux display-message -p -t "$nvim_pane" '#{pane_current_command}')" \
  "Neovim pane command"

run_workspace save
[ "$status" -eq 0 ] || sed -n '1,120p' "$stderr" >&2
assert_equal 0 "$status" "Neovim metadata checkpoint"
nvim_generation=$(cat "$state/dotfiles/tmux/current")
nvim_manifest=$state/dotfiles/tmux/snapshots/$nvim_generation/snapshot.json
nvim_relative=$(jq -er '
  .panes[]
  | select(.process.kind == "nvim")
  | .process.nvim_session
' "$nvim_manifest") || fail "native Neovim session metadata"
nvim_session_file=$state/dotfiles/tmux/snapshots/$nvim_generation/$nvim_relative
[ -s "$nvim_session_file" ] || fail "native Neovim session file"
assert_equal 600 "$(stat -c %a "$nvim_session_file")" "native Neovim session mode"

private_tmux set-option -pt "$nvim_pane" \
  @dotfiles_nvim_server "$test_root/missing-nvim.sock"
run_workspace save
assert_equal 0 "$status" "failed Neovim RPC checkpoint"
failed_nvim_generation=$(cat "$state/dotfiles/tmux/current")
failed_nvim_manifest=$state/dotfiles/tmux/snapshots/$failed_nvim_generation/snapshot.json
jq -e '
  any(.panes[];
    .process.kind == "nvim" and .process.nvim_session == null)
' "$failed_nvim_manifest" >/dev/null \
  || fail "failed Neovim RPC fallback metadata"
assert_contains 'a Neovim checkpoint RPC failed; a clean editor will be restored' \
  "$state/dotfiles/tmux/last-warning" \
  "failed Neovim RPC warning"
printf '%s\n' "$nvim_generation" >"$state/dotfiles/tmux/current"

stop_private_server
cat >"$shim_directory/nvim" <<'SHIM'
#!/bin/sh
set -eu
for argument
do
  printf '%s\n' "$argument"
done >"$CODEX_TEST_LOG_DIRECTORY/nvim"
SHIM
chmod 0755 "$shim_directory/nvim"
run_workspace restore
[ "$status" -eq 0 ] || sed -n '1,120p' "$stderr" >&2
assert_equal 0 "$status" "Neovim process restore"
wait_attempt=0
while [ ! -f "$codex_log_directory/nvim" ] && [ "$wait_attempt" -lt 200 ]; do
  sleep 0.01
  wait_attempt=$((wait_attempt + 1))
done
[ -f "$codex_log_directory/nvim" ] || fail "Neovim restore argv"
assert_equal "$(printf '%s\n%s' -S "$nvim_session_file")" \
  "$(cat "$codex_log_directory/nvim")" \
  "native Neovim restore argv"

nvim_pane_key=$(jq -er '
  .panes[] | select(.process.kind == "nvim") | .key
' "$nvim_manifest")
mv "$nvim_session_file" "$nvim_session_file.private"
ln -s "$nvim_session_file.private" "$nvim_session_file"
rm -f "$codex_log_directory/nvim"
run_workspace resume-pane "$nvim_generation" "$nvim_pane_key"
assert_equal 0 "$status" "symlinked Neovim session fallback"
[ -f "$codex_log_directory/nvim" ] || fail "symlink fallback Neovim invocation"
assert_equal '' "$(cat "$codex_log_directory/nvim")" \
  "symlinked Neovim session starts a clean editor"
rm -f "$nvim_session_file"
mv "$nvim_session_file.private" "$nvim_session_file"

chmod 0644 "$nvim_session_file"
rm -f "$codex_log_directory/nvim"
run_workspace resume-pane "$nvim_generation" "$nvim_pane_key"
assert_equal 0 "$status" "world-readable Neovim session fallback"
[ -f "$codex_log_directory/nvim" ] \
  || fail "world-readable fallback Neovim invocation"
assert_equal '' "$(cat "$codex_log_directory/nvim")" \
  "world-readable Neovim session starts a clean editor"
chmod 0600 "$nvim_session_file"

pass "workspace structural restore"
