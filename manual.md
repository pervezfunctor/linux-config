# Development Environment on Ubuntu/Fedora

## System

Update your system

```bash
sudo apt update && sudo apt upgrade -y # ubuntu
```

```bash
sudo dnf update # fedora
```

Install essential packages

```bash
sudo apt install -y curl git-core wget trash-cli build-essential
```

```bash
sudo dnf install -y curl git-core wget trash-cli gcc make
```

## Shell

Install and set fish as the default shell. This is an excellent interactive shell with near perfect defaults.

Install using

```bash
sudo apt install -y fish
```

```bash
sudo dnf install -y fish
```

and set as default with the following commands.

```bash
sudo chsh -s $(command -v fish) "$USER"
```

Restart your terminal.

Install and use starship prompt.

```bash
sudo apt install -y starship
```

On fedora, use the following command to install starship.

```bash
curl -sS https://starship.rs/install.sh | sh
```

Add starship to `~/.config/fish/config.fish` with

```fish
echo 'starship init fish | source' >> ~/.config/fish/config.fish
```

## Python

Use `uv` for all python development. Install with

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## C++

Install the following packages

```bash
sudo apt install -y clang cmake entr gcc make pkg-config clang-tools
```

```bash
sudo dnf install -y clang cmake entr gcc make pkg-config clang-tools-extra
```

## Package Manager(homebrew)

Install homebrew, the most popular package manager on macos(similar to apt on ubuntu)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
brew tap ublue-os/tap
```

Install few modern shell tools

```bash
brew install trash-cli fzf eza zoxide bat gh ripgrep tealdeer direnv fd jq bottom htop
```

Add '/home/linuxbrew/.linuxbrew/bin' to your PATH in `~/.config/fish/config.fish`

```fish
set -gx PATH /home/linuxbrew/.linuxbrew/bin $PATH
```

## Editor

`zed` editor is pretty good. Install with

```bash
curl -f https://zed.dev/install.sh | sh
```

Install jetbrains mono font with brew

```bash
brew install --cask font-jetbrains-mono-nerd-font
```

If you prefer `vscode`, install with

```bash
brew install --cask visual-studio-code-linux
```

## Terminal

Use Alacritty or Kitty. Use your OS package manager

```bash
sudo apt install -y kitty
```

```bash
sudo dnf install -y kitty
```

Use `Catppuccin Mocha` theme and `Jetbrains Mono Nerd Font` font in kitty terminal and vscode editor.

## Neovim

Install neovim with brew

```bash
brew install neovim
```

Setup neovim with the following

```bash
mkdir -p ~/.config/nvim
trash ~/.config/nvim/ 2>/dev/null
git clone --depth 1 https://github.com/AstroNvim/template ~/.config/nvim
rm -rf ~/.config/nvim/.git
cp ~/.linux-config/nvim/dot-config/nvim/lua/community.lua ~/.config/nvim/lua/community.lua
cp -r ~/.linux-config/nvim/dot-config/nvim/lua/plugins/ ~/.config/nvim/lua/plugins/
```

## dotfiles

You could also get a slightly better configuration setting up manually dotfiles from this repository.

First clone this repository

```bash
git clone https://github.com/pervezfunctor/linux-config.git ~/.linux-config
```

Setup fish with the following

```bash
mkdir -p ~/.config/fish
trash ~/.config/fish/config.fish 2>/dev/null
cp ~/.linux-config/fish/dot-config/fish/config.fish ~/.config/fish/config.fish
```

Setup kitty with the following

```bash
mkdir -p ~/.config/kitty
trash ~/.config/kitty/kitty.conf 2>/dev/null
cp ~/.linux-config/kitty/dot-config/kitty/kitty.conf ~/.config/kitty/kitty.conf
```

Setup zed editor with

```bash
mkdir -p ~/.config/zed
trash ~/.config/zed/settings.json 2>/dev/null
cp ~/.linux-config/zed/dot-config/zed/settings.json ~/.config/zed/settings.json
```

Setup tmux with

```bash
mkdir -p ~/.config/tmux
trash ~/.config/tmux/tmux.conf 2>/dev/null
cp ~/.linux-config/tmux/dot-config/tmux/tmux.conf ~/.config/tmux/tmux.conf
```

If all of this is too cumbersome, use my script to setup what you need using [README](https://github.com/pervezfunctor/linux-config)
