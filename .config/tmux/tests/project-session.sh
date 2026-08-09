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

assert_contains() {
  assert_pattern=$1
  assert_file=$2
  assert_label=$3
  if ! grep -F "$assert_pattern" "$assert_file" >/dev/null 2>&1; then
    fail "$assert_label: missing <$assert_pattern>"
  fi
}

assert_empty() {
  assert_file=$1
  assert_label=$2
  if [ -s "$assert_file" ]; then
    fail "$assert_label: expected an empty file"
  fi
}

script_directory=$(CDPATH='' cd -P "$(dirname "$0")" && pwd -P)
repository_root=$(CDPATH='' cd -P "$script_directory/../../.." && pwd -P)
launcher=$repository_root/.local/bin/t

[ -x "$launcher" ] || fail "launcher is not executable: $launcher"

real_tmux=$(command -v tmux) || fail "tmux is required"
real_git=$(command -v git) || fail "git is required"

unset TMUX TMUX_PANE
export SHELL=/bin/sh

test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-t-test.XXXXXX") || fail "could not create a temporary directory"
socket_path=$test_root/tmux.sock
shim_directory=$test_root/bin
attach_log=$test_root/attach.log
native_log=$test_root/native.log
stdout_file=$test_root/stdout
stderr_file=$test_root/stderr
run_status=0
run_tmux_value=

cleanup() {
  "$real_tmux" -S "$socket_path" kill-server >/dev/null 2>&1 || :
  if [ -n "${test_root-}" ] && [ "$test_root" != / ]; then
    case ${test_root##*/} in
      dotfiles-t-test.*)
        rm -rf "$test_root"
        ;;
      *)
        printf 'refusing to remove unexpected test path: %s\n' "$test_root" >&2
        ;;
    esac
  fi
}

trap cleanup 0 HUP INT TERM

mkdir -p "$shim_directory"

cat >"$shim_directory/tmux" <<'SHIM'
#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  printf '%s\n' native >>"$T_TEST_NATIVE_LOG"
  exit 0
fi

if [ "${1-}" = attach-session ]; then
  {
    printf '%s\n' attach
    shift
    for argument
    do
      printf '<%s>\n' "$argument"
    done
  } >>"$T_TEST_ATTACH_LOG"
  exit 0
fi

exec "$T_TEST_REAL_TMUX" -f /dev/null -S "$T_TEST_SOCKET" "$@"
SHIM

chmod +x "$shim_directory/tmux"

private_tmux() {
  "$real_tmux" -f /dev/null -S "$socket_path" "$@"
}

reset_logs() {
  : >"$attach_log"
  : >"$native_log"
  : >"$stdout_file"
  : >"$stderr_file"
}

run_t() {
  run_directory=$1
  shift
  reset_logs
  set +e
  (
    cd "$run_directory" || exit 125
    PATH="$shim_directory:$PATH" \
      TMUX="$run_tmux_value" \
      T_TEST_REAL_TMUX="$real_tmux" \
      T_TEST_SOCKET="$socket_path" \
      T_TEST_ATTACH_LOG="$attach_log" \
      T_TEST_NATIVE_LOG="$native_log" \
      "$launcher" "$@"
  ) >"$stdout_file" 2>"$stderr_file"
  run_status=$?
  set -e
}

init_repository() {
  init_path=$1
  mkdir -p "$init_path"
  "$real_git" init -q "$init_path"
  CDPATH='' cd -P "$init_path" && pwd -P
}

space_root=$(init_repository "$test_root/repositories/project alpha")
mkdir -p "$space_root/src/nested"

run_t "$space_root/src/nested"
assert_equal 0 "$run_status" "nested launch"
assert_equal "$space_root" "$(private_tmux display-message -p -t '=project_alpha:' '#{session_path}')" "space path session root"
assert_equal 1 "$(private_tmux list-windows -t '=project_alpha' -F '#{window_id}' | wc -l | tr -d '[:space:]')" "single window"
assert_equal 1 "$(private_tmux list-panes -t '=project_alpha' -F '#{pane_id}' | wc -l | tr -d '[:space:]')" "single pane"
expected_attach=$(printf 'attach\n<-c>\n<%s>\n<-t>\n<=project_alpha>' "$space_root")
assert_equal "$expected_attach" "$(cat "$attach_log")" "exact attach arguments"
assert_empty "$native_log" "Git launch native fallback"

run_t "$space_root"
assert_equal 0 "$run_status" "repeat launch"
assert_equal 1 "$(private_tmux list-sessions -F '#{session_name}' | wc -l | tr -d '[:space:]')" "repeat session count"
assert_contains '<=project_alpha>' "$attach_log" "repeat exact target"

shared_one_root=$(init_repository "$test_root/one/shared")
shared_two_root=$(init_repository "$test_root/two/shared")

run_t "$shared_one_root"
assert_equal 0 "$run_status" "first shared launch"
assert_equal "$shared_one_root" "$(private_tmux display-message -p -t '=shared:' '#{session_path}')" "first shared root"

shared_hash=$(printf '%s' "$shared_two_root" | "$real_git" hash-object --stdin | cut -c 1-8)
shared_collision=shared-$shared_hash
run_t "$shared_two_root"
assert_equal 0 "$run_status" "second shared launch"
assert_equal "$shared_two_root" "$(private_tmux display-message -p -t "=$shared_collision:" '#{session_path}')" "collision-safe shared root"
assert_contains "<=$shared_collision>" "$attach_log" "collision-safe attach target"

conflict_target_root=$(init_repository "$test_root/target/conflict")
conflict_base_root=$test_root/occupants/base
conflict_hash_root=$test_root/occupants/hash
mkdir -p "$conflict_base_root" "$conflict_hash_root"
conflict_hash=$(printf '%s' "$conflict_target_root" | "$real_git" hash-object --stdin | cut -c 1-8)
conflict_session=conflict-$conflict_hash
private_tmux new-session -d -s conflict -c "$conflict_base_root"
private_tmux new-session -d -s "$conflict_session" -c "$conflict_hash_root"

run_t "$conflict_target_root"
assert_equal 1 "$run_status" "conflicting collision-safe session"
assert_empty "$attach_log" "conflicting session attach"
assert_contains "t: session '$conflict_session' belongs to another project" "$stderr_file" "conflicting session diagnostic"

outside_directory=$test_root/outside
mkdir -p "$outside_directory"
run_t "$outside_directory"
assert_equal 0 "$run_status" "outside Git fallback"
assert_equal native "$(cat "$native_log")" "native tmux fallback"
assert_empty "$attach_log" "outside Git attach"

run_tmux_value=$test_root/live-looking.sock,1,0
run_t "$space_root"
run_tmux_value=
assert_equal 1 "$run_status" "inside tmux rejection"
assert_contains 't: already inside tmux' "$stderr_file" "inside tmux diagnostic"
assert_empty "$attach_log" "inside tmux attach"
assert_empty "$native_log" "inside tmux native fallback"

run_t "$space_root" --name custom
assert_equal 2 "$run_status" "argument rejection"
assert_contains 'usage: t' "$stderr_file" "argument usage"
assert_empty "$attach_log" "argument attach"
assert_empty "$native_log" "argument native fallback"

pass "project session launcher"
