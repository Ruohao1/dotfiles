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
