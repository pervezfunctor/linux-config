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

# OS Detection Functions

function is_linux
    test (uname -s) = "Linux"
end

function is_mac
    test (uname -s) = "Darwin"
end

function os_release
    if test -f /etc/os-release
        cat /etc/os-release
    end
end

function is_ubuntu
    test -f /etc/os-release; and grep -q 'Ubuntu' /etc/os-release 2>/dev/null
end

function is_debian
    test -f /etc/os-release; and begin
        grep -q 'Debian' /etc/os-release 2>/dev/null
        or grep -qi 'trixie' /etc/os-release 2>/dev/null
        or grep -qi 'questing' /etc/os-release 2>/dev/null
    end
end

function is_apt
    is_debian
end

function is_arch
    test -f /etc/os-release; and grep -q 'Arch Linux' /etc/os-release 2>/dev/null
end

function is_tumbleweed
    test -f /etc/os-release; and grep -q 'Tumbleweed' /etc/os-release 2>/dev/null
end

function is_tw
    is_tumbleweed
end

function is_fedora_atomic
    type -q rpm-ostree
end

function is_fedora
    is_fedora_atomic; and return 1
    test -f /etc/redhat-release; and grep -q -i 'Fedora' /etc/redhat-release
end

function is_pikaos
    test -f /etc/os-release; and grep -q 'pika' /etc/os-release 2>/dev/null
end

function is_gnome
    test "$XDG_CURRENT_DESKTOP" = "GNOME"; or test "$XDG_SESSION_DESKTOP" = "gnome"
end

function is_ublue
    is_fedora_atomic; and type -q ujust
end