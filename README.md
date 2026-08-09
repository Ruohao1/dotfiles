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

## More

My editor configuration is maintained in its own repository: ![neovim-configuration](https://github.com/Ruohao1/neovim-config)
