#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
dotfiles_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
workspace_root=$(CDPATH='' cd -- "$dotfiles_dir/../.." && pwd)
checker=$dotfiles_dir/check-launcher
bootstrap=$dotfiles_dir/bootstrap
launcher=$workspace_root/.config/launcher/application-launcher
rofi_config=$workspace_root/.config/launcher/rofi.rasi

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

test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-launcher-test.XXXXXX")
cleanup() {
  case "$test_tmp" in
    "${TMPDIR:-/tmp}"/dotfiles-launcher-test.*) rm -rf "$test_tmp" ;;
  esac
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -x "$checker" ]; then
  pass 'launcher contract checker is executable'
  run_capture "$test_tmp/checker.output" "$checker" --root "$workspace_root"
  if [ "$run_status" -eq 0 ]; then
    pass 'launcher contract checker accepts the repository configuration'
  else
    fail 'launcher contract checker accepts the repository configuration'
    sed 's/^/  /' "$test_tmp/checker.output" >&2
  fi
else
  fail 'launcher contract checker is executable'
  fail 'launcher contract checker accepts the repository configuration'
fi

if [ -x "$launcher" ]; then
  pass 'application launcher is executable'
else
  fail 'application launcher is executable'
fi

if [ -r "$launcher" ] && sh -n "$launcher"; then
  pass 'application launcher has valid POSIX shell syntax'
else
  fail 'application launcher has valid POSIX shell syntax'
fi

if [ -r "$rofi_config" ]; then
  pass 'profile-scoped Rofi configuration is readable'
else
  fail 'profile-scoped Rofi configuration is readable'
fi

fake_rofi=$test_tmp/rofi
launcher_log=$test_tmp/launcher.args
# shellcheck disable=SC2016 # These variables belong to the generated fake.
printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\n" "$@" >"$APPLICATION_LAUNCHER_TEST_LOG"' \
  >"$fake_rofi"
chmod 0700 "$fake_rofi"

if [ -x "$launcher" ]; then
  run_capture "$test_tmp/launcher.output" env \
    APPLICATION_LAUNCHER_ROFI="$fake_rofi" \
    APPLICATION_LAUNCHER_TEST_LOG="$launcher_log" \
    XDG_CONFIG_HOME="$workspace_root/.config" \
    "$launcher"
  require_status "$run_status" 0 'application launcher invokes its Rofi backend'
  expected_args=$test_tmp/expected.args
  printf '%s\n' \
    -config \
    "$workspace_root/.config/launcher/rofi.rasi" \
    -show \
    drun \
    -show-icons \
    >"$expected_args"
  if cmp -s "$expected_args" "$launcher_log"; then
    pass 'application launcher exposes only Rofi drun with icons'
  else
    fail 'application launcher exposes only Rofi drun with icons'
  fi

  run_capture "$test_tmp/missing-rofi.output" env \
    APPLICATION_LAUNCHER_ROFI="$test_tmp/missing-rofi" \
    XDG_CONFIG_HOME="$workspace_root/.config" \
    "$launcher"
  require_status "$run_status" 127 'application launcher fails clearly when Rofi is unavailable'
else
  fail 'application launcher invokes its Rofi backend'
  fail 'application launcher exposes only Rofi drun with icons'
  fail 'application launcher fails clearly when Rofi is unavailable'
fi

fixture_root=$test_tmp/fixture-root
mkdir -p \
  "$fixture_root/.config/aerospace" \
  "$fixture_root/.config/dotfiles/manifests" \
  "$fixture_root/.config/hypr" \
  "$fixture_root/.config/i3" \
  "$fixture_root/.config/launcher" \
  "$fixture_root/.config/macos"
cp "$workspace_root/.config/aerospace/aerospace.toml" \
  "$fixture_root/.config/aerospace/aerospace.toml"
cp "$workspace_root/.config/hypr/hyprland.lua" \
  "$fixture_root/.config/hypr/hyprland.lua"
cp "$workspace_root/.config/i3/config" "$fixture_root/.config/i3/config"
cp "$launcher" "$fixture_root/.config/launcher/application-launcher"
cp "$rofi_config" "$fixture_root/.config/launcher/rofi.rasi"
cp "$workspace_root/.config/macos/spotlight-shortcut" \
  "$fixture_root/.config/macos/spotlight-shortcut"
for fixture_manifest in \
  config-common.paths \
  config-linux.paths \
  config-linux-hypr.paths \
  config-linux-i3.paths \
  config-macos.paths \
  packages-pacman-hypr.list \
  packages-pacman-i3.list \
  packages-apt-i3.list
do
  cp "$dotfiles_dir/manifests/$fixture_manifest" \
    "$fixture_root/.config/dotfiles/manifests/$fixture_manifest"
done

sed -i '/application-launcher/d' "$fixture_root/.config/i3/config"
run_capture "$test_tmp/missing-binding.output" "$checker" --root "$fixture_root"
if [ "$run_status" -ne 0 ]; then
  pass 'launcher checker rejects a missing Linux WM binding'
else
  fail 'launcher checker rejects a missing Linux WM binding'
fi
cp "$workspace_root/.config/i3/config" "$fixture_root/.config/i3/config"

sed -i 's/modes:[[:space:]]*"drun";/modes: "drun,window";/' \
  "$fixture_root/.config/launcher/rofi.rasi"
run_capture "$test_tmp/window-mode.output" "$checker" --root "$fixture_root"
if [ "$run_status" -ne 0 ]; then
  pass 'launcher checker rejects non-application Rofi modes'
else
  fail 'launcher checker rejects non-application Rofi modes'
fi
cp "$rofi_config" "$fixture_root/.config/launcher/rofi.rasi"

printf '%s\n' "cmd-shift-semicolon = 'exec-and-forget application-launcher'" \
  >>"$fixture_root/.config/aerospace/aerospace.toml"
run_capture "$test_tmp/aerospace-binding.output" "$checker" --root "$fixture_root"
if [ "$run_status" -ne 0 ]; then
  pass 'launcher checker rejects an AeroSpace-owned launcher binding'
else
  fail 'launcher checker rejects an AeroSpace-owned launcher binding'
fi
cp "$workspace_root/.config/aerospace/aerospace.toml" \
  "$fixture_root/.config/aerospace/aerospace.toml"

sed -i '/^rofi$/d' \
  "$fixture_root/.config/dotfiles/manifests/packages-apt-i3.list"
run_capture "$test_tmp/missing-package.output" "$checker" --root "$fixture_root"
if [ "$run_status" -ne 0 ]; then
  pass 'launcher checker rejects a missing profile package'
else
  fail 'launcher checker rejects a missing profile package'
fi

hypr_plan=$(
  HOME="$test_tmp/hypr-home" \
    XDG_STATE_HOME="$test_tmp/hypr-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
    "$bootstrap" --window-manager hypr
)
require_contains "$hypr_plan" 'install pacman rofi' \
  'Pacman Hyprland profile plans the Rofi package'
require_contains "$hypr_plan" 'install .config/launcher/rofi.rasi' \
  'Hyprland profile plans the launcher configuration'

i3_plan=$(
  HOME="$test_tmp/i3-home" \
    XDG_STATE_HOME="$test_tmp/i3-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
    DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=1 \
    "$bootstrap" --window-manager i3
)
require_contains "$i3_plan" 'install apt rofi' \
  'Apt i3 profile plans the Rofi package'
require_contains "$i3_plan" 'install .config/launcher/application-launcher' \
  'i3 profile plans the launcher command'

none_plan=$(
  HOME="$test_tmp/none-home" \
    XDG_STATE_HOME="$test_tmp/none-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
    DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=1 \
    "$bootstrap" --window-manager none
)
require_excludes "$none_plan" '.config/launcher' \
  'Linux none profile excludes launcher configuration'
require_excludes "$none_plan" 'install apt rofi' \
  'Linux none profile excludes the Rofi package'

mac_plan=$(
  HOME="$test_tmp/mac-home" \
    XDG_STATE_HOME="$test_tmp/mac-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
    "$bootstrap" --window-manager none
)
require_contains "$mac_plan" 'install .config/macos/spotlight-shortcut' \
  'macOS none profile includes the native Spotlight helper'
require_excludes "$mac_plan" '.config/launcher' \
  'macOS profile excludes Linux launcher configuration'
require_excludes "$mac_plan" 'install homebrew-formula rofi' \
  'macOS profile installs no Rofi package'

if [ "$failures" -ne 0 ]; then
  printf '# %d test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '# all %d tests passed\n' "$tests"
