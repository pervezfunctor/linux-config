#!/usr/bin/env nu

use std/util 'path add'
use ../nu/logs.nu *

def dir-exists [path: string]: nothing -> bool {
  ($path | path exists) and ($path | path type) == "dir"
}

def has-cmd [cmd: string]: nothing -> bool {
  (which $cmd | is-not-empty)
}

def is-arch []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release)
  let lines = ($content | lines)

  let id = ($lines | where { $in =~ '^ID=' } | first | str replace '^ID=' '' | str trim --char '"')
  let id_like = ($lines | where { $in =~ '^ID_LIKE=' } | first | str replace '^ID_LIKE=' '' | str trim --char '"' | default "")

  $id == "arch" or ($id_like | str contains "arch")
}

def prompt-yn [prompt: string]: nothing -> bool {
  let response = (input $"(ansi cyan)? ($prompt)(ansi reset) (ansi yellow)[y/N](ansi reset) ")
  $response =~ "(?i)^y(es)?$"
}

def si [packages: list<string>]: nothing -> bool {
  log+ $"Installing ($packages | str join ' ')"
  ^sudo pacman -S --quiet --noconfirm ...$packages
}

def stow-package [package: string] {
  let config_dir = ($env.HOME | path join ".local/share/linux-config")

  if not (dir-exists $config_dir) {
    error make { msg: $"Config directory not found: ($config_dir)" }
  }

  let package_dir = ($config_dir | path join $package)
  if not (dir-exists $package_dir) {
    error make { msg: $"Package directory not found: ($package_dir)" }
  }

  log+ $"Stowing ($package) dotfiles"
  ^stow --no-folding --adopt --dir $config_dir --target $env.HOME $package
  do -i { ^git -C $config_dir stash --include-untracked --message $"Stashing ($package) dotfiles" }
}

def update-packages []: nothing -> nothing {
  log+ "Updating packages"
  ^sudo pacman -Syu
  ^sudo pacman -Fy
}

def paru-install [] {
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

def incus-setup [] {
  log+ "Setting up incus"

    let groups_output = (^getent group | lines)
  let group_names = ($groups_output | parse "{name}:x:{gid}:{members}" | get name)

  if "incus" in $group_names {
    ^sudo usermod -aG incus $env.USER
  } else {
    warn+ "incus group not found, skipping"
  }

  if "incus-admin" in $group_names {
    ^sudo usermod -aG incus-admin $env.USER
  } else {
    warn+ "incus-admin group not found, skipping"
  }

  ^sudo systemctl enable --now incus.socket


  sleep 2sec

  let check_init = (do -i { ^incus info } | complete)
  if $check_init.exit_code != 0 {
    log+ "Initializing incus"
    ^sudo incus admin init --minimal
  } else {
    log+ "incus already initialized"
  }
}

def "main incus" [] {
  if (has-cmd incus) {
    log+ "incus is already installed"
    return
  }

  log+ "Installing incus"
  si ["incus"]
  incus-setup
}

def "main system-shell" [] {
  update-packages

  let pkgs = [
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
    "g++"
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

  log+ "Installing system packages"
  si $pkgs

  log+ "Updating locate database, this may take a while..."
  do -i { ^sudo updatedb }
  ^tldr --update
}

def pixi-install [] {
  log+ "Installing pixi packages"
  pixi-install-packages
}

def pixi-install-packages [] {
  log+ "Installing shell tools with pixi"

  let pixi_pkgs = [
    "carapace"
    "mask"
  ]

  ^pixi global install ...$pixi_pkgs
}

def "main shell" [] {
  pixi-install
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

def nushell-setup [] {
  let nu_path = (which nu | first | get path)
  let shells = (open /etc/shells | lines)

  if not ($nu_path in $shells) {
    $nu_path | ^sudo tee -a /etc/shells
  }

  log+ "Installing nufmt..."
  cargo install --git https://github.com/nushell/nufmt
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

  let nvim_config_bak = ($env.HOME | path join ".config/nvim.bak")
  let nvim_share      = ($env.HOME | path join ".local/share/nvim")
  let nvim_share_bak  = ($env.HOME | path join ".local/share/nvim.bak")
  let nvim_state      = ($env.HOME | path join ".local/state/nvim")
  let nvim_state_bak  = ($env.HOME | path join ".local/state/nvim.bak")
  let nvim_cache      = ($env.HOME | path join ".cache/nvim")
  let nvim_cache_bak  = ($env.HOME | path join ".cache/nvim.bak")

  do -i { ^trash $nvim_config_bak }
  do -i { ^mv $nvim_config $nvim_config_bak }
  mkdir $nvim_config
  do -i { ^mv $nvim_share $nvim_share_bak }
  do -i { ^mv $nvim_state $nvim_state_bak }
  do -i { ^mv $nvim_cache $nvim_cache_bak }

  ^git clone --depth 1 https://github.com/AstroNvim/template $nvim_config
  ^rm -rf $"($nvim_config)/.git"
}

def fish-setup [] {
  let fish_path = (which fish | first | get path)
  let shells = (open /etc/shells | lines)

  if not ($fish_path in $shells) {
    $fish_path | ^sudo tee -a /etc/shells
  }

  stow-package "fish"

  log+ "Setting fish as default shell"
  if (has-cmd chsh) {
    ^chsh -s $fish_path
  }
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
  nushell-setup
  fish-setup
}

def "main devtools" [] {
  let mise_bin = ($env.HOME | path join ".local/bin/mise")

  if not ($mise_bin | path exists) {
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
  mut items: list<record<description: string, handler: closure>> = []

  $items = $items ++ [
    { description: "Install system packages",           handler: { main system-shell } }
    { description: "Install incus",                     handler: { main incus } }
    { description: "Setup dotfiles with stow",          handler: { main dotfiles } }
    { description: "Install shell tools",               handler: { main shell } }
    { description: "Install devtools (mise, uv etc)",   handler: { main devtools } }
    { description: "Install Neovim",                    handler: { main nvim } }
    { description: "Install claude",                    handler: { main claude } }
    { description: "Install rustup",                    handler: { main rust } }
  ]

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
    log+ "Installing niri"
    paru-install
    ^paru -S niri dms-shell-bin
  }

  stow-package "niri"

  let niri_dms = ($env.HOME | path join ".config/niri/dms")
  do -i { mkdir $niri_dms }

  let dms_files = ["alttab" "colors" "layout" "wpblur" "binds" "cursor" "outputs"]
  for f in $dms_files {
    let file_path = ($niri_dms | path join $"($f).kdl")
    if not ($file_path | path exists) {
      touch $file_path
    }
  }

  do -i { ^systemctl --user add-wants niri.service dms }
}

def "main mangowc" [] {
  if (has-cmd dms) and (has-cmd mango) {
    log+ "mangowc and dms are already installed"
    return
  }

  log+ "Installing mangowc"
  wm-install

  paru-install
  ^paru -S mangowc-git dms-shell-bin

  let config_dir = ($env.HOME | path join ".local/share/linux-config")

  log+ "Stowing mangowc dotfiles"
  ^stow --no-folding --adopt --dir $config_dir --target $env.HOME mango systemd
  do -i { ^git -C $config_dir stash --include-untracked --message "Stashing mangowc dotfiles" }

  let mango_dms = ($env.HOME | path join ".config/mango/dms")
  do -i { mkdir $mango_dms }

  let dms_files = ["alttab" "colors" "layout" "wpblur" "binds" "cursor" "outputs"]
  for f in $dms_files {
    let file_path = ($mango_dms | path join $"($f).conf")
    if not ($file_path | path exists) {
      touch $file_path
    }
  }

  do -i { ^systemctl --user add-wants wm-session.target dms }
}

def "main hypr" [] {
  if (has-cmd dms) and (has-cmd hyprctl) {
    log+ "hyprland and dms are already installed"
    return
  }

  log+ "Installing hyprland"
  wm-install

  paru-install
  ^paru -S hyprland dms-shell-bin

  stow-package "hypr"

  let hypr_dms = ($env.HOME | path join ".config/hypr/dms")
  do -i { mkdir $hypr_dms }

  let dms_files = ["alttab" "colors" "layout" "wpblur" "binds" "cursor" "outputs"]
  for f in $dms_files {
    let file_path = ($hypr_dms | path join $"($f).conf")
    if not ($file_path | path exists) {
      touch $file_path
    }
  }

  do -i { ^systemctl --user add-wants hyprland-session.target dms }
  do -i { ^systemctl --user add-wants wm-session.target dms }
}

def "main sway" [] {
  if (has-cmd sway) {
    log+ "sway is already installed"
    return
  }

  log+ "Installing sway"
  wm-install

  si ["sway"]

  stow-package "sway"
}

def "main flatpaks" [] {
  if not (has-cmd flatpak) {
    si ["flatpak"]
  }

  log+ "Adding flathub remote"
  ^flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo --user

  let flatpaks = [
    "app.zen_browser.zen"
    "com.github.tchx84.Flatseal"
    "com.spotify.Client"
    "io.github.flattool.Ignition"
    "io.github.kolunmi.Bazaar"
    "md.obsidian.Obsidian"
    "org.gnome.Firmware"
    "org.gnome.Papers"
    "org.gnome.World.PikaBackup"
    "org.telegram.desktop"
    "sh.loft.devpod"
  ]

  log+ "Installing flatpaks..."
  for pkg in $flatpaks {
    log+ $"Installing ($pkg)"
    do -i { ^flatpak --user install -y flathub $pkg }
  }
}

def "main system-desktop" [] {
  update-packages

  let pkgs = [
    "flatpak"
    "gnome-keyring"
    "pass"
    "plocate"
  ]

  log+ "Installing system packages"
  si $pkgs

  log+ "Installing pywal packages"
  ^pipx install pywal pywalfox
}

def "main cockpit" [] {
  log+ "Installing cockpit"
  let packages = ["cockpit" "cockpit-packagekit" "cockpit-storaged" "cockpit-podman" "cockpit-files" "cockpit-machines"]
  si $packages
}

def "main distrobox" [] {
  log+ "Installing distrobox"
  let packages = ["podman" "distrobox"]
  si $packages
}

def "main vscode" [] {
  if not (has-cmd code) {
    log+ "Installing vscode"
    paru-install
    ^paru -S visual-studio-code-bin
  }

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

  stow-package "vscode"
  stow-package "kitty"
}

def "main zed" [] {
  log+ "Installing zed"
  si ["zed"]

  stow-package "zed"
}

def "main virt" [] {
  log+ "Installing virt-manager"
  let packages = ["virt-manager" "virt-install" "virt-viewer" "libisofs" "guestfs-tools" "qemu-img"]
  si $packages

  let groups = ["libvirt" "qemu" "libvirt-qemu" "kvm" "libvirtd"]
  for group in $groups {
    do -i { ^sudo usermod -aG $group $env.USER }
  }

  ^sudo systemctl enable --now libvirtd
  ^sudo systemctl enable --now virtlogd

  if (has-cmd authselect) {
    ^sudo authselect enable-feature with-libvirt
  }
}

def bootstrap [] {
  path add ([
    "bin"
    ".local/bin"
    ".local/share/pnpm"
    ".npm-packages"
    ".pixi/bin"
    ".local/share/linux-config/bin"
  ] | each { $env.HOME | path join $in | path expand })

  if not (is-arch) {
    die "This script only supports Arch Linux. Quitting."
  }
}

def "main setup-desktop" [] {
  mut items: list<record<description: string, handler: closure>> = []

  $items = $items ++ [
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
    bootstrap
    let sudo_job_id = keep-sudo-alive
    main setup-shell
    main setup-desktop
    stop-sudo-alive $sudo_job_id
}
