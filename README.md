# Dotfiles

My personal configuration files, managed as a bare git repository. This setup allows me to track files in my home directory without the clutter of a standard .git folder or symlink managers.

---
## Restore configuration

To clone these dotfiles onto a fresh system, copy and paste this block into your terminal.

```Bash
git clone --bare https://github.com/Ruohao1/dotfiles.git $HOME/.cfg
echo ".cfg" >> .gitignore
alias dotfiles='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
mkdir -p .config-backup
dotfiles checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | xargs -I{} mv {} .config-backup/{}
dotfiles checkout
dotfiles config --local status.showUntrackedFiles no```

---
## Get started

```Bash

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
My editor configuration is maintained in its own repository: ![neovim-configuration](https://github.com/Ruohao1/neovim-configuration)

