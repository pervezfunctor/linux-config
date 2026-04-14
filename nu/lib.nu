#!/usr/bin/env nu

use std/log
use std/util "path add"

export-env {
    $env.DOT_DIR = $"($env.HOME)/.local/share/linux-config"
    $env.LOG_FILE = $"($env.HOME)/.linux-config-logs/bootstrap-(date now | format date '%m-%d-%H%M%S').log"
}

export def init-log-file [] {
    mkdir ($env.LOG_FILE | path dirname)
}

def log-to-file [level: string, msg: string] {
    $"(date now | format date '%m-%d %H:%M:%S') [($level)] ($msg)\n"
    | save --append $env.LOG_FILE
}

export def log+ [msg: string] { log info $msg; log-to-file "INFO" $msg }
export def warn+ [msg: string] { log warning $msg; log-to-file "WARNING" $msg }
export def error+ [msg: string] { log error $msg; log-to-file "ERROR" $msg }

export def die [msg: string] {
    log critical $msg
    log-to-file "CRITICAL" $msg
    error make {
        msg: $msg
        label: { text: "fatal error", span: (metadata $msg).span }
    }
}

export def or-else [default_val: any] {
    if ($in | is-empty) { $default_val } else { $in }
}

export def ensure-parent-dir [path: string] {
    let parent = ($path | path dirname)
    if not ($parent | path exists) {
        mkdir $parent
    }
}

export def check-path [path: string] {
    if not ($path | path exists) {
        error make {
            msg: $"Path does not exist: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}

export def check-file [path: string] {
    let file_type = do -i { $path | path type } | default "none"
    if $file_type != 'file' {
        error make {
            msg: $"Not a file: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}

export def raise-error [msg: string, path: string = ""] {
    error+ $msg
    if ($path | is-empty) {
        error make { msg: $msg }
    } else {
        error make {
            msg: $msg
            label: {
                text: $path
                span: (metadata $path).span
            }
        }
    }
}

export def detect-path-kind [path: string] {
    do -i { $path | path type } | default "none"
}

export def encode-dot-segment [name: string] {
    if ($name | str starts-with ".") {
        $"dot-($name | str substring 1..)"
    } else {
        $name
    }
}

export def decode-dot-segment [name: string] {
    if ($name | str starts-with "dot-") {
        $".($name | str substring 4..)"
    } else {
        $name
    }
}

export def has-cmd [cmd: string]: nothing -> bool {
  (which $cmd | is-not-empty)
}

export def is-linux []: nothing -> bool {
    (uname).kernel-name == "Linux"
}

export def is-mac []: nothing -> bool {
    (sys host).name == "Darwin"
}

export def is-fedora-atomic []: nothing -> bool {
    has-cmd rpm-ostree
}

export def is-ublue []: nothing -> bool {
    (is-fedora-atomic) and (has-cmd ujust)
}

export def dir-exists [path: string]: nothing -> bool {
  ($path | path exists) and ($path | path type) == "dir"
}

export def is-fedora []: nothing -> bool {
  if (is-fedora-atomic) { return false }
  if not ("/etc/redhat-release" | path exists) { return false }
  let content = (open /etc/redhat-release | str downcase)
  $content =~ "fedora"
}

export def is-trixie []: nothing -> bool {
    (os-release | str downcase) =~ "trixie"
}

export def is-questing []: nothing -> bool {
    (os-release | str downcase) =~ "questing"
}

export def is-tw []: nothing -> bool {
    (os-release) =~ "Tumbleweed"
}

export def is-cachy []: nothing -> bool {
  (sys host).name =~ "(?i)cachy"
}

export def is-arch []: nothing -> bool {
    if not ("/etc/os-release" | path exists) { return false }

    let os_info = open /etc/os-release | lines
        | parse '{key}={value}'
        | update value { str replace -a '"' '' }
        | transpose -r
        | into record

    (($os_info.ID? | default "") == "arch") or ($os_info.ID_LIKE? | default "" | str contains "arch")
}

export def is-pikaos []: nothing -> bool {
  has-cmd pikman
}

export def is-apt []: nothing -> bool {
    (is-questing) or (is-trixie) or (is-pikaos)
}

export def os-release []: nothing -> string {
    try { open /etc/os-release } catch { "" }
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
    error+ "Shell path does not exist"
    return
  }

  if not (which sudo | is-not-empty) {
    error+ "sudo is not installed"
    return
  }

  let shells = open /etc/shells | lines
  if not ($shell_path in $shells) {
    ^sudo echo $shell_path | ^sudo tee -a /etc/shells
  }
}

def ignore-error [
  action: closure
  --quiet (-q)
] {
  try {
    do $action
  } catch { |err|
    if not $quiet {
      print $err
    }
  }
}

export def stow-package [package: string] {
  log+ $"Stowing ($package) dotfiles"
  ignore-error {|| nu ($env.DOT_DIR | path join "nu" "min-stow.nu") apply $package }
}

export def group-add [group: string] {
  let groups_output = (^getent group | lines)
  let group_names = ($groups_output | parse "{name}:x:{gid}:{members}" | get name)

  if $group in $group_names {
    ^sudo usermod -aG $group $env.USER
    } else {
    warn+ $"($group) group not found, skipping"
  }
}

export def si [packages: list<string>]: nothing -> bool {
  log+ $"Installing ($packages | str join ' ')"

  let exit_code = try {
    if (is-mac) or (is-ublue) {
      ^brew install ...$packages
    } else if (is-fedora) {
      ^sudo dnf install -y ...$packages
    } else if (is-apt) {
      ^sudo apt install -y ...$packages
    } else if (is-tw) {
      ^sudo zypper --non-interactive --quiet install --auto-agree-with-licenses ...$packages
    } else if (is-arch) {
      ^sudo pacman -S --quiet --noconfirm ...$packages
    } else {
      error+ $"OS not supported. Not installing ($packages | str join ' ')."
      return false
    }
    0
  } catch {
    $env.LAST_EXIT_CODE
  }

  if $exit_code != 0 {
    error+ $"Package installation failed (exit ($exit_code))"
    return false
  }
  true
}

export def update-packages []: nothing -> nothing {
  log+ "Updating packages"
  if (is-mac) or (is-ublue) {
    ^brew update
    ^brew upgrade
  } else if (is-fedora) {
    ^sudo dnf update -y
  } else if (is-apt) {
    ^sudo apt update
    ^sudo apt upgrade -y
  } else if (is-tw) {
    ^sudo zypper refresh
    ^sudo zypper update
  } else if (is-arch) {
    ^sudo pacman -Syu
    ^sudo pacman -Fy
  } else {
    die "OS not supported for package updates."
  }
}

export def brew-install [] {
  if (has-cmd brew) { return }
  log+ "Installing brew"
  http get "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" | bash
  if (is-mac) {
    path add "/opt/homebrew/bin"
  } else {
    path add "/home/linuxbrew/.linuxbrew/bin"
  }

  ^brew tap ublue-os/tap
  ^brew install topgrade
}

export def paru-install [] {
  if (has-cmd paru) {
    log+ "paru is already installed"
    return
  }

  log+ "Installing paru"

  si ["base-devel"]
  do -i { ^rm -rf /tmp/paru }
  ^git clone https://aur.archlinux.org/paru.git /tmp/paru

  try {
    cd /tmp/paru
    ^makepkg --syncdeps --noconfirm --install
  } catch {
    warn+ "Failed to install paru"
  }

  do -i { ^rm -rf /tmp/paru }
}

export def keep-sudo-alive []: nothing -> int {
    ^sudo -v
    job spawn {
        loop {
            ^sudo -n true
            sleep 55sec
        }
    }
}

export def stop-sudo-alive [job_id: int] {
    do -i {
        job kill $job_id
        ^sudo -k
    }
}

export def base-install [] {
  log+ "Installing required packages..."
  if (is-mac) {
    ^xcode-select --install
    ^/usr/sbin/softwareupdate --install-rosetta --agree-to-license
    brew-install
    ^brew install wget mas stow newt trash zstd unzip rclone tmux tar tree visual-studio-code
  } else if (is-ublue) {
    ^brew install stow newt trash-cli
  } else {
    si ["stow" "trash-cli" "whiptail" "unzip"]
  }
}

export def --env bootstrap [] {
  init-log-file
  path add "/home/linuxbrew/.linuxbrew/bin"

  for p in [
    "bin"
    ".local/bin"
    ".cargo/bin"
    ".local/share/mise/shims"
    $"($env.DOT_DIR? | default ($env.HOME | path join ".local/share/linux-config"))/nu"
    $"($env.DOT_DIR? | default ($env.HOME | path join ".local/share/linux-config"))/bin"
    ".pixi/bin"
    ".opencode/bin"
    ".volta/bin"
  ] {
    path add ($env.HOME | path join $p | path expand)
  }
}

export def task-handler [item: record<description: string, handler: closure>] {
  try {
    do $item.handler
  } catch {|err|
    error+ $"($item.description) failed."
    $err | print
  }
}

export def multi-task [items: list<record<description: string, handler: closure>>] {
  let selected = ($items | input list --multi --display description "Select tasks to execute:")

  if ($selected | is-empty) {
    log+ "No tasks selected."
    return
  }

  for item in $selected {
    log+ $"Executing: ($item.description)"
    task-handler $item
  }
}

export def gum-multi-task [
    items: list<record<description: string, handler: closure>>,
    --default-selected: list<int> = []  # Indices of items to pre-select (0-based)
] {
    if not (has-cmd gum) {
        error+ "gum is not installed"
        return
    }

    let descriptions = ($items | get description)

    let defaults = $default_selected
        | each {|i| $descriptions | get $i}
        | str join ","

    let selected_descriptions = if ($defaults | is-empty) {
        $descriptions | gum choose --no-limit
    } else {
        $descriptions | gum choose --no-limit --selected $defaults
    }

    if ($selected_descriptions | is-empty) {
        log+ "No tasks selected."
        return
    }

    let selected = $items | where {|item| $item.description in $selected_descriptions}

    for item in $selected {
        log+ $"Executing: ($item.description)"
        task-handler $item
    }
}

export def touch-files [dir: string, files: list<string>] {
  do -i { mkdir $dir }

  for f in $files {
    let file_path = ($dir | path join $f)
    if not ($file_path | path exists) {
      touch $file_path
    }
  }
}

export def pixi-install [] {
  if (has-cmd pixi) {
    return
  }

  log+ "Installing pixi..."
  sh -c (http get https://pixi.sh/install.sh)
}
