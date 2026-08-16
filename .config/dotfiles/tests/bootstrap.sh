#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
dotfiles_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
workspace_root=$(CDPATH='' cd -- "$dotfiles_dir/../.." && pwd)
bootstrap=$dotfiles_dir/bootstrap
DOTFILES_BOOTSTRAP_TEST_WINDOW_MANAGER=none
export DOTFILES_BOOTSTRAP_TEST_WINDOW_MANAGER

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

test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bootstrap-test.XXXXXX")
cleanup() {
  case "$test_tmp" in
    "${TMPDIR:-/tmp}"/dotfiles-bootstrap-test.*) rm -rf "$test_tmp" ;;
  esac
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -x "$bootstrap" ]; then
  pass 'bootstrap is executable'
else
  fail 'bootstrap is executable'
fi

run_capture "$test_tmp/help" "$bootstrap" --help
if [ "$run_status" -eq 0 ]; then
  pass '--help exits successfully'
else
  fail '--help exits successfully'
fi
help_output=$(cat "$test_tmp/help")
require_contains "$help_output" 'bootstrap [--apply]' '--help documents apply mode'
require_contains "$help_output" '--rollback (latest|RUN_ID)' '--help documents rollback mode'
require_contains "$help_output" '--allow-community-packages' '--help documents community package gate'

run_capture "$test_tmp/invalid" "$bootstrap" --unknown-option
if [ "$run_status" -eq 2 ]; then
  pass 'unknown options use the usage exit status'
else
  fail 'unknown options use the usage exit status'
fi

linux_output=$(
  HOME="$test_tmp/linux-home" \
    XDG_STATE_HOME="$test_tmp/linux-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
    "$bootstrap"
)
require_contains "$linux_output" 'Mode: dry-run' 'no arguments select dry-run mode'
require_contains "$linux_output" 'Platform: linux' 'Linux platform is reported'
require_contains "$linux_output" 'Package manager: pacman' 'pacman backend is reported'
require_contains "$linux_output" '.config/tmux/conf/platform/linux.conf' 'Linux plan includes Linux tmux adapter'
require_contains "$linux_output" '.config/tmux/conf/persistence.conf' \
  'common plan includes tmux persistence binding'
require_contains "$linux_output" '.codex/hooks.json' \
  'common plan includes Codex lifecycle hooks'
require_contains "$linux_output" '.config/systemd/user/tmux-workspace.service' \
  'Linux plan includes the tmux workspace user service'
require_contains "$linux_output" 'systemctl --user daemon-reload' \
  'Linux dry-run reports the user daemon reload'
require_contains "$linux_output" 'systemctl --user enable --now tmux-workspace.service' \
  'Linux dry-run reports service enablement and startup'
require_excludes "$linux_output" '.config/tmux/conf/platform/macos.conf' 'Linux plan excludes macOS tmux adapter'
require_excludes "$linux_output" 'Library/Application Support/com.mitchellh.ghostty/config.ghostty' 'Linux plan excludes macOS Ghostty entrypoint'

require_contains "$linux_output" 'install pacman neovim' 'pacman plan includes Neovim'
require_contains "$linux_output" 'install pacman ghostty' 'pacman plan includes Ghostty'
require_contains "$linux_output" 'install pacman ttf-space-mono-nerd' 'pacman plan includes the configured font'
require_contains "$linux_output" 'manual sudo pacman -Syu --needed' 'pacman plan requires an explicit full upgrade'
require_contains "$linux_output" 'install upstream herdr' 'pacman plan uses the official Herdr installer'
for provider in \
  bash-language-server \
  vscode-json-languageserver \
  lua-language-server \
  pyright \
  yaml-language-server
do
  require_contains "$linux_output" "install pacman $provider" \
    "pacman plan includes $provider"
done

apt_output=$(
  HOME="$test_tmp/apt-home" \
    XDG_STATE_HOME="$test_tmp/apt-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
    DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=0 \
    "$bootstrap"
)
require_contains "$apt_output" 'install apt git' 'apt plan includes Git'
require_contains "$apt_output" 'install upstream neovim >=0.12.0' 'apt plan preserves the Neovim version floor'
require_contains "$apt_output" 'install upstream herdr' 'apt plan uses the official Herdr installer'
require_contains "$apt_output" 'blocked community ghostty' 'apt plan blocks community Ghostty without consent'
apt_lsp_plan=$(printf '%s\n' "$apt_output" | sed -n '/ensure upstream node >=22.0.0/,/ensure npm yaml-language-server@1.24.0/p')
expected_apt_lsp_plan='  ensure upstream node >=22.0.0 with npm >=10.0.0 (fallback node 24.19.0)
  ensure upstream lua-language-server >=3.19.1
  ensure npm bash-language-server@5.6.0
  ensure npm vscode-langservers-extracted@4.10.0
  ensure npm pyright@1.1.411
  ensure npm yaml-language-server@1.24.0'
if [ "$apt_lsp_plan" = "$expected_apt_lsp_plan" ]; then
  pass 'apt plan preserves the exact ordered language-server fallback contract'
else
  fail 'apt plan preserves the exact ordered language-server fallback contract'
fi

apt_community_output=$(
  HOME="$test_tmp/apt-community-home" \
    XDG_STATE_HOME="$test_tmp/apt-community-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
    DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=0 \
    "$bootstrap" --allow-community-packages
)
require_contains "$apt_community_output" 'install community ghostty' 'apt plan includes community Ghostty after explicit consent'

apt_official_output=$(
  HOME="$test_tmp/apt-official-home" \
    XDG_STATE_HOME="$test_tmp/apt-official-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
    DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=1 \
    "$bootstrap"
)
if printf '%s\n' "$apt_official_output" | grep -Fq 'install apt ghostty' \
  && ! printf '%s\n' "$apt_official_output" | grep -Fq 'blocked community ghostty'; then
  pass 'apt plan prefers an available official Ghostty package'
else
  fail 'apt plan prefers an available official Ghostty package'
fi

macos_output=$(
  HOME="$test_tmp/macos-home" \
    XDG_STATE_HOME="$test_tmp/macos-state" \
    DOTFILES_BOOTSTRAP_TESTING=1 \
    DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
    DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
    "$bootstrap"
)
require_contains "$macos_output" '.config/tmux/conf/platform/macos.conf' 'macOS plan includes macOS tmux adapter'
require_contains "$macos_output" 'Library/LaunchAgents/dev.ruohao.tmux-workspace.plist' \
  'macOS plan includes the tmux workspace LaunchAgent'
require_contains "$macos_output" "launchctl bootstrap gui/$(id -u)" \
  'macOS dry-run reports LaunchAgent bootstrap'
require_contains "$macos_output" \
  "launchctl kickstart -k gui/$(id -u)/dev.ruohao.tmux-workspace" \
  'macOS dry-run reports LaunchAgent kickstart'
require_contains "$macos_output" 'install homebrew-formula neovim' 'Homebrew plan includes Neovim formula'
require_contains "$macos_output" 'install homebrew-cask ghostty' 'Homebrew plan includes Ghostty cask'
for provider in \
  bash-language-server \
  vscode-langservers-extracted \
  lua-language-server \
  pyright \
  yaml-language-server
do
  require_contains "$macos_output" "install homebrew-formula $provider" \
    "Homebrew plan includes $provider"
done
require_excludes "$macos_output" '.config/tmux/conf/platform/linux.conf' 'macOS plan excludes Linux tmux adapter'
require_contains "$macos_output" \
  'backup and set Spotlight shortcut Command+Shift+semicolon' \
  'macOS dry-run reports the transactional Spotlight shortcut change'
require_excludes "$macos_output" 'NSWindowShouldDragOnGesture' \
  'macOS none dry-run excludes the AeroSpace window-drag preference'
require_excludes "$macos_output" 'required macOS setup' \
  'macOS none dry-run excludes the Karabiner permission step'
workspace_launch_agent=$workspace_root/Library/LaunchAgents/dev.ruohao.tmux-workspace.plist
if grep -Fq '<key>RunAtLoad</key>' "$workspace_launch_agent" \
  && grep -Fq '<key>KeepAlive</key>' "$workspace_launch_agent" \
  && grep -Fq '<string>/bin/sh</string>' "$workspace_launch_agent" \
  && ! grep -Fq '/home/ruohao' "$workspace_launch_agent"; then
  pass 'workspace LaunchAgent is portable and starts automatically'
else
  fail 'workspace LaunchAgent is portable and starts automatically'
fi

if [ ! -e "$test_tmp/linux-home" ] && [ ! -e "$test_tmp/linux-state" ]; then
  pass 'dry-run creates no persistent home or state paths'
else
  fail 'dry-run creates no persistent home or state paths'
fi

apt_blocked_log=$test_tmp/apt-blocked.commands
run_capture "$test_tmp/apt-blocked.output" env \
  HOME="$test_tmp/apt-blocked-home" \
  XDG_STATE_HOME="$test_tmp/apt-blocked-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=0 \
  DOTFILES_BOOTSTRAP_TEST_STOP_AFTER_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$apt_blocked_log" \
  "$bootstrap" --apply
if [ "$run_status" -eq 4 ]; then
  pass 'apt apply blocks before changes when community consent is missing'
else
  fail 'apt apply blocks before changes when community consent is missing'
fi
apt_blocked_output=$(cat "$test_tmp/apt-blocked.output")
require_contains "$apt_blocked_output" '--allow-community-packages' 'apt block explains the community package flag'
if [ ! -e "$apt_blocked_log" ]; then
  pass 'blocked apt apply executes no package commands'
else
  fail 'blocked apt apply executes no package commands'
fi

apt_apply_log=$test_tmp/apt-apply.commands
run_capture "$test_tmp/apt-apply.output" env \
  HOME="$test_tmp/apt-apply-home" \
  XDG_STATE_HOME="$test_tmp/apt-apply-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=0 \
  DOTFILES_BOOTSTRAP_TEST_STOP_AFTER_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$apt_apply_log" \
  "$bootstrap" --apply --allow-community-packages
if [ "$run_status" -eq 0 ]; then
  pass 'apt package phase succeeds with explicit community consent'
else
  fail 'apt package phase succeeds with explicit community consent'
fi
apt_apply_commands=$(cat "$apt_apply_log" 2>/dev/null || true)
require_contains "$apt_apply_commands" 'sudo apt-get update' 'apt package phase refreshes indexes only during apply'
require_contains "$apt_apply_commands" 'sudo apt-get install -y --no-install-recommends --no-remove' 'apt package install refuses removals'
require_contains "$apt_apply_commands" 'direct-install neovim' 'apt package phase installs supported Neovim upstream'
require_contains "$apt_apply_commands" 'community-installer ghostty' 'apt package phase records the consented Ghostty installer'

pacman_apply_log=$test_tmp/pacman-apply.commands
run_capture "$test_tmp/pacman-apply.output" env \
  HOME="$test_tmp/pacman-apply-home" \
  XDG_STATE_HOME="$test_tmp/pacman-apply-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_STOP_AFTER_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$pacman_apply_log" \
  "$bootstrap" --apply
if [ "$run_status" -eq 4 ]; then
  pass 'pacman apply stops for the user-managed full upgrade'
else
  fail 'pacman apply stops for the user-managed full upgrade'
fi
if [ ! -e "$pacman_apply_log" ]; then
  pass 'pacman policy stop executes no package command'
else
  fail 'pacman policy stop executes no package command'
fi

brew_apply_log=$test_tmp/brew-apply.commands
run_capture "$test_tmp/brew-apply.output" env \
  HOME="$test_tmp/brew-apply-home" \
  XDG_STATE_HOME="$test_tmp/brew-apply-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_BREW_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_STOP_AFTER_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$brew_apply_log" \
  "$bootstrap" --apply
if [ "$run_status" -eq 0 ]; then
  pass 'Homebrew package phase succeeds in the command harness'
else
  fail 'Homebrew package phase succeeds in the command harness'
fi
brew_apply_commands=$(cat "$brew_apply_log" 2>/dev/null || true)
require_contains "$brew_apply_commands" 'pinned-installer homebrew a34ae4ee9151cbce4c3b33bca7043a972b7ae9a5' 'Homebrew bootstrap uses the pinned installer revision'
require_contains "$brew_apply_commands" 'brew install neovim' 'Homebrew package phase installs missing formulae'
require_contains "$brew_apply_commands" 'brew install --cask ghostty' 'Homebrew package phase installs missing casks'
if printf '%s\n' "$brew_apply_commands" | grep -Fqx 'brew install bash-language-server' \
  && printf '%s\n' "$brew_apply_commands" | grep -Fqx 'brew install vscode-langservers-extracted' \
  && printf '%s\n' "$brew_apply_commands" | grep -Fqx 'brew install lua-language-server' \
  && printf '%s\n' "$brew_apply_commands" | grep -Fqx 'brew install pyright' \
  && printf '%s\n' "$brew_apply_commands" | grep -Fqx 'brew install yaml-language-server'; then
  pass 'Homebrew apply installs all five exact language-server formulae'
else
  fail 'Homebrew apply installs all five exact language-server formulae'
fi

i3_apt_apply_log=$test_tmp/i3-apt-apply.commands
run_capture "$test_tmp/i3-apt-apply.output" env \
  HOME="$test_tmp/i3-apt-apply-home" \
  XDG_STATE_HOME="$test_tmp/i3-apt-apply-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=1 \
  DOTFILES_BOOTSTRAP_TEST_STOP_AFTER_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$i3_apt_apply_log" \
  "$bootstrap" --apply --window-manager i3
if [ "$run_status" -eq 0 ]; then
  pass 'i3 apt package phase succeeds in the command harness'
else
  fail 'i3 apt package phase succeeds in the command harness'
fi
i3_apt_apply_commands=$(cat "$i3_apt_apply_log" 2>/dev/null || true)
require_contains "$i3_apt_apply_commands" 'i3-wm' \
  'i3 apt profile installs i3-wm in the guarded apt transaction'

hypr_pacman_output=$test_tmp/hypr-pacman-apply.output
run_capture "$hypr_pacman_output" env \
  HOME="$test_tmp/hypr-pacman-apply-home" \
  XDG_STATE_HOME="$test_tmp/hypr-pacman-apply-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_STOP_AFTER_PACKAGES=1 \
  "$bootstrap" --apply --window-manager hypr
if [ "$run_status" -eq 4 ]; then
  pass 'Hyprland pacman profile stops for the user-managed full upgrade'
else
  fail 'Hyprland pacman profile stops for the user-managed full upgrade'
fi
require_contains "$(cat "$hypr_pacman_output")" 'hyprland' \
  'Hyprland is included in the single pacman full-upgrade command'

aerospace_brew_apply_log=$test_tmp/aerospace-brew-apply.commands
run_capture "$test_tmp/aerospace-brew-apply.output" env \
  HOME="$test_tmp/aerospace-brew-apply-home" \
  XDG_STATE_HOME="$test_tmp/aerospace-brew-apply-state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_STOP_AFTER_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$aerospace_brew_apply_log" \
  "$bootstrap" --apply --window-manager aerospace
if [ "$run_status" -eq 0 ]; then
  pass 'Aerospace Homebrew package phase succeeds in the command harness'
else
  fail 'Aerospace Homebrew package phase succeeds in the command harness'
fi
aerospace_brew_apply_commands=$(cat "$aerospace_brew_apply_log" 2>/dev/null || true)
require_contains "$aerospace_brew_apply_commands" \
  'brew install --cask nikitabobko/tap/aerospace' \
  'Aerospace profile installs the official tap cask'
require_contains "$aerospace_brew_apply_commands" \
  'brew install --cask karabiner-elements' \
  'AeroSpace profile installs Karabiner Elements'

fixture_work=$test_tmp/fixture-work
fixture_repo=$test_tmp/fixture.git
mkdir -p \
  "$fixture_work/.codex" \
  "$fixture_work/.config" \
  "$fixture_work/.config/systemd/user" \
  "$fixture_work/Library/Application Support/com.mitchellh.ghostty" \
  "$fixture_work/Library/LaunchAgents"
mkdir -p "$fixture_work/.local/bin"
cp -R "$dotfiles_dir" "$fixture_work/.config/dotfiles"
cp "$workspace_root/.codex/hooks.json" "$fixture_work/.codex/hooks.json"
cp "$workspace_root/.local/bin/t" "$fixture_work/.local/bin/t"
cp -R \
  "$workspace_root/.config/aerospace" \
  "$workspace_root/.config/ghostty" \
  "$workspace_root/.config/herdr" \
  "$workspace_root/.config/hypr" \
  "$workspace_root/.config/i3" \
  "$workspace_root/.config/karabiner" \
  "$workspace_root/.config/launcher" \
  "$workspace_root/.config/macos" \
  "$workspace_root/.config/nvim" \
  "$fixture_work/.config/"
mkdir -p \
  "$fixture_work/.config/tmux/conf/platform" \
  "$fixture_work/.config/tmux/scripts" \
  "$fixture_work/.config/tmux/tests"
cp \
  "$workspace_root/.config/tmux/conf/keys.conf" \
  "$workspace_root/.config/tmux/conf/options.conf" \
  "$workspace_root/.config/tmux/conf/persistence.conf" \
  "$workspace_root/.config/tmux/conf/status.conf" \
  "$fixture_work/.config/tmux/conf/"
cp \
  "$workspace_root/.config/tmux/conf/platform/linux.conf" \
  "$workspace_root/.config/tmux/conf/platform/macos.conf" \
  "$fixture_work/.config/tmux/conf/platform/"
cp "$workspace_root/.config/tmux/tmux.conf" "$fixture_work/.config/tmux/tmux.conf"
cp -R "$workspace_root/.config/tmux/scripts/." "$fixture_work/.config/tmux/scripts/"
cp "$workspace_root/.config/tmux/tests/project-session.sh" \
  "$fixture_work/.config/tmux/tests/project-session.sh"
cp "$workspace_root/.config/systemd/user/tmux-workspace.service" \
  "$fixture_work/.config/systemd/user/tmux-workspace.service"
cp "$workspace_root/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
  "$fixture_work/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
cp "$workspace_root/Library/LaunchAgents/dev.ruohao.tmux-workspace.plist" \
  "$fixture_work/Library/LaunchAgents/dev.ruohao.tmux-workspace.plist"
printf '%s\n' 'fixture nvim' >"$fixture_work/.config/nvim/init.lua"
printf '%s\n' 'fixture tmux' >"$fixture_work/.config/tmux/tmux.conf"
printf '%s\n' 'fixture linux' >"$fixture_work/.config/tmux/conf/platform/linux.conf"
printf '%s\n' 'fixture macos' >"$fixture_work/.config/tmux/conf/platform/macos.conf"
printf '%s\n' 'fixture shared ghostty' >"$fixture_work/.config/ghostty/config.ghostty"
printf '%s\n' 'fixture linux ghostty' >"$fixture_work/.config/ghostty/platform-linux.ghostty"
printf '%s\n' 'fixture macos ghostty' >"$fixture_work/.config/ghostty/platform-macos.ghostty"
printf '%s\n' 'fixture macos entrypoint' \
  >"$fixture_work/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
printf '%s\n' 'excluded fixture documentation' >"$fixture_work/README.md"
git -C "$fixture_work" init -q -b main
git -C "$fixture_work" config user.name 'Bootstrap Test'
git -C "$fixture_work" config user.email bootstrap-test@example.invalid
git -C "$fixture_work" add .
git -C "$fixture_work" commit -qm fixture
git clone -q --bare "$fixture_work" "$fixture_repo"

hypr_home=$test_tmp/hypr-home
hypr_state=$test_tmp/hypr-state
mkdir -p "$hypr_home/.config/hypr" "$hypr_home/.config/launcher"
printf '%s\n' 'legacy hypr config' >"$hypr_home/.config/hypr/hyprland.conf"
printf '%s\n' 'local hypr overrides' >"$hypr_home/.config/hypr/local.lua"
printf '%s\n' 'local Rofi configuration' >"$hypr_home/.config/launcher/rofi.rasi"
run_capture "$test_tmp/hypr-dry-run.output" env \
  HOME="$hypr_home" \
  XDG_STATE_HOME="$hypr_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
  DOTFILES_BOOTSTRAP_TEST_PREPARE_DRY_RUN=1 \
  "$bootstrap" --window-manager hypr --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'Hyprland repository-aware dry-run succeeds'
else
  fail 'Hyprland repository-aware dry-run succeeds'
fi
hypr_dry_output=$(cat "$test_tmp/hypr-dry-run.output")
require_contains "$hypr_dry_output" 'conflict .config/hypr/hyprland.conf' \
  'Hyprland dry-run reports the legacy entrypoint migration'
require_contains "$hypr_dry_output" 'conflict .config/launcher/rofi.rasi' \
  'Hyprland dry-run reports a conflicting launcher configuration'
if [ "$(cat "$hypr_home/.config/hypr/hyprland.conf")" = 'legacy hypr config' ] \
  && [ "$(cat "$hypr_home/.config/launcher/rofi.rasi")" = \
    'local Rofi configuration' ] \
  && [ ! -e "$hypr_home/.cfg" ] \
  && [ ! -e "$hypr_state" ]; then
  pass 'Hyprland dry-run leaves the legacy config and state untouched'
else
  fail 'Hyprland dry-run leaves the legacy config and state untouched'
fi

run_capture "$test_tmp/hypr-apply.output" env \
  HOME="$hypr_home" \
  XDG_STATE_HOME="$hypr_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=window-manager-hypr \
  "$bootstrap" --apply --window-manager hypr \
  --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'Hyprland transactional profile apply succeeds'
else
  fail 'Hyprland transactional profile apply succeeds'
  sed 's/^/  /' "$test_tmp/hypr-apply.output" >&2
fi
hypr_run=$hypr_state/dotfiles-bootstrap/window-manager-hypr
if cmp -s "$fixture_work/.config/hypr/hyprland.lua" \
  "$hypr_home/.config/hypr/hyprland.lua" \
  && cmp -s "$fixture_work/.config/launcher/application-launcher" \
    "$hypr_home/.config/launcher/application-launcher" \
  && cmp -s "$fixture_work/.config/launcher/rofi.rasi" \
    "$hypr_home/.config/launcher/rofi.rasi" \
  && [ ! -e "$hypr_home/.config/macos/spotlight-shortcut" ] \
  && [ ! -e "$hypr_home/.config/i3/config" ] \
  && [ ! -e "$hypr_home/.config/i3/dwindle" ] \
  && [ ! -e "$hypr_home/.config/aerospace/aerospace.toml" ] \
  && [ ! -e "$hypr_home/.config/aerospace/dwindle" ]; then
  pass 'Hyprland apply deploys only the selected manager config'
else
  fail 'Hyprland apply deploys only the selected manager config'
fi
if [ ! -e "$hypr_home/.config/hypr/hyprland.conf" ] \
  && [ "$(cat "$hypr_run/backup/.config/hypr/hyprland.conf" 2>/dev/null || true)" = \
    'legacy hypr config' ]; then
  pass 'Hyprland apply automatically backs up the legacy entrypoint'
else
  fail 'Hyprland apply automatically backs up the legacy entrypoint'
fi
if [ "$(cat "$hypr_run/backup/.config/launcher/rofi.rasi" 2>/dev/null || true)" = \
    'local Rofi configuration' ]; then
  pass 'Hyprland apply automatically backs up a launcher conflict'
else
  fail 'Hyprland apply automatically backs up a launcher conflict'
fi
if [ "$(cat "$hypr_home/.config/hypr/local.lua")" = 'local hypr overrides' ]; then
  pass 'Hyprland apply preserves a preexisting machine-local override'
else
  fail 'Hyprland apply preserves a preexisting machine-local override'
fi
if [ "$(cat "$hypr_run/window-manager" 2>/dev/null || true)" = hypr ]; then
  pass 'Hyprland transaction records the selected profile'
else
  fail 'Hyprland transaction records the selected profile'
fi
run_capture "$test_tmp/hypr-rollback.output" env \
  HOME="$hypr_home" \
  XDG_STATE_HOME="$hypr_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=pacman \
  "$bootstrap" --rollback window-manager-hypr
if [ "$run_status" -eq 0 ]; then
  pass 'Hyprland profile rollback succeeds'
else
  fail 'Hyprland profile rollback succeeds'
fi
if [ "$(cat "$hypr_home/.config/hypr/hyprland.conf" 2>/dev/null || true)" = \
    'legacy hypr config' ] \
  && [ ! -e "$hypr_home/.config/hypr/hyprland.lua" ] \
  && [ ! -e "$hypr_home/.config/launcher/application-launcher" ] \
  && [ "$(cat "$hypr_home/.config/launcher/rofi.rasi" 2>/dev/null || true)" = \
    'local Rofi configuration' ] \
  && [ "$(cat "$hypr_home/.config/hypr/local.lua")" = 'local hypr overrides' ]; then
  pass 'Hyprland rollback restores legacy config and preserves local overrides'
else
  fail 'Hyprland rollback restores legacy config and preserves local overrides'
fi

i3_home=$test_tmp/i3-home
i3_state=$test_tmp/i3-state
run_capture "$test_tmp/i3-apply.output" env \
  HOME="$i3_home" \
  XDG_STATE_HOME="$i3_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=window-manager-i3 \
  "$bootstrap" --apply --window-manager i3 \
  --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'i3 transactional profile apply succeeds'
else
  fail 'i3 transactional profile apply succeeds'
  sed 's/^/  /' "$test_tmp/i3-apply.output" >&2
fi
if cmp -s "$fixture_work/.config/i3/config" "$i3_home/.config/i3/config" \
  && cmp -s "$fixture_work/.config/i3/dwindle" \
    "$i3_home/.config/i3/dwindle" \
  && [ -x "$i3_home/.config/i3/dwindle" ] \
  && [ -f "$i3_home/.config/i3/local.conf" ] \
  && [ ! -e "$i3_home/.config/hypr/hyprland.lua" ] \
  && [ ! -e "$i3_home/.config/aerospace/aerospace.toml" ] \
  && [ ! -e "$i3_home/.config/aerospace/dwindle" ]; then
  pass 'i3 apply creates its config, helper, and local override only'
else
  fail 'i3 apply creates its config, helper, and local override only'
fi
run_capture "$test_tmp/i3-rollback.output" env \
  HOME="$i3_home" \
  XDG_STATE_HOME="$i3_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  "$bootstrap" --rollback window-manager-i3
if [ "$run_status" -eq 0 ]; then
  pass 'i3 profile rollback succeeds'
else
  fail 'i3 profile rollback succeeds'
fi
if [ ! -e "$i3_home/.config/i3/config" ] \
  && [ ! -e "$i3_home/.config/i3/dwindle" ] \
  && [ ! -e "$i3_home/.config/i3/local.conf" ]; then
  pass 'i3 rollback removes the deployed config and generated local override'
else
  fail 'i3 rollback removes the deployed config and generated local override'
fi

aerospace_home=$test_tmp/aerospace-home
aerospace_state=$test_tmp/aerospace-state
aerospace_spotlight_state=$test_tmp/aerospace-spotlight-state
aerospace_window_drag_state=$test_tmp/aerospace-window-drag-state
mkdir -p \
  "$aerospace_home/.config/aerospace" \
  "$aerospace_home/.config/karabiner" \
  "$aerospace_spotlight_state" \
  "$aerospace_window_drag_state"
printf '%s\n' false >"$aerospace_window_drag_state/value"
printf '%s\n' 'legacy Karabiner configuration' \
  >"$aerospace_home/.config/karabiner/karabiner.json"
printf '%s\n' 'original Aerospace Spotlight shortcut' \
  >"$aerospace_spotlight_state/entry"
printf '%s\n' 'legacy aerospace config' >"$aerospace_home/.aerospace.toml"
printf '%s\n' '#!/bin/sh' 'echo local aerospace' \
  >"$aerospace_home/.config/aerospace/local.sh"
chmod 0700 "$aerospace_home/.config/aerospace/local.sh"
run_capture "$test_tmp/aerospace-apply.output" env \
  HOME="$aerospace_home" \
  XDG_STATE_HOME="$aerospace_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$aerospace_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$aerospace_window_drag_state" \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=window-manager-aerospace \
  "$bootstrap" --apply --window-manager aerospace \
  --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'Aerospace transactional profile apply succeeds in the macOS simulation'
else
  fail 'Aerospace transactional profile apply succeeds in the macOS simulation'
  sed 's/^/  /' "$test_tmp/aerospace-apply.output" >&2
fi
aerospace_run=$aerospace_state/dotfiles-bootstrap/window-manager-aerospace
if [ "$(cat "$aerospace_spotlight_state/entry" 2>/dev/null || true)" = \
    '{"enabled":true,"value":{"parameters":[59,41,1179648],"type":"standard"}}' ] \
  && [ "$(cat "$aerospace_run/preferences/spotlight-shortcut/before.entry" 2>/dev/null || true)" = \
    'original Aerospace Spotlight shortcut' ] \
  && [ "$(cat "$aerospace_run/preferences/spotlight-shortcut/status" 2>/dev/null || true)" = \
    applied ]; then
  pass 'macOS apply journals and sets the native Spotlight shortcut'
else
  fail 'macOS apply journals and sets the native Spotlight shortcut'
fi
if [ "$(cat "$aerospace_window_drag_state/value" 2>/dev/null || true)" = true ] \
  && [ "$(cat "$aerospace_run/preferences/window-drag-gesture/before.value" 2>/dev/null || true)" = false ] \
  && [ -f "$aerospace_run/preferences/window-drag-gesture/before.present" ] \
  && [ "$(cat "$aerospace_run/preferences/window-drag-gesture/after.value" 2>/dev/null || true)" = true ] \
  && [ "$(cat "$aerospace_run/preferences/window-drag-gesture/status" 2>/dev/null || true)" = applied ]; then
  pass 'AeroSpace apply journals and enables the native window-drag preference'
else
  fail 'AeroSpace apply journals and enables the native window-drag preference'
fi
if cmp -s "$fixture_work/.config/aerospace/aerospace.toml" \
  "$aerospace_home/.config/aerospace/aerospace.toml" \
  && cmp -s "$fixture_work/.config/aerospace/dwindle" \
    "$aerospace_home/.config/aerospace/dwindle" \
  && cmp -s "$fixture_work/.config/karabiner/karabiner.json" \
    "$aerospace_home/.config/karabiner/karabiner.json" \
  && cmp -s "$fixture_work/.config/macos/spotlight-shortcut" \
    "$aerospace_home/.config/macos/spotlight-shortcut" \
  && cmp -s "$fixture_work/.config/macos/window-drag-gesture" \
    "$aerospace_home/.config/macos/window-drag-gesture" \
  && [ -x "$aerospace_run/preference-tools/spotlight-shortcut" ] \
  && cmp -s "$fixture_work/.config/macos/spotlight-shortcut" \
    "$aerospace_run/preference-tools/spotlight-shortcut" \
  && [ -x "$aerospace_run/preference-tools/window-drag-gesture" ] \
  && cmp -s "$fixture_work/.config/macos/window-drag-gesture" \
    "$aerospace_run/preference-tools/window-drag-gesture" \
  && [ ! -e "$aerospace_home/.config/launcher/application-launcher" ] \
  && [ -x "$aerospace_home/.config/aerospace/dwindle" ] \
  && [ ! -e "$aerospace_home/.config/hypr/hyprland.lua" ] \
  && [ ! -e "$aerospace_home/.config/i3/config" ] \
  && [ ! -e "$aerospace_home/.config/i3/dwindle" ]; then
  pass 'Aerospace apply deploys only the selected manager config'
else
  fail 'Aerospace apply deploys only the selected manager config'
fi
if [ ! -e "$aerospace_home/.aerospace.toml" ] \
  && [ "$(cat "$aerospace_run/backup/.aerospace.toml" 2>/dev/null || true)" = \
    'legacy aerospace config' ]; then
  pass 'Aerospace apply automatically backs up the legacy config location'
else
  fail 'Aerospace apply automatically backs up the legacy config location'
fi
if [ "$(cat "$aerospace_run/backup/.config/karabiner/karabiner.json" 2>/dev/null || true)" = \
    'legacy Karabiner configuration' ]; then
  pass 'AeroSpace apply backs up a conflicting Karabiner configuration'
else
  fail 'AeroSpace apply backs up a conflicting Karabiner configuration'
fi
if grep -Fq 'echo local aerospace' \
  "$aerospace_home/.config/aerospace/local.sh"; then
  pass 'Aerospace apply preserves a preexisting machine-local hook'
else
  fail 'Aerospace apply preserves a preexisting machine-local hook'
fi
require_contains "$(cat "$test_tmp/aerospace-apply.output")" \
  'open Karabiner-Elements and complete its required macOS setup' \
  'AeroSpace apply reports the manual permission step without claiming completion'

aerospace_drag_journal=$aerospace_run/preferences/window-drag-gesture
aerospace_drag_journal_saved=$aerospace_run/preferences/window-drag-gesture.saved
mv "$aerospace_drag_journal" "$aerospace_drag_journal_saved"
printf '%s\n' 'invalid window-drag journal' >"$aerospace_drag_journal"
run_capture "$test_tmp/aerospace-rollback-invalid-file.output" env \
  HOME="$aerospace_home" \
  XDG_STATE_HOME="$aerospace_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$aerospace_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$aerospace_window_drag_state" \
  "$bootstrap" --rollback window-manager-aerospace
if [ "$run_status" -ne 0 ]; then
  pass 'rollback rejects a regular-file window-drag preference journal'
else
  fail 'rollback rejects a regular-file window-drag preference journal'
fi
require_contains "$(cat "$test_tmp/aerospace-rollback-invalid-file.output")" \
  'bootstrap: transaction has invalid window-drag-gesture preference journal' \
  'regular-file preference preflight reports the invalid window-drag journal'
if [ "$(cat "$aerospace_run/status" 2>/dev/null || true)" = complete ] \
  && [ -d "$aerospace_home/.cfg" ] \
  && cmp -s "$fixture_work/.config/karabiner/karabiner.json" \
    "$aerospace_home/.config/karabiner/karabiner.json" \
  && [ "$(cat "$aerospace_spotlight_state/entry" 2>/dev/null || true)" = \
    '{"enabled":true,"value":{"parameters":[59,41,1179648],"type":"standard"}}' ] \
  && [ "$(cat "$aerospace_window_drag_state/value" 2>/dev/null || true)" = true ]; then
  pass 'regular-file preference preflight leaves the transaction untouched'
else
  fail 'regular-file preference preflight leaves the transaction untouched'
fi
rm "$aerospace_drag_journal"
ln -s "$aerospace_drag_journal_saved" "$aerospace_drag_journal"
run_capture "$test_tmp/aerospace-rollback-invalid-symlink.output" env \
  HOME="$aerospace_home" \
  XDG_STATE_HOME="$aerospace_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$aerospace_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$aerospace_window_drag_state" \
  "$bootstrap" --rollback window-manager-aerospace
if [ "$run_status" -ne 0 ]; then
  pass 'rollback rejects a symlinked window-drag preference journal'
else
  fail 'rollback rejects a symlinked window-drag preference journal'
fi
require_contains "$(cat "$test_tmp/aerospace-rollback-invalid-symlink.output")" \
  'bootstrap: transaction has invalid window-drag-gesture preference journal' \
  'symlink preference preflight reports the invalid window-drag journal'
if [ "$(cat "$aerospace_run/status" 2>/dev/null || true)" = complete ] \
  && [ -d "$aerospace_home/.cfg" ] \
  && cmp -s "$fixture_work/.config/karabiner/karabiner.json" \
    "$aerospace_home/.config/karabiner/karabiner.json" \
  && [ "$(cat "$aerospace_spotlight_state/entry" 2>/dev/null || true)" = \
    '{"enabled":true,"value":{"parameters":[59,41,1179648],"type":"standard"}}' ] \
  && [ "$(cat "$aerospace_window_drag_state/value" 2>/dev/null || true)" = true ]; then
  pass 'symlink preference preflight leaves the transaction untouched'
else
  fail 'symlink preference preflight leaves the transaction untouched'
fi
rm "$aerospace_drag_journal"
mv "$aerospace_drag_journal_saved" "$aerospace_drag_journal"

rm \
  "$aerospace_home/.config/macos/spotlight-shortcut" \
  "$aerospace_home/.config/macos/window-drag-gesture"
if [ ! -e "$aerospace_home/.config/macos/spotlight-shortcut" ] \
  && [ ! -e "$aerospace_home/.config/macos/window-drag-gesture" ] \
  && [ -x "$aerospace_run/preference-tools/spotlight-shortcut" ] \
  && [ -x "$aerospace_run/preference-tools/window-drag-gesture" ]; then
  pass 'AeroSpace rollback remains independent of deployed preference helpers'
else
  fail 'AeroSpace rollback remains independent of deployed preference helpers'
fi
run_capture "$test_tmp/aerospace-rollback-interrupted-drag.output" env \
  HOME="$aerospace_home" \
  XDG_STATE_HOME="$aerospace_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$aerospace_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$aerospace_window_drag_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STOP_AFTER_RESTORE_WRITE=1 \
  "$bootstrap" --rollback window-manager-aerospace
if [ "$run_status" -ne 0 ]; then
  pass 'AeroSpace rollback exposes an interrupted window-drag restore'
else
  fail 'AeroSpace rollback exposes an interrupted window-drag restore'
fi
if [ "$(cat "$aerospace_run/status" 2>/dev/null || true)" = rolling-back ] \
  && [ "$(cat "$aerospace_run/preferences/window-drag-gesture/status" 2>/dev/null || true)" = preparing ] \
  && [ "$(cat "$aerospace_window_drag_state/value" 2>/dev/null || true)" = false ] \
  && [ "$(cat "$aerospace_run/preferences/spotlight-shortcut/status" 2>/dev/null || true)" = applied ] \
  && [ "$(cat "$aerospace_spotlight_state/entry" 2>/dev/null || true)" = \
    '{"enabled":true,"value":{"parameters":[59,41,1179648],"type":"standard"}}' ] \
  && [ -d "$aerospace_home/.cfg" ]; then
  pass 'AeroSpace rollback restores window drag before Spotlight and configuration'
else
  fail 'AeroSpace rollback restores window drag before Spotlight and configuration'
fi

run_capture "$test_tmp/aerospace-rollback.output" env \
  HOME="$aerospace_home" \
  XDG_STATE_HOME="$aerospace_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$aerospace_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$aerospace_window_drag_state" \
  "$bootstrap" --rollback window-manager-aerospace
if [ "$run_status" -eq 0 ]; then
  pass 'Aerospace profile rollback succeeds in the macOS simulation'
else
  fail 'Aerospace profile rollback succeeds in the macOS simulation'
fi
if [ "$(cat "$aerospace_home/.aerospace.toml" 2>/dev/null || true)" = \
    'legacy aerospace config' ] \
  && [ ! -e "$aerospace_home/.config/aerospace/aerospace.toml" ] \
  && [ ! -e "$aerospace_home/.config/aerospace/dwindle" ] \
  && [ "$(cat "$aerospace_home/.config/karabiner/karabiner.json" 2>/dev/null || true)" = \
    'legacy Karabiner configuration' ] \
  && [ ! -e "$aerospace_home/.config/macos/spotlight-shortcut" ] \
  && [ ! -e "$aerospace_home/.config/macos/window-drag-gesture" ] \
  && [ "$(cat "$aerospace_window_drag_state/value" 2>/dev/null || true)" = false ] \
  && [ "$(cat "$aerospace_spotlight_state/entry" 2>/dev/null || true)" = \
    'original Aerospace Spotlight shortcut' ] \
  && grep -Fq 'echo local aerospace' \
    "$aerospace_home/.config/aerospace/local.sh"; then
  pass 'Aerospace rollback restores legacy config and preserves its local hook'
else
  fail 'Aerospace rollback restores legacy config and preserves its local hook'
fi

aerospace_absent_home=$test_tmp/aerospace-absent-home
aerospace_absent_state=$test_tmp/aerospace-absent-state
aerospace_absent_spotlight_state=$test_tmp/aerospace-absent-spotlight-state
aerospace_absent_drag_state=$test_tmp/aerospace-absent-drag-state
mkdir -p "$aerospace_absent_spotlight_state" "$aerospace_absent_drag_state"
run_capture "$test_tmp/aerospace-absent-apply.output" env \
  HOME="$aerospace_absent_home" \
  XDG_STATE_HOME="$aerospace_absent_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$aerospace_absent_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$aerospace_absent_drag_state" \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=window-drag-absent \
  "$bootstrap" --apply --window-manager aerospace \
  --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ] \
  && [ "$(cat "$aerospace_absent_drag_state/value" 2>/dev/null || true)" = true ] \
  && [ ! -e "$aerospace_absent_state/dotfiles-bootstrap/window-drag-absent/preferences/window-drag-gesture/before.present" ]; then
  pass 'AeroSpace apply journals and enables an initially absent drag preference'
else
  fail 'AeroSpace apply journals and enables an initially absent drag preference'
fi
run_capture "$test_tmp/aerospace-absent-rollback.output" env \
  HOME="$aerospace_absent_home" \
  XDG_STATE_HOME="$aerospace_absent_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$aerospace_absent_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$aerospace_absent_drag_state" \
  "$bootstrap" --rollback window-drag-absent
if [ "$run_status" -eq 0 ] && [ ! -e "$aerospace_absent_drag_state/value" ]; then
  pass 'AeroSpace rollback removes an originally absent drag preference'
else
  fail 'AeroSpace rollback removes an originally absent drag preference'
fi

preference_order_home=$test_tmp/preference-order-home
preference_order_state=$test_tmp/preference-order-state
preference_order_spotlight_state=$test_tmp/preference-order-spotlight-state
preference_order_drag_state=$test_tmp/preference-order-drag-state
mkdir -p "$preference_order_spotlight_state" "$preference_order_drag_state"
printf '%s\n' 'original preference-order Spotlight shortcut' \
  >"$preference_order_spotlight_state/entry"
printf '%s\n' false >"$preference_order_drag_state/value"
run_capture "$test_tmp/preference-apply-order.output" env \
  HOME="$preference_order_home" \
  XDG_STATE_HOME="$preference_order_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$preference_order_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$preference_order_drag_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_FAIL_WRITE=1 \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=preference-apply-order \
  "$bootstrap" --apply --window-manager aerospace \
  --repo "$fixture_repo" --ref main
preference_order_run=$preference_order_state/dotfiles-bootstrap/preference-apply-order
if [ "$run_status" -ne 0 ] \
  && [ "$(cat "$preference_order_run/preferences/spotlight-shortcut/status" 2>/dev/null || true)" = restored ] \
  && [ "$(cat "$preference_order_spotlight_state/entry" 2>/dev/null || true)" = \
    'original preference-order Spotlight shortcut' ] \
  && [ "$(cat "$preference_order_run/preferences/window-drag-gesture/status" 2>/dev/null || true)" = failed ] \
  && [ "$(cat "$preference_order_drag_state/value" 2>/dev/null || true)" = false ] \
  && [ "$(cat "$preference_order_run/status" 2>/dev/null || true)" = rolled-back ]; then
  pass 'AeroSpace applies Spotlight before attempting the window-drag preference'
else
  fail 'AeroSpace applies Spotlight before attempting the window-drag preference'
fi

mac_failure_home=$test_tmp/mac-failure-home
mac_failure_state=$test_tmp/mac-failure-state
mac_failure_spotlight_state=$test_tmp/mac-failure-spotlight-state
mkdir -p "$mac_failure_spotlight_state"
printf '%s\n' 'Spotlight before failed bootstrap' \
  >"$mac_failure_spotlight_state/entry"
run_capture "$test_tmp/mac-failure.output" env \
  HOME="$mac_failure_home" \
  XDG_STATE_HOME="$mac_failure_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$mac_failure_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=mac-forced-failure \
  DOTFILES_BOOTSTRAP_TEST_FAIL_AFTER_CHECKOUT=1 \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -ne 0 ]; then
  pass 'forced macOS failure exits unsuccessfully after preference application'
else
  fail 'forced macOS failure exits unsuccessfully after preference application'
fi
if [ "$(cat "$mac_failure_spotlight_state/entry" 2>/dev/null || true)" = \
    'Spotlight before failed bootstrap' ] \
  && [ "$(cat "$mac_failure_state/dotfiles-bootstrap/mac-forced-failure/status" 2>/dev/null || true)" = \
    rolled-back ] \
  && [ ! -e "$mac_failure_home/.cfg" ]; then
  pass 'automatic rollback restores macOS preferences and deployed files'
else
  fail 'automatic rollback restores macOS preferences and deployed files'
fi

drag_failure_home=$test_tmp/drag-failure-home
drag_failure_state=$test_tmp/drag-failure-state
drag_failure_spotlight_state=$test_tmp/drag-failure-spotlight-state
drag_failure_preference_state=$test_tmp/drag-failure-preference-state
mkdir -p "$drag_failure_spotlight_state" "$drag_failure_preference_state"
printf '%s\n' false >"$drag_failure_preference_state/value"
run_capture "$test_tmp/drag-failure.output" env \
  HOME="$drag_failure_home" \
  XDG_STATE_HOME="$drag_failure_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$drag_failure_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$drag_failure_preference_state" \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=window-drag-forced-failure \
  DOTFILES_BOOTSTRAP_TEST_FAIL_AFTER_CHECKOUT=1 \
  "$bootstrap" --apply --window-manager aerospace \
  --repo "$fixture_repo" --ref main
if [ "$run_status" -ne 0 ]; then
  pass 'forced AeroSpace failure exits after applying the drag preference'
else
  fail 'forced AeroSpace failure exits after applying the drag preference'
fi
if [ "$(cat "$drag_failure_preference_state/value" 2>/dev/null || true)" = false ] \
  && [ "$(cat "$drag_failure_state/dotfiles-bootstrap/window-drag-forced-failure/status" 2>/dev/null || true)" = rolled-back ] \
  && [ ! -e "$drag_failure_home/.cfg" ] \
  && [ ! -e "$drag_failure_home/.config/karabiner/karabiner.json" ]; then
  pass 'automatic rollback restores the drag preference and Karabiner configuration'
else
  fail 'automatic rollback restores the drag preference and Karabiner configuration'
fi

mac_conflict_home=$test_tmp/mac-conflict-home
mac_conflict_state=$test_tmp/mac-conflict-state
mac_conflict_spotlight_state=$test_tmp/mac-conflict-spotlight-state
mkdir -p "$mac_conflict_spotlight_state"
printf '%s\n' 'Spotlight before conflict test' \
  >"$mac_conflict_spotlight_state/entry"
run_capture "$test_tmp/mac-conflict-apply.output" env \
  HOME="$mac_conflict_home" \
  XDG_STATE_HOME="$mac_conflict_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$mac_conflict_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=mac-preference-conflict \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
printf '%s\n' 'Spotlight changed after bootstrap' \
  >"$mac_conflict_spotlight_state/entry"
run_capture "$test_tmp/mac-conflict-rollback.output" env \
  HOME="$mac_conflict_home" \
  XDG_STATE_HOME="$mac_conflict_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$mac_conflict_spotlight_state" \
  "$bootstrap" --rollback mac-preference-conflict
if [ "$run_status" -ne 0 ]; then
  pass 'manual rollback reports a later Spotlight shortcut conflict'
else
  fail 'manual rollback reports a later Spotlight shortcut conflict'
fi
if [ "$(cat "$mac_conflict_spotlight_state/entry" 2>/dev/null || true)" = \
    'Spotlight changed after bootstrap' ]; then
  pass 'conflicted rollback preserves the later Spotlight shortcut'
else
  fail 'conflicted rollback preserves the later Spotlight shortcut'
fi
if [ "$(cat "$mac_conflict_state/dotfiles-bootstrap/mac-preference-conflict/status" 2>/dev/null || true)" = \
    complete ] \
  && [ -d "$mac_conflict_home/.cfg" ]; then
  pass 'preference conflict stops rollback before deployed files are changed'
else
  fail 'preference conflict stops rollback before deployed files are changed'
fi

drag_conflict_home=$test_tmp/drag-conflict-home
drag_conflict_state=$test_tmp/drag-conflict-state
drag_conflict_spotlight_state=$test_tmp/drag-conflict-spotlight-state
drag_conflict_preference_state=$test_tmp/drag-conflict-preference-state
mkdir -p "$drag_conflict_spotlight_state" "$drag_conflict_preference_state"
run_capture "$test_tmp/drag-conflict-apply.output" env \
  HOME="$drag_conflict_home" \
  XDG_STATE_HOME="$drag_conflict_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$drag_conflict_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$drag_conflict_preference_state" \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=window-drag-conflict \
  "$bootstrap" --apply --window-manager aerospace \
  --repo "$fixture_repo" --ref main
printf '%s\n' false >"$drag_conflict_preference_state/value"
run_capture "$test_tmp/drag-conflict-rollback.output" env \
  HOME="$drag_conflict_home" \
  XDG_STATE_HOME="$drag_conflict_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$drag_conflict_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$drag_conflict_preference_state" \
  "$bootstrap" --rollback window-drag-conflict
if [ "$run_status" -ne 0 ]; then
  pass 'manual rollback reports a later window-drag preference conflict'
else
  fail 'manual rollback reports a later window-drag preference conflict'
fi
if [ "$(cat "$drag_conflict_preference_state/value" 2>/dev/null || true)" = false ]; then
  pass 'conflicted rollback preserves the later window-drag preference'
else
  fail 'conflicted rollback preserves the later window-drag preference'
fi
if [ "$(cat "$drag_conflict_state/dotfiles-bootstrap/window-drag-conflict/status" 2>/dev/null || true)" = complete ] \
  && [ -d "$drag_conflict_home/.cfg" ]; then
  pass 'drag-preference conflict stops rollback before deployed files change'
else
  fail 'drag-preference conflict stops rollback before deployed files change'
fi

transaction_home=$test_tmp/transaction-home
transaction_state=$test_tmp/transaction-state
transaction_service_log=$test_tmp/transaction-service.commands
mkdir -p \
  "$transaction_home/.config/nvim" \
  "$transaction_home/.config/systemd/user" \
  "$transaction_home/.config/tmux" \
  "$transaction_home/.local/share"
printf '%s\n' 'original nvim' >"$transaction_home/.config/nvim/init.lua"
printf '%s\n' 'original service unit' \
  >"$transaction_home/.config/systemd/user/tmux-workspace.service"
printf '%s\n' 'keep local-only' >"$transaction_home/.config/nvim/local-only.lua"
printf '%s\n' 'original tmux target' >"$transaction_home/.local/share/original-tmux.conf"
ln -s "$transaction_home/.local/share/original-tmux.conf" "$transaction_home/.config/tmux/tmux.conf"
run_capture "$test_tmp/transaction-apply.output" env \
  HOME="$transaction_home" \
  XDG_STATE_HOME="$transaction_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=transaction-success \
  DOTFILES_BOOTSTRAP_TEST_SERVICE_ENABLED=true \
  DOTFILES_BOOTSTRAP_TEST_SERVICE_ACTIVE=true \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$transaction_service_log" \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'transactional configuration apply succeeds'
else
  fail 'transactional configuration apply succeeds'
  sed 's/^/  /' "$test_tmp/transaction-apply.output" >&2
fi
transaction_service_commands=$(cat "$transaction_service_log" 2>/dev/null || true)
require_contains "$transaction_service_commands" \
  'systemctl --user daemon-reload' \
  'transactional apply reloads the systemd user manager'
require_contains "$transaction_service_commands" \
  'systemctl --user enable --now tmux-workspace.service' \
  'transactional apply enables and starts the workspace service'
if [ -L "$transaction_home/.local/bin/tmux-workspace" ] \
  && [ "$(readlink "$transaction_home/.local/bin/tmux-workspace")" = \
    "$transaction_home/.config/tmux/scripts/workspace" ]; then
  pass 'transactional apply installs the workspace helper command link'
else
  fail 'transactional apply installs the workspace helper command link'
fi
transaction_run=$transaction_state/dotfiles-bootstrap/transaction-success
if [ "$(cat "$transaction_run/service-platform" 2>/dev/null || true)" = linux ] \
  && [ "$(cat "$transaction_run/service-was-installed" 2>/dev/null || true)" = true ] \
  && [ "$(cat "$transaction_run/service-was-enabled" 2>/dev/null || true)" = true ] \
  && [ "$(cat "$transaction_run/service-was-active" 2>/dev/null || true)" = true ]; then
  pass 'transaction records the previous workspace service state'
else
  fail 'transaction records the previous workspace service state'
fi
if [ "$(cat "$transaction_run/backup/.config/nvim/init.lua" 2>/dev/null || true)" = 'original nvim' ]; then
  pass 'conflicting file is automatically backed up'
else
  fail 'conflicting file is automatically backed up'
fi
if [ -L "$transaction_run/backup/.config/tmux/tmux.conf" ]; then
  pass 'conflicting symlink is backed up without dereferencing it'
else
  fail 'conflicting symlink is backed up without dereferencing it'
fi
if [ "$(cat "$transaction_home/.config/nvim/init.lua" 2>/dev/null || true)" = 'fixture nvim' ] \
  && [ ! -L "$transaction_home/.config/tmux/tmux.conf" ]; then
  pass 'selected repository configuration replaces conflicts'
else
  fail 'selected repository configuration replaces conflicts'
fi
if [ "$(cat "$transaction_home/.config/nvim/local-only.lua" 2>/dev/null || true)" = 'keep local-only' ]; then
  pass 'untracked local files under selected directories are preserved'
else
  fail 'untracked local files under selected directories are preserved'
fi
if [ "$(cat "$transaction_run/status" 2>/dev/null || true)" = complete ] \
  && [ "$(cat "$transaction_state/dotfiles-bootstrap/latest" 2>/dev/null || true)" = transaction-success ]; then
  pass 'completed transaction and latest run are journaled'
else
  fail 'completed transaction and latest run are journaled'
fi

: >"$transaction_service_log"
run_capture "$test_tmp/transaction-rollback.output" env \
  HOME="$transaction_home" \
  XDG_STATE_HOME="$transaction_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$transaction_service_log" \
  "$bootstrap" --rollback transaction-success
if [ "$run_status" -eq 0 ]; then
  pass 'manual rollback by run ID succeeds'
else
  fail 'manual rollback by run ID succeeds'
fi
transaction_rollback_service_commands=$(cat "$transaction_service_log" 2>/dev/null || true)
require_contains "$transaction_rollback_service_commands" \
  'systemctl --user disable --now tmux-workspace.service' \
  'rollback stops and disables the deployed workspace service'
require_contains "$transaction_rollback_service_commands" \
  'systemctl --user daemon-reload' \
  'rollback reloads the restored systemd user configuration'
if printf '%s\n' "$transaction_rollback_service_commands" \
    | grep -Fqx 'systemctl --user enable tmux-workspace.service' \
  && printf '%s\n' "$transaction_rollback_service_commands" \
    | grep -Fqx 'systemctl --user start tmux-workspace.service'; then
  pass 'rollback restores the previous enabled and active service state'
else
  fail 'rollback restores the previous enabled and active service state'
fi
if [ "$(cat "$transaction_home/.config/nvim/init.lua" 2>/dev/null || true)" = 'original nvim' ]; then
  pass 'rollback restores the original conflicting file'
else
  fail 'rollback restores the original conflicting file'
fi
if [ -L "$transaction_home/.config/tmux/tmux.conf" ] \
  && [ "$(readlink "$transaction_home/.config/tmux/tmux.conf")" = "$transaction_home/.local/share/original-tmux.conf" ]; then
  pass 'rollback restores the original symlink'
else
  fail 'rollback restores the original symlink'
fi
if [ ! -e "$transaction_home/.config/tmux/conf/platform/linux.conf" ] \
  && [ ! -e "$transaction_home/.cfg" ] \
  && [ ! -e "$transaction_home/.local/bin/tmux-workspace" ] \
  && [ "$(cat "$transaction_home/.config/systemd/user/tmux-workspace.service" 2>/dev/null || true)" = \
    'original service unit' ]; then
  pass 'rollback removes newly deployed files and repository metadata'
else
  fail 'rollback removes newly deployed files and repository metadata'
fi
if [ "$(cat "$transaction_home/.config/nvim/local-only.lua" 2>/dev/null || true)" = 'keep local-only' ]; then
  pass 'rollback preserves unrelated local files'
else
  fail 'rollback preserves unrelated local files'
fi
rollback_output=$(cat "$test_tmp/transaction-rollback.output")
require_contains "$rollback_output" 'Packages are not uninstalled' 'rollback reports that package changes are retained'

service_failure_home=$test_tmp/service-failure-home
service_failure_state=$test_tmp/service-failure-state
run_capture "$test_tmp/service-failure.output" env \
  HOME="$service_failure_home" \
  XDG_STATE_HOME="$service_failure_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=service-activation-failure \
  DOTFILES_BOOTSTRAP_TEST_SERVICE_FAIL=enable \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -ne 0 ]; then
  pass 'service activation failure exits unsuccessfully'
else
  fail 'service activation failure exits unsuccessfully'
fi
if [ "$(cat "$service_failure_state/dotfiles-bootstrap/service-activation-failure/status" 2>/dev/null || true)" = \
    rolled-back ] \
  && [ ! -e "$service_failure_home/.cfg" ] \
  && [ ! -e "$service_failure_home/.local/bin/tmux-workspace" ] \
  && [ ! -e "$service_failure_home/.config/systemd/user/tmux-workspace.service" ]; then
  pass 'service activation failure rolls back deployed configuration'
else
  fail 'service activation failure rolls back deployed configuration'
fi

run_capture "$test_tmp/transaction-rollback-again.output" env \
  HOME="$transaction_home" \
  XDG_STATE_HOME="$transaction_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  "$bootstrap" --rollback transaction-success
if [ "$run_status" -eq 0 ]; then
  pass 'repeating a completed rollback is idempotent'
else
  fail 'repeating a completed rollback is idempotent'
fi

latest_home=$test_tmp/latest-home
latest_state=$test_tmp/latest-state
run_capture "$test_tmp/latest-apply.output" env \
  HOME="$latest_home" \
  XDG_STATE_HOME="$latest_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=latest-success \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
run_capture "$test_tmp/latest-rollback.output" env \
  HOME="$latest_home" \
  XDG_STATE_HOME="$latest_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  "$bootstrap" --rollback latest
if [ "$run_status" -eq 0 ]; then
  pass 'rollback latest resolves and restores the newest run'
else
  fail 'rollback latest resolves and restores the newest run'
fi
if [ ! -e "$latest_home/.cfg" ] && [ ! -e "$latest_home/.config/nvim/init.lua" ]; then
  pass 'latest rollback removes files created in a fresh home'
else
  fail 'latest rollback removes files created in a fresh home'
fi

parent_home=$test_tmp/parent-home
parent_state=$test_tmp/parent-state
mkdir -p "$parent_home/.config"
printf '%s\n' 'original blocking parent' >"$parent_home/.config/tmux"
run_capture "$test_tmp/parent-apply.output" env \
  HOME="$parent_home" \
  XDG_STATE_HOME="$parent_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=parent-conflict \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'apply backs up a non-directory parent blocking selected files'
else
  fail 'apply backs up a non-directory parent blocking selected files'
fi
if [ "$(cat "$parent_state/dotfiles-bootstrap/parent-conflict/backup/.config/tmux" 2>/dev/null || true)" = 'original blocking parent' ]; then
  pass 'blocking parent is retained in the transaction backup'
else
  fail 'blocking parent is retained in the transaction backup'
fi
run_capture "$test_tmp/parent-rollback.output" env \
  HOME="$parent_home" \
  XDG_STATE_HOME="$parent_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  "$bootstrap" --rollback parent-conflict
if [ "$(cat "$parent_home/.config/tmux" 2>/dev/null || true)" = 'original blocking parent' ]; then
  pass 'rollback restores a blocking parent conflict'
else
  fail 'rollback restores a blocking parent conflict'
fi

failure_home=$test_tmp/failure-home
failure_state=$test_tmp/failure-state
mkdir -p "$failure_home/.config/nvim"
printf '%s\n' 'failure original' >"$failure_home/.config/nvim/init.lua"
run_capture "$test_tmp/failure-apply.output" env \
  HOME="$failure_home" \
  XDG_STATE_HOME="$failure_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=forced-failure \
  DOTFILES_BOOTSTRAP_TEST_FAIL_AFTER_CHECKOUT=1 \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -ne 0 ]; then
  pass 'a forced post-checkout failure exits unsuccessfully'
else
  fail 'a forced post-checkout failure exits unsuccessfully'
fi
if [ "$(cat "$failure_home/.config/nvim/init.lua" 2>/dev/null || true)" = 'failure original' ] \
  && [ ! -e "$failure_home/.cfg" ]; then
  pass 'failure trap automatically restores configuration and metadata'
else
  fail 'failure trap automatically restores configuration and metadata'
fi
if [ "$(cat "$failure_state/dotfiles-bootstrap/forced-failure/status" 2>/dev/null || true)" = rolled-back ]; then
  pass 'automatic rollback is recorded in the transaction journal'
else
  fail 'automatic rollback is recorded in the transaction journal'
fi

signal_home=$test_tmp/signal-home
signal_state=$test_tmp/signal-state
mkdir -p "$signal_home/.config/nvim"
printf '%s\n' 'signal original' >"$signal_home/.config/nvim/init.lua"
run_capture "$test_tmp/signal-apply.output" env \
  HOME="$signal_home" \
  XDG_STATE_HOME="$signal_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=forced-signal \
  DOTFILES_BOOTSTRAP_TEST_SIGNAL_AFTER_CHECKOUT=TERM \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 143 ]; then
  pass 'termination signal preserves the conventional exit status'
else
  fail 'termination signal preserves the conventional exit status'
fi
if [ "$(cat "$signal_home/.config/nvim/init.lua" 2>/dev/null || true)" = 'signal original' ] \
  && [ ! -e "$signal_home/.cfg" ]; then
  pass 'termination trap automatically restores configuration and metadata'
else
  fail 'termination trap automatically restores configuration and metadata'
fi

dry_conflict_home=$test_tmp/dry-conflict-home
dry_conflict_state=$test_tmp/dry-conflict-state
mkdir -p "$dry_conflict_home/.config/nvim"
printf '%s\n' 'dry-run conflict' >"$dry_conflict_home/.config/nvim/init.lua"
run_capture "$test_tmp/dry-conflict.output" env \
  HOME="$dry_conflict_home" \
  XDG_STATE_HOME="$dry_conflict_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_PREPARE_DRY_RUN=1 \
  "$bootstrap" --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'repository-aware dry-run succeeds'
else
  fail 'repository-aware dry-run succeeds'
fi
dry_conflict_output=$(cat "$test_tmp/dry-conflict.output")
require_contains "$dry_conflict_output" 'conflict .config/nvim/init.lua' 'dry-run reports an existing selected-file conflict'
if [ ! -e "$dry_conflict_home/.cfg" ] && [ ! -e "$dry_conflict_state" ]; then
  pass 'repository-aware dry-run creates no persistent repository or state data'
else
  fail 'repository-aware dry-run creates no persistent repository or state data'
fi

lifecycle_home=$test_tmp/lifecycle-home
lifecycle_state=$test_tmp/lifecycle-state
run_capture "$test_tmp/lifecycle-apply.output" env \
  HOME="$lifecycle_home" \
  XDG_STATE_HOME="$lifecycle_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=lifecycle-linux \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'Linux end-to-end sparse deployment succeeds'
else
  fail 'Linux end-to-end sparse deployment succeeds'
fi
if [ ! -e "$lifecycle_home/.config/tmux/conf/platform/macos.conf" ] \
  && [ ! -e "$lifecycle_home/Library/Application Support/com.mitchellh.ghostty/config.ghostty" ] \
  && [ ! -e "$lifecycle_home/.config/tmux/tests/project-session.sh" ] \
  && [ ! -e "$lifecycle_home/README.md" ]; then
  pass 'Linux deployment excludes macOS-only configuration and documentation'
else
  fail 'Linux deployment excludes macOS-only configuration and documentation'
fi
if [ -L "$lifecycle_home/.local/bin/dotfiles" ] \
  && [ -x "$lifecycle_home/.config/dotfiles/dotfiles" ]; then
  pass 'deployment installs the executable dotfiles command link'
else
  fail 'deployment installs the executable dotfiles command link'
fi
if [ -x "$lifecycle_home/.local/bin/t" ]; then
  pass 'deployment includes the cross-platform project launcher'
else
  fail 'deployment includes the cross-platform project launcher'
fi
run_capture "$test_tmp/lifecycle-status.output" env \
  HOME="$lifecycle_home" \
  "$lifecycle_home/.local/bin/dotfiles" status --porcelain=v1 --untracked-files=no
if [ "$run_status" -eq 0 ] && [ ! -s "$test_tmp/lifecycle-status.output" ]; then
  pass 'installed bare repository reports a clean tracked status'
else
  fail 'installed bare repository reports a clean tracked status'
fi
lifecycle_sparse_config=$(cat "$lifecycle_home/.cfg/config.worktree" 2>/dev/null || true)
lifecycle_sparse_paths=$(cat "$lifecycle_home/.cfg/info/sparse-checkout" 2>/dev/null || true)
if printf '%s\n' "$lifecycle_sparse_config" | grep -Fq 'sparseCheckoutCone = false' \
  && ! printf '%s\n' "$lifecycle_sparse_paths" | grep -Fq '.config/tmux/conf/platform/macos.conf'; then
  pass 'installed repository retains exact-file non-cone sparse selection'
else
  fail 'installed repository retains exact-file non-cone sparse selection'
fi
run_capture "$test_tmp/lifecycle-remote.output" env \
  HOME="$lifecycle_home" \
  "$lifecycle_home/.local/bin/dotfiles" remote get-url origin
if [ "$run_status" -eq 0 ] \
  && [ "$(cat "$test_tmp/lifecycle-remote.output")" = "$fixture_repo" ]; then
  pass 'installed repository retains the requested origin URL'
else
  fail 'installed repository retains the requested origin URL'
fi

mac_lifecycle_home=$test_tmp/mac-lifecycle-home
mac_lifecycle_state=$test_tmp/mac-lifecycle-state
mac_lifecycle_spotlight_state=$test_tmp/mac-lifecycle-spotlight-state
mkdir -p "$mac_lifecycle_spotlight_state"
run_capture "$test_tmp/mac-lifecycle-apply.output" env \
  HOME="$mac_lifecycle_home" \
  XDG_STATE_HOME="$mac_lifecycle_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$mac_lifecycle_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=lifecycle-macos \
  "$bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'simulated macOS end-to-end sparse deployment succeeds'
else
  fail 'simulated macOS end-to-end sparse deployment succeeds'
fi
if [ "$(cat "$mac_lifecycle_spotlight_state/entry" 2>/dev/null || true)" = \
    '{"enabled":true,"value":{"parameters":[59,41,1179648],"type":"standard"}}' ]; then
  pass 'macOS none profile configures the native Spotlight shortcut'
else
  fail 'macOS none profile configures the native Spotlight shortcut'
fi
if [ "$(cat "$mac_lifecycle_home/.config/tmux/conf/platform/macos.conf" 2>/dev/null || true)" = 'fixture macos' ] \
  && [ "$(cat "$mac_lifecycle_home/Library/Application Support/com.mitchellh.ghostty/config.ghostty" 2>/dev/null || true)" = 'fixture macos entrypoint' ]; then
  pass 'macOS deployment includes macOS-only configuration'
else
  fail 'macOS deployment includes macOS-only configuration'
fi
if [ ! -e "$mac_lifecycle_home/.config/tmux/conf/platform/linux.conf" ] \
  && [ ! -e "$mac_lifecycle_home/.config/tmux/tests/project-session.sh" ] \
  && [ ! -e "$mac_lifecycle_home/README.md" ]; then
  pass 'macOS deployment excludes Linux-only configuration and documentation'
else
  fail 'macOS deployment excludes Linux-only configuration and documentation'
fi
run_capture "$test_tmp/mac-lifecycle-status.output" env \
  HOME="$mac_lifecycle_home" \
  "$mac_lifecycle_home/.local/bin/dotfiles" status --porcelain=v1 --untracked-files=no
if [ "$run_status" -eq 0 ] && [ ! -s "$test_tmp/mac-lifecycle-status.output" ]; then
  pass 'simulated macOS bare repository reports a clean tracked status'
else
  fail 'simulated macOS bare repository reports a clean tracked status'
fi

printf '%s\n' 'fixture nvim updated' >"$fixture_work/.config/nvim/init.lua"
git -C "$fixture_work" add .config/nvim/init.lua
git -C "$fixture_work" commit -qm update
git -C "$fixture_work" remote add fixture-origin "$fixture_repo"
git -C "$fixture_work" push -q fixture-origin main
run_capture "$test_tmp/lifecycle-pull.output" env \
  HOME="$lifecycle_home" \
  "$lifecycle_home/.local/bin/dotfiles" pull --ff-only
if [ "$run_status" -eq 0 ]; then
  pass 'installed bare repository supports a standard fast-forward pull'
else
  fail 'installed bare repository supports a standard fast-forward pull'
fi
if [ "$(cat "$lifecycle_home/.config/nvim/init.lua" 2>/dev/null || true)" = 'fixture nvim updated' ]; then
  pass 'fast-forward pull updates selected configuration'
else
  fail 'fast-forward pull updates selected configuration'
fi
if [ ! -e "$lifecycle_home/.config/tmux/conf/platform/macos.conf" ] \
  && [ ! -e "$lifecycle_home/README.md" ]; then
  pass 'fast-forward pull preserves Linux platform isolation'
else
  fail 'fast-forward pull preserves Linux platform isolation'
fi

standalone_bootstrap=$test_tmp/standalone-bootstrap
cp "$bootstrap" "$standalone_bootstrap"
standalone_dry_home=$test_tmp/standalone-dry-home
standalone_dry_state=$test_tmp/standalone-dry-state
run_capture "$test_tmp/standalone-dry.output" env \
  HOME="$standalone_dry_home" \
  XDG_STATE_HOME="$standalone_dry_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  /bin/sh "$standalone_bootstrap" --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'standalone downloaded bootstrap supports dry-run'
else
  fail 'standalone downloaded bootstrap supports dry-run'
fi
standalone_dry_output=$(cat "$test_tmp/standalone-dry.output")
if printf '%s\n' "$standalone_dry_output" | grep -Fq '.config/tmux/conf/platform/linux.conf' \
  && printf '%s\n' "$standalone_dry_output" | grep -Fq 'install apt git'; then
  pass 'standalone bootstrap fetches platform and package manifests'
else
  fail 'standalone bootstrap fetches platform and package manifests'
fi

standalone_home=$test_tmp/standalone-home
standalone_state=$test_tmp/standalone-state
run_capture "$test_tmp/standalone-apply.output" env \
  HOME="$standalone_home" \
  XDG_STATE_HOME="$standalone_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_SKIP_PACKAGES=1 \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=standalone-linux \
  /bin/sh "$standalone_bootstrap" --apply --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'standalone downloaded bootstrap completes a bare deployment'
else
  fail 'standalone downloaded bootstrap completes a bare deployment'
fi
if [ -d "$standalone_home/.cfg" ] \
  && [ -x "$standalone_home/.local/bin/dotfiles" ] \
  && [ ! -e "$standalone_home/.config/tmux/conf/platform/macos.conf" ] \
  && [ ! -e "$standalone_home/README.md" ]; then
  pass 'standalone deployment preserves Linux platform isolation'
else
  fail 'standalone deployment preserves Linux platform isolation'
fi

package_report_home=$test_tmp/package-report-home
package_report_state=$test_tmp/package-report-state
package_report_log=$test_tmp/package-report.commands
run_capture "$test_tmp/package-report-apply.output" env \
  HOME="$package_report_home" \
  XDG_STATE_HOME="$package_report_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_APT_GHOSTTY_OFFICIAL=0 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$package_report_log" \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=package-report \
  "$bootstrap" --apply --allow-community-packages --window-manager i3 \
  --repo "$fixture_repo" --ref main
if [ "$run_status" -eq 0 ]; then
  pass 'configuration transaction succeeds after simulated package installation'
else
  fail 'configuration transaction succeeds after simulated package installation'
fi
package_report=$(cat "$package_report_state/dotfiles-bootstrap/package-report/packages-retained.txt" 2>/dev/null || true)
if printf '%s\n' "$package_report" | grep -Fq 'apt git' \
  && printf '%s\n' "$package_report" | grep -Fq 'apt i3-wm' \
  && printf '%s\n' "$package_report" | grep -Fq 'direct neovim' \
  && printf '%s\n' "$package_report" | grep -Fq 'community ghostty'; then
  pass 'transaction journals every package installation path'
else
  fail 'transaction journals every package installation path'
fi
run_capture "$test_tmp/package-report-rollback.output" env \
  HOME="$package_report_home" \
  XDG_STATE_HOME="$package_report_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=linux \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=apt \
  "$bootstrap" --rollback package-report
package_rollback_output=$(cat "$test_tmp/package-report-rollback.output")
if [ "$run_status" -eq 0 ] \
  && printf '%s\n' "$package_rollback_output" | grep -Fq 'apt git' \
  && printf '%s\n' "$package_rollback_output" | grep -Fq 'apt i3-wm' \
  && printf '%s\n' "$package_rollback_output" | grep -Fq 'community ghostty'; then
  pass 'rollback reports the retained package actions by name'
else
  fail 'rollback reports the retained package actions by name'
fi

karabiner_report_home=$test_tmp/karabiner-report-home
karabiner_report_state=$test_tmp/karabiner-report-state
karabiner_report_spotlight_state=$test_tmp/karabiner-report-spotlight-state
karabiner_report_drag_state=$test_tmp/karabiner-report-drag-state
karabiner_report_log=$test_tmp/karabiner-report.commands
mkdir -p "$karabiner_report_spotlight_state" "$karabiner_report_drag_state"
run_capture "$test_tmp/karabiner-report-apply.output" env \
  HOME="$karabiner_report_home" \
  XDG_STATE_HOME="$karabiner_report_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_ALL_PACKAGES_MISSING=1 \
  DOTFILES_BOOTSTRAP_TEST_COMMAND_LOG="$karabiner_report_log" \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$karabiner_report_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$karabiner_report_drag_state" \
  DOTFILES_BOOTSTRAP_TEST_RUN_ID=karabiner-package-report \
  "$bootstrap" --apply --window-manager aerospace \
  --repo "$fixture_repo" --ref main
karabiner_report=$(
  cat "$karabiner_report_state/dotfiles-bootstrap/karabiner-package-report/packages-retained.txt" \
    2>/dev/null || true
)
if [ "$run_status" -eq 0 ] \
  && printf '%s\n' "$karabiner_report" \
    | grep -Fq 'homebrew-cask karabiner-elements'; then
  pass 'AeroSpace transaction journals Karabiner Elements as retained'
else
  fail 'AeroSpace transaction journals Karabiner Elements as retained'
fi
run_capture "$test_tmp/karabiner-report-rollback.output" env \
  HOME="$karabiner_report_home" \
  XDG_STATE_HOME="$karabiner_report_state" \
  DOTFILES_BOOTSTRAP_TESTING=1 \
  DOTFILES_BOOTSTRAP_TEST_PLATFORM=macos \
  DOTFILES_BOOTSTRAP_TEST_MANAGER=homebrew \
  DOTFILES_BOOTSTRAP_TEST_SPOTLIGHT_STATE="$karabiner_report_spotlight_state" \
  DOTFILES_BOOTSTRAP_TEST_WINDOW_DRAG_STATE="$karabiner_report_drag_state" \
  "$bootstrap" --rollback karabiner-package-report
karabiner_rollback_output=$(cat "$test_tmp/karabiner-report-rollback.output")
if [ "$run_status" -eq 0 ] \
  && printf '%s\n' "$karabiner_rollback_output" \
    | grep -Fq 'homebrew-cask karabiner-elements'; then
  pass 'AeroSpace rollback reports retained Karabiner Elements by name'
else
  fail 'AeroSpace rollback reports retained Karabiner Elements by name'
fi

if [ "$failures" -ne 0 ]; then
  printf '1..%d\n' "$tests"
  printf '# %d test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '1..%d\n' "$tests"
printf '# all %d tests passed\n' "$tests"
