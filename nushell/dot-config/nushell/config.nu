$env.config = {
    show_banner: false
}

use ~/.local/share/linux-config/nu/lib.nu *

def has-cmd [app: string] {
    (which $app | is-not-empty)
}

def kitty-theme [] {
    ^kitty +kitten themes
}

if (which /home/linuxbrew/.linuxbrew/bin/brew | is-not-empty) {
    alias b = brew
    alias bi = brew install
    alias br = brew uninstall
    alias bs = brew search
    def bu [] {
        brew update
        brew upgrade
    }
}

if (is-apt) {
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
    alias u = sudo pacman -Syyu
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
