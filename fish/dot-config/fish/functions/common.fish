function jupyter-lab
    set -l jupyter_dir "$HOME/jupyter-lab"

    if not test -d $jupyter_dir
        echo "Directory does not exist: $jupyter_dir"
        return 1
    end

    set -l jupyter "$jupyter_dir/.venv/bin/jupyter"
    if not test -f $jupyter
        echo "Virtual environment not found"
        return 1
    end

    $jupyter lab
end

function has_cmd
    type -q $argv[1]
    return $status
end

function uv-marimo-standalone
    uvx --with pyzmq --from "marimo[sandbox]" marimo edit --sandbox
end

function uv-jupyter-standalone
    uv tool run jupyter lab
end

function kitty-theme
    kitty +kitten themes
end

function reinit
    source $HOME/.config/fish/config.fish
end

function fish_greeting
end