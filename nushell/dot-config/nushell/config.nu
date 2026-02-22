$env.config = {
    show_banner: false
}

use ../../../nu/lib.nu [
    is-linux
    is-mac
    is-ubuntu
    is-apt
    is-arch
    is-tw
    is-fedora
    is-fedora-atomic
    is-pikaos
    is-gnome
    is-ublue
]

def jupyter-lab [] {
    let jupyter_dir = ($nu.home-dir | path join jupyter-lab)

    if not ($jupyter_dir | path exists) {
        error make {
            msg: "Directory does not exist"
            label: {
                text: $jupyter_dir
                span: (metadata $jupyter_dir).span
            }
        }
    }

    let jupyter = ($jupyter_dir | path join .venv | path join bin | path join jupyter)
    if not ($jupyter | path exists) {
        error make { msg: "Virtual environment not found" }
    }

    ^$jupyter lab
}

def has_cmd [app: string] {
    (which $app | is-not-empty)
}

def uv-marimo-standalone [] {
    uvx --with pyzmq --from "marimo[sandbox]" marimo edit --sandbox
}

def uv-jupyter-standalone [] {
    uv tool run jupyter lab
}

def kitty-theme [] {
    ^kitty +kitten themes
}

if (is-ubuntu) or (is-apt) {
    alias i = sudo apt install
    alias r = sudo apt remove
    alias s = apt search
    def u [] {
        sudo apt update
        sudo apt upgrade
    }
} else if (is-arch) {
    alias i = sudo pacman -S
    alias r = sudo pacman -R
    alias s = pacman -Ss
    alias u = sudo pacman -Syu
} else if (is-tw) {
    alias i = sudo zypper install
    alias r = sudo zypper remove
    alias s = zypper search
    alias u = sudo zypper update
} else if (is-fedora) or (is-fedora-atomic) {
    alias i = sudo dnf install
    alias r = sudo dnf remove
    alias s = dnf search
    alias u = sudo dnf update
} else {
    alias i = pikman install
    alias r = pikman remove
    alias s = pikman search
    def u [] {
        pikman update
        pikman upgrade
    }
}

source ($nu.default-config-dir | path join auto-includes.nu)
source ($nu.default-config-dir | path join aliases.nu)

def reinit [] {
    ^$"($nu.default-config-dir | path join nushell-sources.nu)"
}
