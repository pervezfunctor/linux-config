source /usr/share/cachyos-fish-config/cachyos-config.fish

set -gx DOT_DIR "$HOME/.local/share/linux-config"
set -gx EDITOR "zededit --wait"
set -gx VISUAL "zededit --wait"
# set -gx EDITOR "code --wait"
# set -gx VISUAL "code --wait"
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
set -gx VOLTA_HOME "$HOME/.volta"
set -gx XDG_DATA_DIRS "$HOME/.local/share/flatpak/exports/share" $XDG_DATA_DIRS

set -gx PATH $HOME/.local/share/flatpak/exports/bin $HOME/.pixi/bin $HOME/bin $HOME/.local/bin $VOLTA_HOME/bin $PNPM_HOME $PATH

if not string match -q -- $PNPM_HOME $PATH
    set -gx PATH "$PNPM_HOME" $PATH
end

if test -x ~/.local/bin/mise
    ~/.local/bin/mise activate fish | source
end

alias git-tree='git status --short | awk "{print \$2}" | tree --fromfile'
