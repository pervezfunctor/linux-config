#!/usr/bin/env nu

export def default-if-empty [default_val: any] {
    if ($in | is-empty) { $default_val } else { $in }
}

export def try-relative [path: string, base: string] {
    do -i { $path | path relative-to $base } | default ($path | path basename)
}

export def ensure-parent-dir [path: string] {
    let parent = ($path | path dirname)
    if not ($parent | path exists) {
        mkdir $parent
    }
}

export def validate-path [path: string, --required] {
    if $required and not ($path | path exists) {
        error make {
            msg: $"Path does not exist: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}

export def validate-file [path: string] {
    let file_type = do -i { $path | path type } | default "none"
    if $file_type != 'file' and $file_type != 'symlink' {
        error make {
            msg: $"Not a file: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}

export def safe-ln [src: string, dest: string] {
    try {
        ^ln -sf $src $dest
        true
    } catch {
        false
    }
}

export def safe-rm [path: string] {
    try {
        ^rm -f $path
        true
    } catch {
        false
    }
}

export def safe-cp [src: string, dest: string] {
    try {
        ^cp $src $dest
        true
    } catch {
        false
    }
}

export def safe-mkdir [path: string] {
    try {
        mkdir $path
        true
    } catch {
        false
    }
}

# OS Detection Functions

def has_cmd [app: string] {
    (which $app | is-not-empty)
}

export def is-linux [] {
    (sys host).name == "Linux"
}

export def is-mac [] {
    (sys host).name == "Darwin"
}

export def os-release [] {
    if ("/etc/os-release" | path exists) {
        open "/etc/os-release"
    } else {
        {}
    }
}

export def is-ubuntu [] {
    let os = os-release
    ($os.PRETTY_NAME? | default "" | str contains "Ubuntu")
}

export def is-debian [] {
    let os = os-release
    let name = ($os.PRETTY_NAME? | default "")
    ($name | str contains "Debian") or ($name | str contains "trixie") or ($name | str contains "questing")
}

export def is-apt [] {
    is-debian
}

export def is-arch [] {
    let os = os-release
    ($os.PRETTY_NAME? | default "" | str contains "Arch Linux")
}

export def is-tumbleweed [] {
    let os = os-release
    ($os.PRETTY_NAME? | default "" | str contains "Tumbleweed")
}

export def is-tw [] {
    is-tumbleweed
}

export def is-fedora-atomic [] {
    has_cmd rpm-ostree
}

export def is-fedora [] {
    if (is-fedora-atomic) {
        false
    } else {
        let os = os-release
        ($os.PRETTY_NAME? | default "" | str contains "Fedora")
    }
}

export def is-pikaos [] {
    let os = os-release
    ($os.PRETTY_NAME? | default "" | str downcase | str contains "pika")
}

export def is-gnome [] {
    ($env.XDG_CURRENT_DESKTOP? | default "" | str contains "GNOME") or ($env.XDG_SESSION_DESKTOP? | default "" | str contains "gnome")
}

export def is-ublue [] {
    (is-fedora-atomic) and (has_cmd ujust)
}
