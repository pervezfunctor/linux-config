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

## Package Manager(homebrew)

Install homebrew, the most popular package manager on macos(similar to apt on ubuntu)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew tap ublue-os/tap
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

Use `Catppuccin Mocha` theme and `Jetbrains Mono Nerd Font` font in ghostty terminal and vscode editor.

## Terminal

Use Alacritty or Kitty. Use your OS package manager

```bash
sudo apt install -y kitty
```

```bash
sudo dnf install -y kitty
```

## Python

Use `uv` for all python development. Install with

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
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
chsh -s $(command -v fish)
```

Install and use starship prompt.

```bash
curl -sS https://starship.rs/install.sh | sh
```

If absent, add the following line to ~/.config/fish/config.fish

```fish
starship init fish | source
```

Few modern shell tools

```bash
brew install trash-cli fzf eza zoxide bat gh ripgrep tealdeer direnv fd jq bottom htop
```

If this is too cumbersome, use my script to setup what you need from this repo`s [README](https://github.com/pervezfunctor/linux-config)
