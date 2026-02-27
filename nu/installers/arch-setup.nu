#!/usr/bin/env nu

use std/util 'path add'

export def log+ [msg: string] { log info $msg }
export def warn+ [msg: string] { log warning $msg }
export def error+ [msg: string] { log error $msg }

export def die [msg: string] {
    log critical $msg
    error make {
        msg: $msg
        label: { text: "fatal error", span: (metadata $msg).span }
    }
}

def prompt-yn [prompt: string] {
  let response = (input $"(ansi cyan)? ($prompt)(ansi reset) (ansi yellow)[y/N](ansi reset) ")
  $response =~ "(?i)^y(es)?$"
}

def si [packages: list<string>] {
  log+ $"Installing ($packages | str join ' ')"
  ^sudo pacman -S --quiet --noconfirm ...$packages
}

def update-packages [] {
  log+ "Updating packages"

  ^sudo pacman -Syu
  ^sudo pacman -Fy
}

def paru-install [] {
  if (has-cmd paru) {
    log+ "paru is already installed"
    return
  }

  log+ "Installing paru"

  do -i { ^rm -rf /tmp/paru }

  ^git clone https://aur.archlinux.org/paru.git /tmp/paru
  cd /tmp/paru
  ^makepkg --syncdeps --noconfirm --install
    ^rm -rf /tmp/paru
}

def "main incus config" [] {
  log+ "Setting up incus"
  group-add "incus"
  group-add "incus-admin"

  ^sudo systemctl enable --now incus.socket
  sleep 2sec
  ^sudo incus admin init --minimal
}

def "main virt config" [] {
  for group in ["libvirt" "qemu" "libvirt-qemu" "kvm" "libvirtd"] {
    do -i { ^sudo usermod -aG $group $env.USER }
  }

  if (has-cmd authselect) {
    do -i { ^sudo authselect enable-feature with-libvirt }
  }
}

export def stow-package [package: string] {
  try {
    let config_dir = ($env.HOME | path join ".local/share/linux-config")
    let package_dir = ($config_dir | path join $package)

    log+ $"Stowing ($package)"

    ^stow --no-folding --dir $config_dir --target $env.HOME $package
  } catch {
    error+ "Cannot stow ($package)"
  }
}

def "main system install" [] {
  update-packages

  log+ "Installing system packages"
  si [
    "mermaid-cli"
    "base-devel"
    "bash-language-server"
    "bat"
    "bottom"
    "cmake"
    "cockpit"
    "cockpit-files"
    "cockpit-machines"
    "cockpit-packagekit"
    "cockpit-podman"
    "cockpit-storaged"
    "direnv"
    "distrobox"
    "dnsmasq"
    "duf"
    "eza"
    "fd"
    "fish"
    "flatpak"
    "flatpak"
    "fuse3"
    "fzf"
    "gcc"
    "gdu"
    "git"
    "github-cli"
    "gnome-keyring"
    "gum"
    "incus"
    "jq"
    "jujutsu"
    "just"
    "lazygit"
    "lazyjj"
    "libvirt"
    "lm_sensors"
    "make"
    "micro"
    "mise"
    "neovim"
    "nushell"
    "openbsd-netcat"
    "pass"
    "pixi"
    "plocate"
    "podman"
    "python-pipx"
    "qemu-full"
    "qemu-hw-display-virtio-gpu"
    "qemu-hw-display-virtio-gpu-gl"
    "qemu-img"
    "qemu-tools"
    "qt6-multimedia"
    "rclone"
    "ripgrep"
    "rsync"
    "rustup"
    "shellcheck"
    "shfmt"
    "squashfuse"
    "starship"
    "stow"
    "swtpm"
    "tar"
    "tealdeer"
    "tectonic"
    "television"
    "tmux"
    "tmuxp"
    "topgrade"
    "trash-cli"
    "tree"
    "ttf-jetbrains-mono-nerd"
    "unzip"
    "uv"
    "virt-install"
    "virt-manager"
    "virt-manager"
    "virt-viewer"
    "woff2-font-awesome"
    "xh"
    "yazi"
    "zed"
    "zoxide"
    "zsh"
    "zstd"
  ]


  ^pixi global install carapace mask
  ^rustup default stable
  bash -c (http get https://claude.ai/install.sh)
}

def "main system config" [] {
  log+ "Updating locate database, this may take a while..."

  do -i {
    ^sudo updatedb
    ^tldr --update
  }

  main dotfiles
  stow-package "kitty"
  stow-package "zed"
  stow-package "nushell"
  stow-package "fish"
}

def "main system" [] {
  main system install
  main system config
}

let DOT_DIR = ($env.HOME | path join ".local/share/linux-config")
const REPO_URL = "https://github.com/pervezfunctor/linux-config.git"

def "main dotfiles" [] {
  if not (dir-exists $DOT_DIR) {
    cd $env.HOME
    log+ "Cloning dotfiles"
    ^git clone --depth 1 $REPO_URL $DOT_DIR
    return
  }

  let is_git = (do -i { ^git -C $DOT_DIR rev-parse --is-inside-work-tree } | complete)
  if $is_git.exit_code != 0 {
    error make { msg: $"($DOT_DIR) exists but is not a git repository" }
  }

  let status = (do -i { ^git -C $DOT_DIR status --porcelain=v1 } | complete)
  if $status.exit_code != 0 {
    error make { msg: "Unable to determine repository status" }
  }

  if ($status.stdout | is-empty) {
    log+ "Dotfiles repo clean. Pulling latest changes"
    let pull = (do -i { ^git -C $DOT_DIR pull --rebase --stat } | complete)
    if $pull.exit_code == 0 {
      log+ "Dotfiles updated"
      return
    }

    warn+ "git pull --rebase failed. Attempting to abort rebase"
    do -i { ^git -C $DOT_DIR rebase --abort }
    error make { msg: "git pull --rebase failed on clean repo" }
  }

  log+ "Dotfiles repo has local changes. Stashing before pull"
  let stash_label = $"setup-autostash-(date now | format date '%s')"
  do -i { ^git -C $DOT_DIR stash push --include-untracked --message $stash_label }

  let pull = (do -i { ^git -C $DOT_DIR pull --rebase --stat } | complete)
  if $pull.exit_code == 0 {
    log+ "Pull succeeded. Restoring local changes"
    do -i { ^git -C $DOT_DIR stash pop }
    return
  }

  warn+ "git pull --rebase failed with local changes. Restoring state"
  do -i { ^git -C $DOT_DIR rebase --abort }
  do -i { ^git -C $DOT_DIR stash pop }
  error make { msg: "git pull --rebase failed; local changes restored" }
}

def wm-install [] {
  mut pkgs = [
    "cliphist"
    "grim"
    "gvfs"
    "gvfs-smb"
    "imv"
    "kimageformats"
    "kitty"
    "mate-polkit"
    "mpv"
    "nautilus"
    "pipewire"
    "pipewire-pulse"
    "qt5ct"
    "qt6ct"
    "slurp"
    "wireplumber"
    "wl-clipboard"
    "xdg-desktop-portal-gnome"
    "xdg-desktop-portal-gtk"
    "xdg-desktop-portal-wlr"
  ]

  si $pkgs

  paru-install

  let pictures = ($env.HOME | path join "Pictures")
  do -i { mkdir $"($pictures)/Screenshots" }
  do -i { mkdir $"($pictures)/Wallpapers" }

  ^pipx install pywal pywalfox

  stow-package "systemd"
}

def "main niri config" [] {
  stow-package "niri"
  let niri_dms = ($env.HOME | path join ".config/niri/dms")
  touch-files $niri_dms ["alttab.kdl" "colors.kdl" "layout.kdl" "wpblur.kdl" "binds.kdl" "cursor.kdl" "outputs.kdl"]
  ^systemctl --user add-wants niri.service dms
}

def "main niri install" [] {
  wm-install

  if (has-cmd dms) and (has-cmd niri) {
    log+ "niri and dms are already installed"
  } else {
    log+ "Installing niri and dms"
    ^paru -S niri dms-shell-bin
  }
}

def "main niri" [] {
  main niri install
  main niri config
}

def "main mangowc install" [] {
  log+ "Installing mangowc"
  wm-install
  ^paru -S mangowc-git dms-shell-bin
}

def "main mangowc config" [] {
  log+ "Stowing mangowc dotfiles"

  stow-package "mango"
  stow-package "systemd"

  let mango_dms = ($env.HOME | path join ".config/mango/dms")
  let dms_files = ["alttab" "colors" "layout" "wpblur" "binds" "cursor" "outputs"]
  touch-files $mango_dms $dms_files
  ^systemctl --user add-wants wm-session.target dms
}

def "main mangowc" [] {
  mangowc install
  mangowc config
}

def "main hypr install" [] {
  log+ "Installing hyprland"
  wm-install
  paru-install
  ^paru -S hyprland dms-shell-bin
}

def "main hypr config" [] {
  log+ "Setting up hypr"

  stow-package "hypr"

  let hypr_dms = ($env.HOME | path join ".config/hypr/dms")
  let dms_files = ["alttab" "colors" "layout" "wpblur" "binds" "cursor" "outputs"]
  touch-files $hypr_dms $dms_files

  ^systemctl --user add-wants hyprland-session.target dms
  ^systemctl --user add-wants wm-session.target dms
}

def "main hypr" [] {
  hypr install
  hypr config
}

def "main sway install" [] {
  log+ "Installing sway"
  wm-install
  si ["sway"]
}

def "main sway config" [] {
  stow-package "sway"
}

def "main sway" [] {
  sway install
  sway config
}

def "main flatpaks" [] {
  log+ "Adding flathub remote"
  ^flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo --user

  let flatpaks = [
    "com.github.tchx84.Flatseal"
    "org.gnome.Firmware"
  ]

  log+ "Installing flatpaks..."
  for pkg in $flatpaks {
    log+ $"Installing ($pkg)"
    do -i { ^flatpak --user install -y flathub $pkg }
  }
}

export def multi-task [items: list<record<description: string, handler: closure>>] {
  let selected = ($items | input list --multi --display description "Select tasks to execute:")

  if ($selected | is-empty) {
    log+ "No tasks selected."
    return
  }

  for item in $selected {
    try {
      log+ $"Executing: ($item.description)"
      $item.handler
    } catch {|err|
      error+ "%ask ($item.description) failed."
      print $err
    }
  }
}

def "main setup" [] {
  if not ($DOT_DIR | path exists) {
    die $"($DOT_DIR) does not exist. Quitting"
  }

  multi-task [
    { description: "Install system packages(required)", handler: { main system } }
    { description: "Install niri", handler: { main niri } }
    { description: "Install mangowc", handler: { main mangowc } }
    { description: "Install hyprland", handler: { main hypr } }
    { description: "Install sway", handler: { main sway } }
    { description: "Install flatpaks", handler: { main flatpaks } }
  ]
}

def "main stow" [package: string] {
  stow-package $package
}

def "main help" [] {
    print "arch-setup.nu - Arch Linux setup script"
    print ""
    print "Usage: nu arch-setup.nu <command>"
    print ""
    print "Commands:"
    print "  niri           Install niri WM"
    print "  mangowc        Install mangowc WM"
    print "  hypr           Install hyprland WM"
    print "  sway           Install sway WM"
    print "  flatpaks       Install flatpak applications"
    print "  dotfiles       Clone and stow dotfiles"
    print "  stow <pkg>     Stow a specific package (niri, fish, nushell, etc)"
    print "  incus config   Install and configure incus"
    print "  virt config    Install libvirt/virt-manager"
    print "  help           Show this help message"
}

export def --env bootstrap [] {
  for p in ["bin" ".local/bin" ".local/share/linux-config/bin"] {
    path add ($env.HOME | path join $p | path expand)
  }
}

def main [] {
  bootstrap
  main setup
}
