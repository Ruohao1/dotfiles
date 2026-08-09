#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
dotfiles_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
workspace_root=$(CDPATH='' cd -- "$dotfiles_dir/../.." && pwd)
bootstrap=$dotfiles_dir/bootstrap
checker=$dotfiles_dir/check-window-managers

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

require_contains() {
  haystack=$1
  needle=$2
  label=$3
  case "$haystack" in
    *"$needle"*) pass "$label" ;;
    *)
      fail "$label"
      printf '  missing: %s\n' "$needle" >&2
      ;;
  esac
}

require_excludes() {
  haystack=$1
  needle=$2
  label=$3
  case "$haystack" in
    *"$needle"*)
      fail "$label"
      printf '  unexpected: %s\n' "$needle" >&2
      ;;
    *) pass "$label" ;;
  esac
}

run_capture() {
  output_file=$1
  shift
  set +e
  "$@" >"$output_file" 2>&1
  run_status=$?
  set -e
}

test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-window-managers-test.XXXXXX")
cleanup() {
  case "$test_tmp" in
    "${TMPDIR:-/tmp}"/dotfiles-window-managers-test.*) rm -rf "$test_tmp" ;;
  esac
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

for required_file in \
  "$workspace_root/.config/hypr/hyprland.lua" \
  "$workspace_root/.config/i3/config" \
  "$workspace_root/.config/aerospace/aerospace.toml" \
  "$dotfiles_dir/manifests/window-manager-bindings.tsv" \
  "$dotfiles_dir/manifests/config-linux-hypr.paths" \
  "$dotfiles_dir/manifests/config-linux-i3.paths" \
  "$dotfiles_dir/manifests/config-macos-aerospace.paths" \
  "$dotfiles_dir/manifests/packages-pacman-hypr.list" \
  "$dotfiles_dir/manifests/packages-pacman-i3.list" \
  "$dotfiles_dir/manifests/packages-apt-i3.list" \
  "$dotfiles_dir/manifests/packages-homebrew-aerospace-casks.list"
do
  if [ -f "$required_file" ]; then
    pass "required file exists: ${required_file#"$workspace_root/"}"
  else
    fail "required file exists: ${required_file#"$workspace_root/"}"
  fi
done

if [ -x "$checker" ]; then
  pass 'window-manager contract checker is executable'
else
  fail 'window-manager contract checker is executable'
fi

if [ -x "$checker" ]; then
  run_capture "$test_tmp/checker.output" "$checker" \
    --root "$workspace_root"
  if [ "$run_status" -eq 0 ]; then
    pass 'window-manager contract checker accepts the repository configs'
  else
    fail 'window-manager contract checker accepts the repository configs'
    sed 's/^/  /' "$test_tmp/checker.output" >&2
  fi
else
  fail 'window-manager contract checker accepts the repository configs'
fi

if command -v luac >/dev/null 2>&1 \
  && [ -f "$workspace_root/.config/hypr/hyprland.lua" ]; then
  run_capture "$test_tmp/luac.output" luac -p \
    "$workspace_root/.config/hypr/hyprland.lua"
  if [ "$run_status" -eq 0 ]; then
    pass 'Hyprland Lua configuration has valid Lua syntax'
  else
    fail 'Hyprland Lua configuration has valid Lua syntax'
  fi
else
  pass 'Hyprland Lua syntax check skipped when luac or config is unavailable'
fi

run_capture "$test_tmp/missing-selection.output" env \
  -u DOTFILES_BOOTSTRAP_TEST_WINDOW_MANAGER \
  HOME="$test_tmp/missing-selection-home" \
  XDG_STATE_HOME="$test_tmp/missing-selection-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
  "$bootstrap"
if [ "$run_status" -eq 2 ]; then
  pass 'bootstrap requires an explicit window-manager selection'
else
  fail 'bootstrap requires an explicit window-manager selection'
fi
missing_selection_output=$(cat "$test_tmp/missing-selection.output")
require_contains "$missing_selection_output" '--window-manager' \
  'missing-selection error explains the required option'
if [ ! -e "$test_tmp/missing-selection-home" ] \
  && [ ! -e "$test_tmp/missing-selection-state" ]; then
  pass 'missing selection fails before persistent changes'
else
  fail 'missing selection fails before persistent changes'
fi

hypr_output=$(
  HOME="$test_tmp/hypr-home" \
    XDG_STATE_HOME="$test_tmp/hypr-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
    "$bootstrap" --window-manager hypr
)
require_contains "$hypr_output" 'Window manager: hypr' \
  'Hyprland profile is reported'
require_contains "$hypr_output" '.config/hypr/hyprland.lua' \
  'Hyprland profile selects its Lua config'
require_contains "$hypr_output" 'install pacman hyprland' \
  'Hyprland profile selects only its package'
require_excludes "$hypr_output" '.config/i3/config' \
  'Hyprland profile excludes i3 config'
require_excludes "$hypr_output" '.config/aerospace/aerospace.toml' \
  'Hyprland profile excludes Aerospace config'

i3_apt_output=$(
  HOME="$test_tmp/i3-apt-home" \
    XDG_STATE_HOME="$test_tmp/i3-apt-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
    DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=1 \
    "$bootstrap" --window-manager i3
)
require_contains "$i3_apt_output" 'Window manager: i3' \
  'i3 apt profile is reported'
require_contains "$i3_apt_output" '.config/i3/config' \
  'i3 profile selects its config'
require_contains "$i3_apt_output" 'install apt i3-wm' \
  'i3 apt profile selects only i3-wm'
require_excludes "$i3_apt_output" '.config/hypr/hyprland.lua' \
  'i3 profile excludes Hyprland config'

i3_pacman_output=$(
  HOME="$test_tmp/i3-pacman-home" \
    XDG_STATE_HOME="$test_tmp/i3-pacman-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
    "$bootstrap" --window-manager i3
)
require_contains "$i3_pacman_output" 'install pacman i3-wm' \
  'i3 pacman profile selects only i3-wm'

aerospace_output=$(
  HOME="$test_tmp/aerospace-home" \
    XDG_STATE_HOME="$test_tmp/aerospace-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
    "$bootstrap" --window-manager aerospace
)
require_contains "$aerospace_output" 'Window manager: aerospace' \
  'Aerospace profile is reported'
require_contains "$aerospace_output" '.config/aerospace/aerospace.toml' \
  'Aerospace profile selects its XDG config'
require_contains "$aerospace_output" \
  'install homebrew-cask nikitabobko/tap/aerospace' \
  'Aerospace profile selects the official Homebrew cask'
require_excludes "$aerospace_output" '.config/hypr/hyprland.lua' \
  'Aerospace profile excludes Hyprland config'
require_excludes "$aerospace_output" '.config/i3/config' \
  'Aerospace profile excludes i3 config'

none_output=$(
  HOME="$test_tmp/none-home" \
    XDG_STATE_HOME="$test_tmp/none-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
    DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=1 \
    "$bootstrap" --window-manager none
)
require_contains "$none_output" 'Window manager: none' \
  'none profile is explicit'
require_excludes "$none_output" '.config/hypr/hyprland.lua' \
  'none profile excludes Hyprland config'
require_excludes "$none_output" '.config/i3/config' \
  'none profile excludes i3 config'
require_excludes "$none_output" '.config/aerospace/aerospace.toml' \
  'none profile excludes Aerospace config'

run_capture "$test_tmp/apt-hypr.output" env \
  HOME="$test_tmp/apt-hypr-home" \
  XDG_STATE_HOME="$test_tmp/apt-hypr-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  "$bootstrap" --window-manager hypr
if [ "$run_status" -eq 2 ]; then
  pass 'apt plus Hyprland is rejected before planning'
else
  fail 'apt plus Hyprland is rejected before planning'
fi

run_capture "$test_tmp/linux-aerospace.output" env \
  HOME="$test_tmp/linux-aerospace-home" \
  XDG_STATE_HOME="$test_tmp/linux-aerospace-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
  "$bootstrap" --window-manager aerospace
if [ "$run_status" -eq 2 ]; then
  pass 'Linux plus Aerospace is rejected before planning'
else
  fail 'Linux plus Aerospace is rejected before planning'
fi

run_capture "$test_tmp/macos-i3.output" env \
  HOME="$test_tmp/macos-i3-home" \
  XDG_STATE_HOME="$test_tmp/macos-i3-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  "$bootstrap" --window-manager i3
if [ "$run_status" -eq 2 ]; then
  pass 'macOS plus i3 is rejected before planning'
else
  fail 'macOS plus i3 is rejected before planning'
fi

if [ "$failures" -ne 0 ]; then
  printf '1..%d\n' "$tests"
  printf '# %d test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '1..%d\n' "$tests"
printf '# all %d tests passed\n' "$tests"
