#!/usr/bin/env nu

def has_cmd [cmd: string] {
    (which $cmd | is-not-empty)
}

def install_installer [name: string] {
    match $name {
        "brew" => {
            if not (has_cmd brew) {
                print "Installing brew..."
                ^/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            }
        }
        "pixi" => {
            if not (has_cmd pixi) {
                print "Installing pixi..."
                ^brew install pixi
            }
        }
        "mise" => {
            if not (has_cmd mise) {
                print "Installing mise..."
                ^curl https://mise.run | sh
            }
        }
        "cargo" => {
            if not (has_cmd cargo) {
                print "Installing cargo (via rustup)..."
                ^curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y
            }
        }
        "go" => {
            if not (has_cmd go) {
                print "Installing go..."
                ^brew install go
            }
        }
        "npm" => {
            if not (has_cmd npm) {
                print "Installing npm (via node)..."
                ^brew install node
            }
        }
        "pipx" => {
            if not (has_cmd pipx) {
                print "Installing pipx..."
                ^pip install --user pipx
            }
        }
        "pikman" => {
            if not (has_cmd pikman) {
                print "Installing pikman..."
                ^curl -fsSL https://get.pika.pink | bash
            }
        }
        _ => {
            print $"Unknown installer: ($name)"
        }
    }
}

def install_packages [name: string, packages: list<string>] {
    if ($packages | is-empty) {
        return
    }

    print $"Installing packages for ($name):"
    print $"  Packages: (($packages | str join ', '))"

    match $name {
        "dnf" => { ^sudo dnf install -y $packages }
        "pacman" => { ^sudo pacman -S --noconfirm $packages }
        "zypper" => { ^sudo zypper install -y $packages }
        "apt" => { ^sudo apt install -y $packages }
        "pixi" => { ^pixi global install $packages }
        "brew" => { ^brew install $packages }
        "mise" => {
            for pkg in $packages {
                ^mise use -g $pkg
            }
        }
        "cargo" => {
            for pkg in $packages {
                ^cargo install $pkg
            }
        }
        "go" => {
            for pkg in $packages {
                ^go install $"($pkg)@latest"
            }
        }
        "npm" => {
            for pkg in $packages {
                ^npm install -g $pkg
            }
        }
        "pipx" => {
            for pkg in $packages {
                ^pipx install $pkg
            }
        }
        "pikman" => {
            for pkg in $packages {
                ^pikman install $pkg
            }
        }
        "flatpak" => {
            for pkg in $packages {
                ^flatpak install -y flathub $pkg
            }
        }
        _ => {
            print $"Unknown installer: ($name)"
        }
    }

    print $""
}

def get_packages [installer_data: any, groups: list<string>] {
    let is_flat_list = ($installer_data | describe | str contains "list")

    if $is_flat_list {
        $installer_data
    } else {
        $groups | each { |group|
            let group_pkgs = ($installer_data | get $group | default [])
            $group_pkgs
        } | flatten
    }
}

def main [yaml_file: string, ...groups: string] {
    let config = (open $yaml_file | from yaml)

    let installers_to_install = ($config | get installers | default [])

    print $"Installing installers: (($installers_to_install | str join ', '))"
    print $""
    for installer in $installers_to_install {
        install_installer $installer
    }

    let all_installers = [
        "brew", "pixi", "mise", "cargo", "go", "npm", "pipx", "pikman",
        "dnf", "pacman", "zypper", "apt", "flatpak"
    ]

    for name in $all_installers {
        let installer_data = ($config | get $name | default {})

        if ($installer_data | is-empty) {
            continue
        }

        let available = (has_cmd $name)
        if not $available {
            print $"($name) is not available, skipping..."
            continue
        }

        let packages = (get_packages $installer_data $groups)
        install_packages $name $packages
    }
}
