# Dotfiles

My personal configuration files, managed as a bare git repository. This setup allows me to track files in my home directory without the clutter of a standard `.git` folder or symlink managers.

---

## Install on a fresh machine

The bootstrap detects macOS or Linux and selects Homebrew, pacman, or apt automatically. It only installs configuration for the window-manager profile you choose.

The copy-paste helper requires `curl`.

First, paste this helper into your terminal. It downloads the bootstrap to a unique temporary file and removes it after each run.

```sh
dotfiles_bootstrap() (
  set -eu

  installer=$(mktemp)
  trap 'rm -f "$installer"' 0 HUP INT TERM
  curl --fail --location --show-error --silent \
    --output "$installer" \
    https://raw.githubusercontent.com/Ruohao1/dotfiles/main/.config/dotfiles/bootstrap
  sh "$installer" "$@"
)
```

Choose the command for your system. Remove `--apply` to preview the complete package, conflict, backup, and configuration plan without changing anything.

### macOS

```sh
# AeroSpace
dotfiles_bootstrap --apply --window-manager aerospace

# No window manager
dotfiles_bootstrap --apply --window-manager none
```

The AeroSpace profile installs Karabiner Elements and configures Option plus left-drag to rearrange tiled windows.
After the first apply, open Karabiner Elements and complete its required macOS setup by keeping its background items enabled, granting Accessibility, and approving its Driver Extension.
Karabiner Elements 15.9.0 or earlier may also require Input Monitoring.
Bootstrap reports this manual step but does not claim that macOS completed it.

### Arch, EndeavourOS, or Manjaro

```sh
# Hyprland
dotfiles_bootstrap --apply --window-manager hypr

# i3
dotfiles_bootstrap --apply --window-manager i3

# No window manager
dotfiles_bootstrap --apply --window-manager none
```

### Debian, Ubuntu, Linux Mint, or Pop!_OS

The community-package flag permits the pinned Ghostty installer when Ghostty is unavailable from the configured apt repositories.

```sh
# i3
dotfiles_bootstrap --apply --window-manager i3 --allow-community-packages

# No window manager
dotfiles_bootstrap --apply --window-manager none --allow-community-packages
```

Existing conflicting files are backed up automatically. To restore the files and macOS preferences from the latest completed installation, run:

```sh
$HOME/.config/dotfiles/bootstrap --rollback latest
```

Rollback intentionally keeps installed packages.

---

## Get started

```sh
git init $HOME/.cfg
alias dotfiles='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
echo "alias dotfiles='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'" >> $HOME/.zshrc
dotfiles config --local status.showUntrackedFiles no
dotfiles remote add origin <git-repo-url>
dotfiles branch -M main
dotfiles push -u origin main
```

---

## Modifier contract

Shared actions keep the same suffix key, action, and modifier tier on every platform.
Only the platform modifier name changes.

| Responsibility | Linux modifier | macOS modifier |
| --- | --- | --- |
| Workspace and window-manager actions | Super | Option |
| Terminal and multiplexer actions | Alt | Command |

Hyprland, i3, and AeroSpace window-manager bindings are maintained as one checked contract.

---

## More

My Neovim configuration is maintained in this repository under [`.config/nvim`](.config/nvim).
