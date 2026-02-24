#!/usr/bin/env nu

use std/util 'path add'

use ../lib/logs.nu *
use ../lib/lib.nu *
use ../lib/setup-lib.nu *

def prompt-yn [prompt: string]: nothing -> bool {
  let response = (input $"(ansi cyan)? ($prompt)(ansi reset) (ansi yellow)[y/N](ansi reset) ")
  $response =~ "(?i)^y(es)?$"
}

def si [packages: list<string>]: nothing -> bool {
  log+ $"Installing ($packages | str join ' ')"
  ^sudo pacman -S --quiet --noconfirm ...$packages
}

def update-packages []: nothing -> nothing {
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


def incus-config [] {
  log+ "Setting up incus"
  group-add "incus"
  group-add "incus-admin"

  ^sudo systemctl enable --now incus.socket
  sleep 2sec
  ^sudo incus admin init --minimal
}

def "main incus" [] {
  if (has-cmd incus) {
    log+ "incus is already installed"
    return
  }

  log+ "Installing incus"
  si ["incus"]
  incus-config
}

def "main system-shell" [] {
  update-packages

  log+ "Installing system packages"
  si [
    "bash-language-server"
    "bat"
    "bottom"
    "cmake"
    "direnv"
    "duf"
    "eza"
    "fd"
    "fish"
    "fuse3"
    "fzf"
    "gcc"
    "gdu"
    "git"
    "github-cli"
    "gum"
    "jq"
    "jujutsu"
    "just"
    "lazygit"
    "lazyjj"
    "lm_sensors"
    "make"
    "micro"
    "mise"
    "neovim"
    "nushell"
    "pixi"
    "python-pipx"
    "qt6-multimedia"
    "rclone"
    "ripgrep"
    "rsync"
    "shellcheck"
    "shfmt"
    "squashfuse"
    "starship"
    "stow"
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
    "woff2-font-awesome"
    "xh"
    "yazi"
    "zoxide"
    "zstd"
  ]

  log+ "Updating locate database, this may take a while..."
  do -i { ^sudo updatedb }
  ^tldr --update
}

def pixi-install-packages [] {
  log+ "Installing shell tools with pixi"

  let pixi_pkgs = [
    "carapace"
    "mask"
  ]

  ^pixi global install ...$pixi_pkgs
}


def "main pixi" [] {
  log+ "Installing pixi packages"
  if not (has-cmd pixi) {
    curl -fsSL https://pixi.sh/install.sh | sh
  }

  pixi-install-packages
}

def "main rust" [] {
  if (has-cmd cargo) {
    log+ "rust/cargo is already installed"
    return
  }

  log+ "Installing rust"
  si ["rustup"]
  rustup default stable
}

def nushell-config [] {
  let nu_path = (which nu | first | get path)
  add-shell $nu_path
  stow-package "nushell"
}

def "main nvim" [] {
  let nvim_config = ($env.HOME | path join ".config/nvim")

  if (dir-exists $nvim_config) {
    if not (prompt-yn "Found existing nvim config. Do you want to trash and replace with AstroNvim?") {
      return
    }
  }

  log+ "Installing AstroNvim"

  do -i { ^trash ($env.HOME | path join .config nvim.bak) }
  do -i { ^trash ($env.HOME | path join .local share nvim.bak) }
  do -i { ^trash ($env.HOME | path join .local state nvim.bak) }
  do -i { ^trash ($env.HOME | path join .cache nvim.bak) }

  mkdir $nvim_config
  ^git clone --depth 1 https://github.com/AstroNvim/template $nvim_config
  ^rm -rf $"($nvim_config)/.git"
}

def fish-config [] {
  let shell_path = (which fish | first | get path)
  add-shell $shell_path
  stow-package "fish"

  log+ "Setting fish as default shell"
  ^chsh -s $shell_path
}

def dotfiles-clone [] {
  let repo_dir = ($env.HOME | path join ".local/share/linux-config")
  let repo_url = "https://github.com/pervezfunctor/linux-config.git"

  if not (dir-exists $repo_dir) {
    cd $env.HOME
    log+ "Cloning dotfiles"
    ^git clone --depth 1 $repo_url $repo_dir
    return
  }

  let is_git = (do -i { ^git -C $repo_dir rev-parse --is-inside-work-tree } | complete)
  if $is_git.exit_code != 0 {
    error make { msg: $"($repo_dir) exists but is not a git repository" }
  }

  let status = (do -i { ^git -C $repo_dir status --porcelain=v1 } | complete)
  if $status.exit_code != 0 {
    error make { msg: "Unable to determine repository status" }
  }

  if ($status.stdout | is-empty) {
    log+ "Dotfiles repo clean. Pulling latest changes"
    let pull = (do -i { ^git -C $repo_dir pull --rebase --stat } | complete)
    if $pull.exit_code == 0 {
      log+ "Dotfiles updated"
      return
    }

    warn+ "git pull --rebase failed. Attempting to abort rebase"
    do -i { ^git -C $repo_dir rebase --abort }
    error make { msg: "git pull --rebase failed on clean repo" }
  }

  log+ "Dotfiles repo has local changes. Stashing before pull"
  let stash_label = $"setup-autostash-(date now | format date '%s')"
  do -i { ^git -C $repo_dir stash push --include-untracked --message $stash_label }

  let pull = (do -i { ^git -C $repo_dir pull --rebase --stat } | complete)
  if $pull.exit_code == 0 {
    log+ "Pull succeeded. Restoring local changes"
    do -i { ^git -C $repo_dir stash pop }
    return
  }

  warn+ "git pull --rebase failed with local changes. Restoring state"
  do -i { ^git -C $repo_dir rebase --abort }
  do -i { ^git -C $repo_dir stash pop }
  error make { msg: "git pull --rebase failed; local changes restored" }
}

def "main dotfiles" [] {
  dotfiles-clone
  nushell-config
  fish-config
}

def "main devtools" [] {
  let mise_bin = ($env.HOME | path join ".local/bin/mise")

  if not (($mise_bin | path exists) and (has-cmd mise)) {
    error make { msg: "mise binary not found" }
  }

  log+ "Installing Node via mise"
  ^$mise_bin use -g node@latest
  ^$mise_bin use -g pnpm

  let use_pnpm = (has-cmd pnpm)

  if $use_pnpm {
    ^pnpm setup
  }

  let npm_pkgs = [
    "@mermaid-js/mermaid-cli"
    "@google/gemini-cli"
    "opencode-ai"
  ]

  log+ "Installing npm packages"
  for pkg in $npm_pkgs {
    log+ $"Installing ($pkg)"
    if $use_pnpm {
      ^pnpm install -g $pkg
    } else {
      ^npm install -g $pkg
    }
  }
}

def "main claude" [] {
  if (has-cmd claude) {
    log+ "claude is already installed"
    return
  }

  log+ "Installing claude"
  ^curl -fsSL https://claude.ai/install.sh | ^bash
}

def "main setup-shell" [] {
  multi-task [
    { description: "Install system packages",           handler: { main system-shell } }
    { description: "Install incus",                     handler: { main incus } }
    { description: "Setup dotfiles with stow",          handler: { main dotfiles } }
    { description: "Install pixi",                      handler: { main pixi } }
    { description: "Install devtools (mise, uv etc)",   handler: { main devtools } }
    { description: "Install Neovim",                    handler: { main nvim } }
    { description: "Install claude",                    handler: { main claude } }
    { description: "Install rustup",                    handler: { main rust } }
  ]
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
    "pipewire-jack"
    "pipewire-pulse"
    # "power-profiles-daemon"
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

  stow-package "systemd"
}

def "main niri" [] {
  wm-install

  if (has-cmd dms) and (has-cmd niri) {
    log+ "niri and dms are already installed"
  } else {
    log+ "Installing niri and dms"
    ^paru -S niri dms-shell-bin
  }

  stow-package "niri"

  let niri_dms = ($env.HOME | path join ".config/niri/dms")
  touch-files $niri_dms ["alttab.kdl" "colors.kdl" "layout.kdl" "wpblur.kdl" "binds.kdl" "cursor.kdl" "outputs.kdl"]

  do -i { ^systemctl --user add-wants niri.service dms }
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

  do -i { ^systemctl --user add-wants wm-session.target dms }
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
  stow-package "hypr"

  let hypr_dms = ($env.HOME | path join ".config/hypr/dms")
  let dms_files = ["alttab" "colors" "layout" "wpblur" "binds" "cursor" "outputs"]
  touch-files $hypr_dms $dms_files

  do -i { ^systemctl --user add-wants hyprland-session.target dms }
  do -i { ^systemctl --user add-wants wm-session.target dms }
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
  if not (has-cmd flatpak) {
    si ["flatpak"]
  }

  log+ "Adding flathub remote"
  ^flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo --user

  let flatpaks = [
    "com.github.tchx84.Flatseal"
    "io.github.flattool.Ignition"
    "md.obsidian.Obsidian"
    "org.gnome.Firmware"
  ]

  log+ "Installing flatpaks..."
  for pkg in $flatpaks {
    log+ $"Installing ($pkg)"
    do -i { ^flatpak --user install -y flathub $pkg }
  }
}

def "main system-desktop" [] {
  update-packages

  log+ "Installing system packages"
  si [
    "flatpak"
    "gnome-keyring"
    "pass"
    "plocate"
  ]

  if not (has-cmd pipx) {
    warn+ "pipx is not installed"
    return
  }

  log+ "Installing pywal packages"
  ^pipx install pywal pywalfox
}

def "main cockpit" [] {
  log+ "Installing cockpit"
  si [
    "cockpit"
    "cockpit-packagekit"
    "cockpit-storaged"
    "cockpit-podman"
    "cockpit-files"
    "cockpit-machines"
  ]
}

def "main distrobox" [] {
  log+ "Installing distrobox"
  si ["podman" "distrobox"]
}

def "main vscode install" [] {
  if (has-cmd code) {
    log+ "vscode is already installed"
    return
  }

  log+ "Installing vscode"
  paru-install
  ^paru -S visual-studio-code-bin
}

def "main vscode extensions" [] {
  let extensions = [
    "jdinhlife.gruvbox"
    "mads-hartmann.bash-ide-vscode"
    "TheNuProjectContributors.vscode-nushell-lang"
    "timonwong.shellcheck"
    "wayou.vscode-todo-highlight"
  ]

  log+ "Installing vscode extensions"
  for ext in $extensions {
    log+ $"Installing ($ext)"
    do -i { ^code --install-extension $ext }
  }
}

def "main vscode config" [] {
  stow-package "vscode"
  stow-package "kitty"
}

def "main vscode" [] {
  main vscode install
  main vscode extensions
  main vscode config
}

def "main zed" [] {
  log+ "Installing zed"
  si ["zed"]

  stow-package "zed"
}

def "main virt" [] {
  log+ "Installing virt-manager"
  si ["virt-manager" "virt-install" "virt-viewer" "libisofs" "guestfs-tools" "qemu-img"]

  for group in ["libvirt" "qemu" "libvirt-qemu" "kvm" "libvirtd"] {
    do -i { ^sudo usermod -aG $group $env.USER }
  }

  if (has-cmd authselect) {
    do -i { ^sudo authselect enable-feature with-libvirt }
  }
}

def "main setup-desktop" [] {
  multi-task [
    { description: "Install desktop system packages", handler: { main system-desktop } }
    { description: "Install distrobox",               handler: { main distrobox } }
    { description: "Install virt-manager",            handler: { main virt } }
    { description: "Install vscode",  handler: { main vscode } }
    { description: "Install flatpaks", handler: { main flatpaks } }
    { description: "Install zed",      handler: { main zed } }
    { description: "Install niri", handler: { main niri } }
    { description: "Install mangowc", handler: { main mangowc } }
    { description: "Install hyprland", handler: { main hypr } }
    { description: "Install sway", handler: { main sway } }
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
    print "  setup-shell    Interactive shell setup (packages, dotfiles, tools)"
    print "  setup-desktop  Interactive desktop setup (WMs, flatpaks, apps)"
    print "  system-shell   Install system packages (non-interactive)"
    print "  system-desktop Install desktop packages (non-interactive)"
    print "  dotfiles       Clone and stow dotfiles"
    print "  stow <pkg>     Stow a specific package (niri, fish, nushell, etc)"
    print "  incus          Install and configure incus"
    print "  shell          Install pixi packages"
    print "  rust           Install rustup"
    print "  nvim           Install AstroNvim"
    print "  devtools       Install dev tools (node, pnpm, etc)"
    print "  claude         Install claude CLI"
    print "  niri           Install niri WM"
    print "  mangowc        Install mangowc WM"
    print "  hypr           Install hyprland WM"
    print "  sway           Install sway WM"
    print "  vscode         Install vscode and extensions"
    print "  zed            Stow zed editor dotfiles"
    print "  flatpaks       Install flatpak applications"
    print "  distrobox      Install distrobox"
    print "  virt           Install virt-manager"
    print "  help           Show this help message"
}

def main [] {
    init-log-file

    let sudo_job_id = keep-sudo-alive

    bootstrap
    main setup-shell
    main setup-desktop

    stop-sudo-alive $sudo_job_id
}
