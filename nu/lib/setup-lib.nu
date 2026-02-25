use std/util "path add"

export def stow-package [package: string] {
  let config_dir = ($env.HOME | path join ".local/share/linux-config")
  validate-path $config_dir

  let package_dir = ($config_dir | path join $package)
  validate-path $package_dir

  # @TODO: Replace with stow.nu apply
  log+ $"Stowing ($package) dotfiles"
  ^stow --no-folding --adopt --dir $config_dir --target $env.HOME $package
  do -i {
    ^git -C $config_dir stash --include-untracked --message $"Stashing ($package) dotfiles"
  }
}

export def group-add [group: string] {
  let groups_output = (^getent group | lines)
  let group_names = ($groups_output | parse "{name}:x:{gid}:{members}" | get name)

  if $group in $group_names {
    ^sudo usermod -aG $group $env.USER
  } else {
    warn+ "$group group not found, skipping"
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
  } else {
    die "OS not supported for package updates."
  }
}

export def brew-install [] {
  if (has-cmd brew) { return }
  log+ "Installing brew"
  ^/bin/bash -c (http get "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")
  if (is-mac) {
    path add "/opt/homebrew/bin"
  } else {
    path add "/home/linuxbrew/.linuxbrew/bin"
  }

  ^brew tap ublue-os/tap
  ^brew install topgrade
}

export def paru-install [] {
  if (has-cmd paru) { return }
  log+ "Installing paru"
  si ["base-devel"]
  do -i { ^rm -rf /tmp/paru }
  ^git clone https://aur.archlinux.org/paru.git /tmp/paru
  do {
    cd /tmp/paru
    ^makepkg --syncdeps --noconfirm --install
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

export def bootstrap [] {
  path add "/opt/homebrew/bin"
  path add "/home/linuxbrew/.linuxbrew/bin"

  path add ([
    "bin"
    ".local/bin"
    ".local/share/pnpm"
    ".npm-packages"
    ".local/share/mise/shims"
    ".volta/bin"
    ".pixi/bin"
    ".local/share/linux-config/bin"
  ] | each { $env.HOME | path join $in | path expand })
}

export def multi-task [items: list<record<description: string, handler: closure>>] {
  let selected = ($items | input list --multi --display description "Select tasks to execute:")

  if ($selected | is-empty) {
    log+ "No tasks selected."
    return
  }

  for item in $selected {
    log+ $"Executing: ($item.description)"
    do $item.handler
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
