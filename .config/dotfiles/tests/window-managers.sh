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

require_equals() {
  actual=$1
  expected=$2
  label=$3
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label"
    printf '  expected: %s\n' "$expected" >&2
    printf '  actual:   %s\n' "$actual" >&2
  fi
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
  "$workspace_root/.config/i3/dwindle" \
  "$workspace_root/.config/aerospace/aerospace.toml" \
  "$workspace_root/.config/aerospace/dwindle" \
  "$workspace_root/.config/karabiner/karabiner.json" \
  "$workspace_root/.config/macos/window-drag-gesture" \
  "$dotfiles_dir/manifests/window-manager-bindings.tsv" \
  "$dotfiles_dir/manifests/window-manager-pointer-bindings.tsv" \
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

for required_helper in \
  "$workspace_root/.config/i3/dwindle" \
  "$workspace_root/.config/aerospace/dwindle" \
  "$workspace_root/.config/macos/window-drag-gesture"
do
  if [ -x "$required_helper" ]; then
    pass "helper is executable: ${required_helper#"$workspace_root/"}"
  else
    fail "helper is executable: ${required_helper#"$workspace_root/"}"
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

if command -v git >/dev/null 2>&1; then
  local_root=$test_tmp/'local root\probe'
  mkdir -p \
    "$local_root/.config/aerospace" \
    "$local_root/.config/dotfiles/manifests" \
    "$local_root/.config/hypr" \
    "$local_root/.config/i3" \
    "$local_root/.config/karabiner" \
    "$local_root/.config/macos"
  cp "$workspace_root/.config/aerospace/aerospace.toml" \
    "$local_root/.config/aerospace/aerospace.toml"
  cp "$workspace_root/.config/aerospace/dwindle" \
    "$local_root/.config/aerospace/dwindle"
  cp "$workspace_root/.config/karabiner/karabiner.json" \
    "$local_root/.config/karabiner/karabiner.json"
  cp -p "$workspace_root/.config/macos/window-drag-gesture" \
    "$local_root/.config/macos/window-drag-gesture"
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-bindings.tsv"
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
  cp "$dotfiles_dir/manifests/config-macos-aerospace.paths" \
    "$local_root/.config/dotfiles/manifests/config-macos-aerospace.paths"
  cp "$dotfiles_dir/manifests/packages-homebrew-aerospace-casks.list" \
    "$local_root/.config/dotfiles/manifests/packages-homebrew-aerospace-casks.list"
  cp "$workspace_root/.config/hypr/hyprland.lua" \
    "$local_root/.config/hypr/hyprland.lua"
  cp "$workspace_root/.config/i3/config" "$local_root/.config/i3/config"
  cp "$workspace_root/.config/i3/dwindle" "$local_root/.config/i3/dwindle"
  git -C "$local_root" init -q -b main
  git -C "$local_root" add .config
  printf '%s\n' 'machine-local legacy config' \
    >"$local_root/.config/hypr/hyprland.conf"
  run_capture "$test_tmp/checker-untracked-legacy.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -eq 0 ]; then
    pass 'contract checker preserves an untracked local legacy config'
  else
    fail 'contract checker preserves an untracked local legacy config'
  fi

  sed \
    's/^preference_key=NSWindowShouldDragOnGesture$/preference_key=NSWindowShouldDragOnGestureChanged/' \
    "$workspace_root/.config/macos/window-drag-gesture" \
    >"$local_root/.config/macos/window-drag-gesture"
  chmod 0700 "$local_root/.config/macos/window-drag-gesture"
  run_capture "$test_tmp/checker-window-drag-key.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a changed window-drag preference key'
  else
    fail 'contract checker rejects a changed window-drag preference key'
  fi
  cp -p "$workspace_root/.config/macos/window-drag-gesture" \
    "$local_root/.config/macos/window-drag-gesture"

  awk '
    { print }
    $0 == "preference_key=NSWindowShouldDragOnGesture" {
      print "export preference_key=NSWindowShouldDragOnGestureChanged"
    }
  ' "$workspace_root/.config/macos/window-drag-gesture" \
    >"$local_root/.config/macos/window-drag-gesture"
  chmod 0700 "$local_root/.config/macos/window-drag-gesture"
  run_capture "$test_tmp/checker-window-drag-shadow-key.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a shadow window-drag preference key'
  else
    fail 'contract checker rejects a shadow window-drag preference key'
  fi
  cp -p "$workspace_root/.config/macos/window-drag-gesture" \
    "$local_root/.config/macos/window-drag-gesture"

  window_drag_sentinel=$test_tmp/window-drag-helper-executed
  awk '
    { print }
    $0 == "preference_key=NSWindowShouldDragOnGesture" {
      print ": >\"$DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_SENTINEL\""
      print "export preference_key\"=NSWindowShouldDragOnGestureChanged\""
    }
  ' "$workspace_root/.config/macos/window-drag-gesture" \
    >"$local_root/.config/macos/window-drag-gesture"
  chmod 0700 "$local_root/.config/macos/window-drag-gesture"
  run_capture "$test_tmp/checker-window-drag-quoted-shadow-key.output" \
    env DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_SENTINEL="$window_drag_sentinel" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ] && [ ! -e "$window_drag_sentinel" ]; then
    pass 'contract checker rejects quoted key reassignment without executing helper code'
  else
    fail 'contract checker rejects quoted key reassignment without executing helper code'
  fi
  cp -p "$workspace_root/.config/macos/window-drag-gesture" \
    "$local_root/.config/macos/window-drag-gesture"

  awk '
    { print }
    $0 == "preference_key=NSWindowShouldDragOnGesture" {
      print "eval '\''preference_'\''key'\''=NSWindowShouldDragOnGestureChanged'\''"
    }
  ' "$workspace_root/.config/macos/window-drag-gesture" \
    >"$local_root/.config/macos/window-drag-gesture"
  chmod 0700 "$local_root/.config/macos/window-drag-gesture"
  run_capture "$test_tmp/checker-window-drag-split-token-key.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a split-token window-drag key reassignment'
  else
    fail 'contract checker rejects a split-token window-drag key reassignment'
  fi
  cp -p "$workspace_root/.config/macos/window-drag-gesture" \
    "$local_root/.config/macos/window-drag-gesture"

  awk '
    { print }
    $0 == "preference_key=NSWindowShouldDragOnGesture" {
      print "# reviewed helper comments are part of the immutable byte contract"
    }
  ' "$workspace_root/.config/macos/window-drag-gesture" \
    >"$local_root/.config/macos/window-drag-gesture"
  chmod 0700 "$local_root/.config/macos/window-drag-gesture"
  run_capture "$test_tmp/checker-window-drag-comment.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects an unreviewed comment-only helper change'
  else
    fail 'contract checker rejects an unreviewed comment-only helper change'
  fi
  cp -p "$workspace_root/.config/macos/window-drag-gesture" \
    "$local_root/.config/macos/window-drag-gesture"

  tab=$(printf '\t')
  sed "s/${tab}SUPER${tab}OPTION${tab}/${tab}ALT${tab}OPTION${tab}/" \
    "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    >"$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
  run_capture "$test_tmp/checker-pointer-linux-modifier.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a changed Linux pointer modifier'
  else
    fail 'contract checker rejects a changed Linux pointer modifier'
  fi
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"

  sed "2s/^/${tab}/" \
    "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    >"$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
  run_capture "$test_tmp/checker-pointer-leading-empty.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a leading empty pointer field'
  else
    fail 'contract checker rejects a leading empty pointer field'
  fi
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"

  sed "2s/${tab}/${tab}${tab}/" \
    "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    >"$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
  run_capture "$test_tmp/checker-pointer-repeated-empty.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a repeated empty pointer field'
  else
    fail 'contract checker rejects a repeated empty pointer field'
  fi
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"

  sed "2s/$/${tab}/" \
    "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    >"$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
  run_capture "$test_tmp/checker-pointer-trailing-empty.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a trailing empty pointer field'
  else
    fail 'contract checker rejects a trailing empty pointer field'
  fi
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"

  sed "s/${tab}button1${tab}/${tab}button2${tab}/" \
    "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    >"$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
  run_capture "$test_tmp/checker-pointer-button.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a changed shared pointer button'
  else
    fail 'contract checker rejects a changed shared pointer button'
  fi
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"

  sed 's/SUPER + mouse:272/ALT + mouse:272/' \
    "$workspace_root/.config/hypr/hyprland.lua" \
    >"$local_root/.config/hypr/hyprland.lua"
  run_capture "$test_tmp/checker-pointer-hypr.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a changed Hyprland pointer chord'
  else
    fail 'contract checker rejects a changed Hyprland pointer chord'
  fi
  cp "$workspace_root/.config/hypr/hyprland.lua" \
    "$local_root/.config/hypr/hyprland.lua"

  sed 's/^tiling_drag modifier$/tiling_drag titlebar/' \
    "$workspace_root/.config/i3/config" \
    >"$local_root/.config/i3/config"
  run_capture "$test_tmp/checker-pointer-i3.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a changed i3 tiled-drag mechanism'
  else
    fail 'contract checker rejects a changed i3 tiled-drag mechanism'
  fi
  cp "$workspace_root/.config/i3/config" "$local_root/.config/i3/config"

  {
    cat "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
    printf '%b\n' \
      'reorder-tiled-window\tprimary-drag\tSUPER\tOPTION\tbutton1\thypr-window-drag\ti3-tiling-drag\tmacos-native-window-drag'
  } >"$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"
  run_capture "$test_tmp/checker-pointer-duplicate.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a duplicate shared pointer action'
  else
    fail 'contract checker rejects a duplicate shared pointer action'
  fi
  cp "$workspace_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv" \
    "$local_root/.config/dotfiles/manifests/window-manager-pointer-bindings.tsv"

  printf '%s\n' '{' >"$local_root/.config/karabiner/karabiner.json"
  run_capture "$test_tmp/checker-karabiner-malformed.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects malformed Karabiner JSON'
  else
    fail 'contract checker rejects malformed Karabiner JSON'
  fi
  cp "$workspace_root/.config/karabiner/karabiner.json" \
    "$local_root/.config/karabiner/karabiner.json"

  sed 's/"option"/"command"/' \
    "$workspace_root/.config/karabiner/karabiner.json" \
    >"$local_root/.config/karabiner/karabiner.json"
  run_capture "$test_tmp/checker-karabiner-input-modifier.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a changed Karabiner input modifier'
  else
    fail 'contract checker rejects a changed Karabiner input modifier'
  fi
  cp "$workspace_root/.config/karabiner/karabiner.json" \
    "$local_root/.config/karabiner/karabiner.json"

  jq '.profiles[0].complex_modifications.rules[0].manipulators[0].from.modifiers.optional = ["any"]' \
    "$workspace_root/.config/karabiner/karabiner.json" \
    >"$local_root/.config/karabiner/karabiner.json"
  run_capture "$test_tmp/checker-karabiner-extra-modifiers.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects broad Karabiner modifier interception'
  else
    fail 'contract checker rejects broad Karabiner modifier interception'
  fi
  cp "$workspace_root/.config/karabiner/karabiner.json" \
    "$local_root/.config/karabiner/karabiner.json"

  jq '.profiles[0].complex_modifications.rules[0].manipulators[0].to[0].pointing_button = "button2"' \
    "$workspace_root/.config/karabiner/karabiner.json" \
    >"$local_root/.config/karabiner/karabiner.json"
  run_capture "$test_tmp/checker-karabiner-output-button.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a changed Karabiner output button'
  else
    fail 'contract checker rejects a changed Karabiner output button'
  fi
  cp "$workspace_root/.config/karabiner/karabiner.json" \
    "$local_root/.config/karabiner/karabiner.json"

  jq '.profiles[0].complex_modifications.rules[0].manipulators += [.profiles[0].complex_modifications.rules[0].manipulators[0]]' \
    "$workspace_root/.config/karabiner/karabiner.json" \
    >"$local_root/.config/karabiner/karabiner.json"
  run_capture "$test_tmp/checker-karabiner-extra-manipulator.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects an extra Karabiner pointer manipulator'
  else
    fail 'contract checker rejects an extra Karabiner pointer manipulator'
  fi
  cp "$workspace_root/.config/karabiner/karabiner.json" \
    "$local_root/.config/karabiner/karabiner.json"

  sed 's/            natural_scroll = true,/            natural_scroll = false,/' \
    "$workspace_root/.config/hypr/hyprland.lua" \
    >"$local_root/.config/hypr/hyprland.lua"
  run_capture "$test_tmp/checker-disabled-natural-scroll.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects disabled touchpad natural scrolling'
  else
    fail 'contract checker rejects disabled touchpad natural scrolling'
  fi
  cp "$workspace_root/.config/hypr/hyprland.lua" \
    "$local_root/.config/hypr/hyprland.lua"

  printf '%s\n' \
    'hl.animation({ leaf = "windows", enabled = true, speed = 2, bezier = "default" })' \
    >>"$local_root/.config/hypr/hyprland.lua"
  run_capture "$test_tmp/checker-unapproved-animation.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects an unapproved Hyprland animation'
  else
    fail 'contract checker rejects an unapproved Hyprland animation'
  fi
  cp "$workspace_root/.config/hypr/hyprland.lua" \
    "$local_root/.config/hypr/hyprland.lua"

  printf '%s\n' \
    'hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })' \
    >>"$local_root/.config/hypr/hyprland.lua"
  run_capture "$test_tmp/checker-unapproved-gesture.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects an unapproved Hyprland gesture'
  else
    fail 'contract checker rejects an unapproved Hyprland gesture'
  fi
  cp "$workspace_root/.config/hypr/hyprland.lua" \
    "$local_root/.config/hypr/hyprland.lua"

  printf '%s\n' 'exec --no-startup-id unrelated-command' \
    >>"$local_root/.config/i3/config"
  run_capture "$test_tmp/checker-unrelated-i3-exec.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects an unrelated i3 startup command'
  else
    fail 'contract checker rejects an unrelated i3 startup command'
  fi
  cp "$workspace_root/.config/i3/config" "$local_root/.config/i3/config"

  printf '%s\n' \
    "on-window-detected = [{ run = 'exec-and-forget unrelated-command' }]" \
    >>"$local_root/.config/aerospace/aerospace.toml"
  run_capture "$test_tmp/checker-unrelated-aerospace-callback.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects an unrelated AeroSpace callback'
  else
    fail 'contract checker rejects an unrelated AeroSpace callback'
  fi
  cp "$workspace_root/.config/aerospace/aerospace.toml" \
    "$local_root/.config/aerospace/aerospace.toml"

  git -C "$local_root" add .config/hypr/hyprland.conf
  run_capture "$test_tmp/checker-tracked-legacy.output" \
    "$checker" --root "$local_root"
  if [ "$run_status" -ne 0 ]; then
    pass 'contract checker rejects a tracked legacy manager entrypoint'
  else
    fail 'contract checker rejects a tracked legacy manager entrypoint'
  fi
else
  pass 'contract checker local legacy tracking tests skipped without Git'
  pass 'contract checker tracked legacy rejection skipped without Git'
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

hypr_config=$(cat "$workspace_root/.config/hypr/hyprland.lua")
require_contains "$hypr_config" 'force_split = 2' \
  'Hyprland places new Dwindle tiles on the right or bottom'
require_contains "$hypr_config" 'preserve_split = true' \
  'Hyprland preserves established Dwindle splits'
require_contains "$hypr_config" '            natural_scroll = true,' \
  'Hyprland enables natural scrolling for the touchpad'
require_contains "$hypr_config" \
  'hl.animation({ leaf = "workspaces", enabled = false })' \
  'Hyprland keeps shortcut workspace changes instantaneous'
require_contains "$hypr_config" \
  'hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })' \
  'Hyprland slides between workspaces with a three-finger gesture'
require_contains "$hypr_config" \
  'hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }))' \
  'Hyprland key 1 selects numeric workspace 1'
require_contains "$hypr_config" \
  'hl.bind("SUPER + 0", hl.dsp.focus({ workspace = 10 }))' \
  'Hyprland key 0 selects numeric workspace 10'
require_contains "$hypr_config" \
  'hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))' \
  'Hyprland Shift+1 moves a window to numeric workspace 1'
require_contains "$hypr_config" \
  'hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))' \
  'Hyprland Shift+0 moves a window to numeric workspace 10'
require_excludes "$hypr_config" 'workspace = "name:' \
  'Hyprland avoids dynamically ordered named numeric workspaces'

i3_config=$(cat "$workspace_root/.config/i3/config")
require_contains "$i3_config" 'exec --no-startup-id ~/.config/i3/dwindle' \
  'i3 starts its Dwindle event helper'

aerospace_config=$(cat "$workspace_root/.config/aerospace/aerospace.toml")
require_contains "$aerospace_config" \
  "on-window-detected = [{ check-further-callbacks = true, run = 'exec-and-forget /bin/sh \"\${HOME}/.config/aerospace/dwindle\"' }]" \
  'AeroSpace runs its Dwindle helper for newly detected windows'

fake_i3msg=$test_tmp/i3-msg
# The variables below belong to the generated fake, not this test process.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$I3_DWINDLE_TEST_LOG"' \
  >"$fake_i3msg"
chmod +x "$fake_i3msg"
i3_helper=$workspace_root/.config/i3/dwindle
i3_log=$test_tmp/i3-actions.log

: >"$i3_log"
run_capture "$test_tmp/i3-wide.output" env \
  I3_DWINDLE_I3MSG="$fake_i3msg" \
  I3_DWINDLE_TEST_LOG="$i3_log" \
  "$i3_helper" --once \
  '{"change":"focus","container":{"id":42,"floating":"auto_off","rect":{"width":1200,"height":700}}}'
require_status "$run_status" 0 'i3 helper accepts a wide tiled-window event'
require_equals "$(cat "$i3_log")" '[con_id=42] split h' \
  'i3 helper makes the next child of a wide tile appear to its right'

: >"$i3_log"
run_capture "$test_tmp/i3-tall.output" env \
  I3_DWINDLE_I3MSG="$fake_i3msg" \
  I3_DWINDLE_TEST_LOG="$i3_log" \
  "$i3_helper" --once \
  '{"change":"move","container":{"id":43,"floating":"user_off","rect":{"width":600,"height":900}}}'
require_status "$run_status" 0 'i3 helper accepts a tall tiled-window event'
require_equals "$(cat "$i3_log")" '[con_id=43] split v' \
  'i3 helper makes the next child of a tall tile appear below it'

: >"$i3_log"
run_capture "$test_tmp/i3-floating.output" env \
  I3_DWINDLE_I3MSG="$fake_i3msg" \
  I3_DWINDLE_TEST_LOG="$i3_log" \
  "$i3_helper" --once \
  '{"change":"focus","container":{"id":44,"floating":"auto_on","rect":{"width":1200,"height":700}}}'
require_status "$run_status" 0 'i3 helper accepts a floating-window event'
require_equals "$(cat "$i3_log")" '' \
  'i3 helper leaves floating windows untouched'

fake_aerospace=$test_tmp/aerospace
# The variables below belong to the generated fake, not this test process.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/sh' \
  'case ${1:-} in' \
  '  echo)' \
  '    case ${5:-} in' \
  "      '%{workspace}') printf '%s\\n' \"\${AEROSPACE_DWINDLE_TEST_WORKSPACE:-0}\" ;;" \
  "      '%{window-layout}') printf '%s\\n' \"\${AEROSPACE_DWINDLE_TEST_LAYOUT:-h_tiles}\" ;;" \
  '      *) exit 2 ;;' \
  '    esac' \
  '    ;;' \
  '  list-windows)' \
  '    count=${AEROSPACE_DWINDLE_TEST_WINDOW_COUNT:-0}' \
  '    while [ "$count" -gt 0 ]; do' \
  '      printf "%s\n" "${AEROSPACE_DWINDLE_TEST_LAYOUT:-h_tiles}"' \
  '      count=$((count - 1))' \
  '    done' \
  '    ;;' \
  '  join-with)' \
  '    printf "%s\n" "$*" >>"$AEROSPACE_DWINDLE_TEST_LOG"' \
  '    ;;' \
  '  *) exit 2 ;;' \
  'esac' \
  >"$fake_aerospace"
chmod +x "$fake_aerospace"
aerospace_helper=$workspace_root/.config/aerospace/dwindle
aerospace_log=$test_tmp/aerospace-actions.log

: >"$aerospace_log"
run_capture "$test_tmp/aerospace-two.output" env \
  AEROSPACE_DWINDLE_BIN="$fake_aerospace" \
  AEROSPACE_DWINDLE_TEST_LOG="$aerospace_log" \
  AEROSPACE_DWINDLE_TEST_WINDOW_COUNT=2 \
  AEROSPACE_WINDOW_ID=52 \
  "$aerospace_helper"
require_status "$run_status" 0 'AeroSpace helper accepts a second tiled window'
require_equals "$(cat "$aerospace_log")" '' \
  'AeroSpace helper leaves the first two tiles side by side'

: >"$aerospace_log"
run_capture "$test_tmp/aerospace-horizontal.output" env \
  AEROSPACE_DWINDLE_BIN="$fake_aerospace" \
  AEROSPACE_DWINDLE_TEST_LAYOUT=h_tiles \
  AEROSPACE_DWINDLE_TEST_LOG="$aerospace_log" \
  AEROSPACE_DWINDLE_TEST_WINDOW_COUNT=3 \
  AEROSPACE_WINDOW_ID=53 \
  "$aerospace_helper"
require_status "$run_status" 0 'AeroSpace helper accepts a third horizontal tile'
require_equals "$(cat "$aerospace_log")" \
  'join-with --window-id 53 left' \
  'AeroSpace helper nests a horizontal tile with its left neighbor'

: >"$aerospace_log"
run_capture "$test_tmp/aerospace-vertical.output" env \
  AEROSPACE_DWINDLE_BIN="$fake_aerospace" \
  AEROSPACE_DWINDLE_TEST_LAYOUT=v_tiles \
  AEROSPACE_DWINDLE_TEST_LOG="$aerospace_log" \
  AEROSPACE_DWINDLE_TEST_WINDOW_COUNT=4 \
  AEROSPACE_WINDOW_ID=54 \
  "$aerospace_helper"
require_status "$run_status" 0 'AeroSpace helper accepts a fourth tile in a vertical parent'
require_equals "$(cat "$aerospace_log")" \
  'join-with --window-id 54 up' \
  'AeroSpace helper splits the bottom-right tile into left and right children'

: >"$aerospace_log"
run_capture "$test_tmp/aerospace-floating.output" env \
  AEROSPACE_DWINDLE_BIN="$fake_aerospace" \
  AEROSPACE_DWINDLE_TEST_LAYOUT=floating \
  AEROSPACE_DWINDLE_TEST_LOG="$aerospace_log" \
  AEROSPACE_DWINDLE_TEST_WINDOW_COUNT=3 \
  AEROSPACE_WINDOW_ID=55 \
  "$aerospace_helper"
require_status "$run_status" 0 'AeroSpace helper accepts a floating window'
require_equals "$(cat "$aerospace_log")" '' \
  'AeroSpace helper leaves floating windows untouched'

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
require_excludes "$hypr_output" '.config/i3/dwindle' \
  'Hyprland profile excludes the i3 Dwindle helper'
require_excludes "$hypr_output" '.config/aerospace/aerospace.toml' \
  'Hyprland profile excludes Aerospace config'
require_excludes "$hypr_output" '.config/aerospace/dwindle' \
  'Hyprland profile excludes the AeroSpace Dwindle helper'

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
require_contains "$i3_apt_output" '.config/i3/dwindle' \
  'i3 profile selects its Dwindle helper'
require_contains "$i3_apt_output" 'install apt i3-wm' \
  'i3 apt profile selects only i3-wm'
require_excludes "$i3_apt_output" '.config/hypr/hyprland.lua' \
  'i3 profile excludes Hyprland config'
require_excludes "$i3_apt_output" '.config/aerospace/dwindle' \
  'i3 profile excludes the AeroSpace Dwindle helper'

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
require_contains "$aerospace_output" '.config/aerospace/dwindle' \
  'Aerospace profile selects its Dwindle helper'
require_contains "$aerospace_output" \
  'install homebrew-cask nikitabobko/tap/aerospace' \
  'Aerospace profile selects the official Homebrew cask'
require_contains "$aerospace_output" '.config/karabiner/karabiner.json' \
  'AeroSpace profile selects its Karabiner bridge'
require_contains "$aerospace_output" '.config/macos/window-drag-gesture' \
  'AeroSpace profile selects its transactional window-drag helper'
require_contains "$aerospace_output" \
  'install homebrew-cask karabiner-elements' \
  'AeroSpace profile selects Karabiner Elements'
require_contains "$aerospace_output" \
  'backup and enable NSWindowShouldDragOnGesture for Control+Command drag' \
  'AeroSpace dry-run reports the transactional window-drag preference'
require_contains "$aerospace_output" \
  'open Karabiner-Elements and complete its required macOS setup' \
  'AeroSpace dry-run reports the one-time permission step'
require_excludes "$aerospace_output" '.config/hypr/hyprland.lua' \
  'Aerospace profile excludes Hyprland config'
require_excludes "$aerospace_output" '.config/i3/config' \
  'Aerospace profile excludes i3 config'
require_excludes "$aerospace_output" '.config/i3/dwindle' \
  'Aerospace profile excludes the i3 Dwindle helper'

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
require_excludes "$none_output" '.config/i3/dwindle' \
  'none profile excludes the i3 Dwindle helper'
require_excludes "$none_output" '.config/aerospace/aerospace.toml' \
  'none profile excludes Aerospace config'
require_excludes "$none_output" '.config/aerospace/dwindle' \
  'none profile excludes the AeroSpace Dwindle helper'

mac_none_output=$(
  HOME="$test_tmp/mac-none-home" \
    XDG_STATE_HOME="$test_tmp/mac-none-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
    "$bootstrap" --window-manager none
)
require_excludes "$mac_none_output" '.config/karabiner/karabiner.json' \
  'macOS none profile excludes the Karabiner bridge'
require_excludes "$mac_none_output" '.config/macos/window-drag-gesture' \
  'macOS none profile excludes the window-drag helper'
require_excludes "$mac_none_output" 'karabiner-elements' \
  'macOS none profile excludes Karabiner Elements'
require_excludes "$mac_none_output" 'NSWindowShouldDragOnGesture' \
  'macOS none profile excludes the window-drag preference'
require_excludes "$mac_none_output" 'required macOS setup' \
  'macOS none profile excludes the Karabiner permission step'

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
