alias c = code
alias g = git
alias h = btm
alias p = pikman
alias pi = pixi global install
alias t = tmux
alias v = nvim
alias f = fd-find

alias gs = git stash -u
alias gp = git push
alias gb = git branch
alias gbc = git checkout -b
alias gsl = git stash list
alias gst = git status
alias gsu = git status -u
alias gcan = git commit --amend --no-edit
alias gsa = git stash apply
alias gfm = git pull
alias gcm = git commit --message
alias gia = git add
alias gco = git checkout
alias git-tree = git status --short | awk '{print $2}' | tree --fromfile

alias stls = sudo systemctl status
alias stle = sudo systemctl enable --now
alias stld = sudo systemctl disable
alias stlp = sudo systemctl stop
alias stlr = sudo systemctl restart
alias stlg = sudo systemctl list-units
alias stlf = sudo systemctl list-units --all --state=failed

alias utle = systemctl --user enable --now
alias utld = systemctl --user disable
alias utlp = systemctl --user stop
alias utlr = systemctl --user restart
alias utlg = systemctl --user list-units
alias utlf = systemctl --user list-units --all --state=failed
alias dms-logs = journalctl --user -u dms -f
alias uv-jupyter-standalone = uv tool run jupyter lab
alias uv-marimo-standalone = uvx --with pyzmq --from "marimo[sandbox]" marimo edit --sandbox

# # eza (ls replacement)
# alias ls = eza -al --color=always --group-directories-first --icons
# alias la = eza -a --color=always --group-directories-first --icons
# alias ll = eza -l --color=always --group-directories-first --icons
# alias lt = eza -aT --color=always --group-directories-first --icons
# def "l." [] { eza -a | rg -e '^\.' }

# # Common use
# alias grubup = sudo grub-mkconfig -o /boot/grub/grub.cfg
# alias fixpacman = sudo rm /var/lib/pacman/db.lck
# alias tarnow = tar -acf
# alias untar = tar -zxvf
# alias wget = wget -c
# alias psmem = ps auxf | sort -nr -k 4
# alias psmem10 = ps auxf | sort -nr -k 4 | head -10
# alias .. = cd ..
# alias ... = cd ../..
# alias .... = cd ../../..
# alias ..... = cd ../../../..
# alias ...... = cd ../../../../..
# alias dir = dir --color=auto
# alias vdir = vdir --color=auto
# alias grep = grep --color=auto
# alias fgrep = fgrep --color=auto
# alias egrep = egrep --color=auto
# alias hw = hwinfo --short
# alias big = expac -H M '%m\t%n' | sort -h | nl
# alias gitpkg = pacman -Q | rg -i "\-git" | wc -l
# alias update = sudo pacman -Syu

# # Get fastest mirrors
# alias mirror = sudo cachyos-rate-mirrors

# # Help people new to Arch
# alias apt = man pacman
# alias apt-get = man pacman
# alias please = sudo
# alias tb = nc termbin.com 9999

# # Cleanup orphaned packages
# def cleanup [] { sudo pacman -Rns (pacman -Qtdq) }

# # Get the error messages from journalctl
# alias jctl = journalctl -p 3 -xb

# # Recent installed packages
# alias rip = expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl
