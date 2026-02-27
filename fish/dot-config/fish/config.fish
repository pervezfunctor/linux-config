# Format man pages
set -x MANROFFOPT "-c"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

## Environment setup
# Apply .profile: use this to put fish compatible .profile stuff in
if test -f ~/.fish_profile
  source ~/.fish_profile
end

set -gx DOT_DIR $HOME/.local/share/linux-config

set -gx EDITOR "zeditor --wait"
set -gx VISUAL "zeditor --wait"
# set -gx EDITOR "code --wait"
# set -gx VISUAL "code --wait"

set -gx PNPM_HOME $HOME/.local/share/pnpm
set -gx VOLTA_HOME $HOME/.volta
set -gx XDG_DATA_DIRS $HOME/.local/share/flatpak/exports/share $XDG_DATA_DIRS

# if using system npm: https://github.com/sindresorhus/guides/blob/main/npm-global-without-sudo.md
set NPM_PACKAGES "$HOME/.npm-packages"
set MANPATH $NPM_PACKAGES/share/man $MANPATH


fish_add_path --global --move \
    /home/linuxbrew/.linuxbrew/bin \

    $HOME/.local/share/flatpak/exports/bin \
    $DOT_DIR/nu/installers \
    $DOT_DIR/nu \
    $HOME/.pixi/bin \
    $HOME/bin \
    $HOME/.local/bin \
    $NPM_PACKAGES/bin \
    $VOLTA_HOME/bin \
    $PNPM_HOME

if not string match -q -- $PNPM_HOME $PATH
    set -gx PATH "$PNPM_HOME" $PATH
end

if test -x ~/.local/bin/mise
    ~/.local/bin/mise activate fish | source
end

if has_cmd fish
    zoxide init fish | source
end

if has_cmd fzf
    fzf --fish | source
end

if has_cmd starship
    starship init fish | source
end

if has_cmd carapace
    set -Ux CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense' # optional
    carapace _carapace | source
end
