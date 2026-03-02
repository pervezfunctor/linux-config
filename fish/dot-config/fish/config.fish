set -x MANROFFOPT "-c"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

if test -f ~/.fish_profile
  source ~/.fish_profile
end

set -gx DOT_DIR $HOME/.local/share/linux-config
set -gx PNPM_HOME $HOME/.local/share/pnpm
set -gx VOLTA_HOME $HOME/.volta
set -gx XDG_DATA_DIRS $HOME/.local/share/flatpak/exports/share $XDG_DATA_DIRS
set -gx NPM_PACKAGES "$HOME/.npm-packages"
set -gx MANPATH $NPM_PACKAGES/share/man $MANPATH


fish_add_path --global --move \
    /home/linuxbrew/.linuxbrew/bin \
    $HOME/.local/share/flatpak/exports/bin \
    $DOT_DIR/nu \
    $HOME/.pixi/bin \
    $HOME/bin \
    $HOME/.local/bin \
    $NPM_PACKAGES/bin \
    $VOLTA_HOME/bin \
    $PNPM_HOME


function has_cmd
    type -q $argv[1]
end

if has_cmd ~/.local/bin/mise
    ~/.local/bin/mise activate fish | source
end

if status is-interactive
    if has_cmd zoxide
        zoxide init fish | source
    end

    if has_cmd fzf
        fzf --fish | source
    end

    if has_cmd starship
        starship init fish | source
    end

    if has_cmd carapace
        set -gx CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense' # optional
        carapace _carapace | source
    end
end

function kitty-theme
    kitty +kitten themes
end

function reinit
    source $HOME/.config/fish/config.fish
end

function fish_greeting
end

alias gs 'git stash'
alias gp 'git push'
alias gb 'git branch'
alias gbc 'git checkout -b'
alias gsl 'git stash list'
alias gst 'git status'
alias gsu 'git status -u'
alias gcan 'git commit --amend --no-edit'
alias gsa 'git stash apply'
alias gfm 'git pull'
alias gcm 'git commit -m'
alias gia 'git add'
alias gco 'git checkout'
function git-tree
    git status --short | awk '{print $2}' | tree --fromfile
end

function c
  if has_cmd zeditor
    zeditor
    zeditor $argv
  elif has_cmd zed
    zed
    zed $argv
  elif has_cmd code
    code
    code $argv
  elif has_cmd nvim
    nvim
    nvim $argv
  else
    echo "No editor found"
  end
end

alias f 'fd'
alias g 'git'
alias h 'btm'
alias p 'pixi global install'
alias t 'tmux'
alias v 'nvim'

alias fpi 'flatpak install --user flathub'
alias fpr 'flatpak remove --user'
alias fps 'flatpak search'
alias fpu 'flatpak update --user'

if has_cmd /home/linuxbrew/.linuxbrew/bin/brew
  alias b 'brew'
  alias bi 'brew install'
  alias br 'brew uninstall'
  alias bs 'brew search'
  alias bu 'brew update && brew upgrade'
end

if has_cmd zypper
    alias i 'sudo zypper install'
    alias r 'sudo zypper remove'
    alias s 'zypper search'
    alias u 'sudo zypper update'
else if has_cmd dnf
    alias i 'sudo dnf install'
    alias r 'sudo dnf remove'
    alias s 'dnf search'
    alias u 'sudo dnf update'
else if has_cmd pikman
    alias i 'pikman install'
    alias r 'pikman remove'
    alias s 'pikman search'
    alias u 'pikman update; and pikman upgrade'
else if has_cmd apt
    alias i 'sudo apt install'
    alias r 'sudo apt remove'
    alias s 'apt search'
    alias u 'sudo apt update; and sudo apt upgrade'
else if has_cmd paru
    alias i 'paru -S'
    alias r 'paru -R'
    alias s 'paru -Ss'
    alias u 'paru -Syu'
else if has_cmd pacman
    alias i 'sudo pacman -S'
    alias r 'sudo pacman -R'
    alias s 'pacman -Ss'
    alias u 'sudo pacman -Syu'
else if has_cmd rpm-ostree
    alias u 'sudo rpm-ostree update'
end
