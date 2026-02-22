source $__fish_config_dir/functions/common.fish

alias c 'code'
alias g 'git'
alias h 'btm'
alias p 'pikman'
alias pi 'pixi global install'
alias t 'tmux'
alias v 'nvim'
alias f 'fd-find'

if is_ubuntu; or is_apt
    alias i 'sudo apt install'
    alias r 'sudo apt remove'
    alias s 'apt search'
    alias u 'sudo apt update; and sudo apt upgrade'
else if is_arch
    alias i 'sudo pacman -S'
    alias r 'sudo pacman -R'
    alias s 'pacman -Ss'
    alias u 'sudo pacman -Syu'
else if is_tw
    alias i 'sudo zypper install'
    alias r 'sudo zypper remove'
    alias s 'zypper search'
    alias u 'sudo zypper update'
else if is_fedora; or is_fedora_atomic
    alias i 'sudo dnf install'
    alias r 'sudo dnf remove'
    alias s 'dnf search'
    alias u 'sudo dnf update'
else
    alias i 'pikman install'
    alias r 'pikman remove'
    alias s 'pikman search'
    alias u 'pikman update; and pikman upgrade'
end

alias gs 'git stash -u'
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

alias stls 'sudo systemctl status'
alias stle 'sudo systemctl enable --now'
alias stld 'sudo systemctl disable'
alias stlp 'sudo systemctl stop'
alias stlr 'sudo systemctl restart'
alias stlg 'sudo systemctl list-units'
alias stlf 'sudo systemctl list-units --all --state=failed'

alias utle 'systemctl --user enable --now'
alias utld 'systemctl --user disable'
alias utlp 'systemctl --user stop'
alias utlr 'systemctl --user restart'
alias utlg 'systemctl --user list-units'
alias utlf 'systemctl --user list-units --all --state=failed'
alias dms-logs 'journalctl --user -u dms -f'

## if using system npm: https://github.com/sindresorhus/guides/blob/main/npm-global-without-sudo.md
# set NPM_PACKAGES "$HOME/.npm-packages"
# set PATH $PATH $NPM_PACKAGES/bin
# set MANPATH $NPM_PACKAGES/share/man $MANPATH
