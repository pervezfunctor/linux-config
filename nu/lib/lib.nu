#!/usr/bin/env nu

export use ./logs.nu *

export def default-if-empty [default_val: any] {
    if ($in | is-empty) { $default_val } else { $in }
}

export def ensure-parent-dir [path: string] {
    let parent = ($path | path dirname)
    if not ($parent | path exists) {
        mkdir $parent
    }
}

export def validate-path [path: string] {
    if not ($path | path exists) {
        error make {
            msg: $"Path does not exist: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}

export def validate-file [path: string] {
    let file_type = do -i { $path | path type } | default "none"
    if $file_type != 'file' {
        error make {
            msg: $"Not a file: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}

def has_cmd [app: string] {
    (which $app | is-not-empty)
}

export def is-linux [] {
    ((sys host).name =~ "Linux") or ((uname).kernel-name == "Linux") or ((sys host).long_os_version | str contains "Linux")
}

export def is-mac [] {
    (sys host).name == "Darwin"
}

export def is-fedora-atomic [] {
    has_cmd rpm-ostree
}

export def is-gnome [] {
    ($env.XDG_CURRENT_DESKTOP? | default "" | str contains "GNOME") or ($env.XDG_SESSION_DESKTOP? | default "" | str contains "gnome")
}

export def is-ublue [] {
    (is-fedora-atomic) and (has_cmd ujust)
}

export def dir-exists [path: string]: nothing -> bool {
  ($path | path exists) and ($path | path type) == "dir"
}

export def has-cmd [cmd: string]: nothing -> bool {
  (which $cmd | is-not-empty)
}

export def is-fedora []: nothing -> bool {
  if (is-fedora-atomic) { return false }
  if not ("/etc/redhat-release" | path exists) { return false }
  let content = (open /etc/redhat-release | str downcase)
  $content =~ "fedora"
}

export def is-trixie []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release | str downcase)
  $content =~ "trixie"
}

export def is-questing []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release | str downcase)
  $content =~ "questing"
}

export def is-ubuntu []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release | str downcase)
  $content =~ "ubuntu"
}

export def is-tw []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release)
  $content =~ "Tumbleweed"
}

export def is-arch []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release)
  let lines = ($content | lines)

  let id = ($lines | where { $in =~ '^ID=' } | first | str replace '^ID=' '' | str trim --char '"')
  let id_like = ($lines | where { $in =~ '^ID_LIKE=' } | first | default "" | str replace '^ID_LIKE=' '' | str trim --char '"')

  $id == "arch" or ($id_like | str contains "arch")
}

export def is-pikaos []: nothing -> bool {
  has-cmd pikman
}

export def is-apt []: nothing -> bool {
  (is-trixie) or (is-questing) or (is-pikaos)
}

export def is-non-atomic-linux []: nothing -> bool {
  (is-linux) and not (is-fedora-atomic)
}

export def prompt-yn [prompt: string]: nothing -> bool {
  let response = (input $"(ansi cyan)? ($prompt)(ansi reset) (ansi yellow)[y/N](ansi reset) ")
  $response =~ "(?i)^y(es)?$"
}

export def handle [block: closure] {
    try {
        do $block
    } catch {|err|
        $err | print -e
        null
    }
}

export def add-shell [shell_path: string] {
  if not ($shell_path | path exists) {
    warn+ "Shell path does not exist"
    return
  }

  if not (which sudo | is-not-empty) {
    warn+ "sudo is not installed"
    return
  }

  let shells = open /etc/shells | lines
  if not ($shell_path in $shells) {
    ^sudo echo $shell_path | ^sudo tee -a /etc/shells
  }
}
