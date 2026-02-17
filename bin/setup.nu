#!/usr/bin/env nu

use std/log

$env.LOG_FILE = $"($env.HOME)/.linux-config-logs/bootstrap-(date now | format date '%m-%d-%H%M%S').log"

def init-log-file [] {
    mkdir ($env.LOG_FILE | path dirname)
}

def file-log [level: string, msg: string] {
    $"(date now | format date '%m-%d %H:%M:%S') [($level)] ($msg)\n"
    | save --append $env.LOG_FILE
}

def log+ [msg: string] { log info $msg; file-log "INFO" $msg }
def warn+ [msg: string] { log warning $msg; file-log "WARNING" $msg }
def error+ [msg: string] { log error $msg; file-log "ERROR" $msg }
def die [msg: string] { log critical $msg; file-log "CRITICAL" $msg; exit 1 }

def keep-sudo-alive [] {
  sudo -v

  job spawn {
    loop {
      sudo -n true
      sleep 60sec
    }
  }
}

def dir-exists [path: string]: nothing -> bool {
  ($path | path exists) and ($path | path type) == "dir"
}

def is-linux []: nothing -> bool {
  (sys host | get name) == "Linux"
}

def is-mac []: nothing -> bool {
  (sys host | get name) == "Darwin"
}

def has-cmd [cmd: string]: nothing -> bool {
  (which $cmd | first | get path) != null
}

def is-fedora-atomic []: nothing -> bool {
  has-cmd rpm-ostree
}

def is-fedora []: nothing -> bool {
  if (is-fedora-atomic) { return false }

  if not ("/etc/redhat-release" | path exists) { return false }

  let content = (open /etc/redhat-release | str downcase)
  $content =~ "fedora"
}

def is-arch []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release)
  $content =~ "Arch Linux"
}

def is-tw []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release)
  $content =~ "Tumbleweed"
}

def is-trixie []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release | str downcase)
  $content =~ "trixie"
}

def is-questing []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release | str downcase)
  $content =~ "questing"
}

def is-pikaos []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release)
  $content =~ "pika"
}

def is-ubuntu []: nothing -> bool {
  if not ("/etc/os-release" | path exists) { return false }
  let content = (open /etc/os-release)
  $content =~ "Ubuntu"
}

def is-gnome []: nothing -> bool {
  let desktop = ($env.XDG_CURRENT_DESKTOP? | default "")
  let session = ($env.XDG_SESSION_DESKTOP? | default "")
  ($desktop == "GNOME") or ($session == "gnome")
}

def is-apt []: nothing -> bool {
  (is-trixie) or (is-questing) or (is-pikaos)
}

def is-ublue []: nothing -> bool {
  (is-fedora-atomic) and (has-cmd ujust)
}

def prompt-yn [prompt: string]: nothing -> bool {
  let response = (input $"(ansi cyan)? ($prompt)(ansi reset) (ansi yellow)[y/N](ansi reset) ")
  $response =~ "(?i)^y(es)?$"
}

def is-non-atomic-linux []: nothing -> bool {
  (is-linux) and not (is-fedora-atomic)
}

def si [packages: list<string>]: nothing -> bool {
  log+ $"Installing ($packages | str join ' ')"

  let result = if (is-mac) or (is-ublue) {
    do -i { ^brew install ...$packages } | complete
  } else if (is-fedora) {
    do -i { ^sudo dnf install -y ...$packages } | complete
  } else if (is-apt) {
    do -i { ^sudo apt install -y ...$packages } | complete
  } else if (is-tw) {
    do -i { ^sudo zypper --non-interactive --quiet install --auto-agree-with-licenses ...$packages } | complete
  } else if (is-arch) {
    do -i { ^sudo pacman -S --quiet --noconfirm ...$packages } | complete
  } else {
    error+ $"OS not supported. Not installing ($packages | str join ' ')."
    return false
  }

  if $result.exit_code != 0 {
    error+ $"Package installation failed (exit ($result.exit_code)):\n($result.stderr)"
    return false
  }

  true
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

def brew-install [] {
  if (has-cmd brew) { return }

  log+ "Installing brew"
  let install_url = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  ^/bin/bash -c $"curl -fsSL ($install_url) | bash"

  if (is-linux) {
    do -i { ^bash -c "source /home/linuxbrew/.linuxbrew/bin/brew shellenv" }
  }

  ^brew install topgrade gum

  if (is-mac) {
    ^brew install rclone rsync stow tar tmux trash-cli tree unzip zstd
    ^brew install imagemagick starship nushell
  }
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
  ^sudo usermod -aG incus $env.USER
  ^sudo usermod -aG incus-admin $env.USER
  ^sudo systemctl enable --now incus.socket
  ^sudo incus admin init --minimal
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

def "main home-manager" [] {
  if not (has-cmd nix) {
    error make { msg: "nix is required for home-manager" }
  }

  log+ "Setting up home-manager"
  let flake_path = ($env.HOME | path join ".local/share/linux-config/home-manager")
  ^nix run home-manager -- switch --flake $"($flake_path)#($env.USER)" --impure
}

def "main nix" [] {
  if (has-cmd nix) { return }

  log+ "Installing nix"
  let install_url = "https://install.determinate.systems/nix"
  ^curl --proto '=https' --tlsv1.2 -sSf -L $install_url | ^sh -s -- install --determinate --no-confirm

  let nix_profile = "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  if ($nix_profile | path exists) {
    do -i { ^bash -c $"source ($nix_profile)" }
  }
}

def "main system-shell" [] {
  update-packages

  let pkgs = [
    "cmake"
    "gcc"
    "git"
    "make"
    "micro"
    "rclone"
    "rsync"
    "stow"
    "tar"
    "tmux"
    "trash-cli"
    "tree"
    "unzip"
    "zsh"
    "zstd"
  ]

  let pkgs = if (is-tw) {
    $pkgs ++ ["gcc-c++" "micro-editor" "python313-pipx"]
  } else if (is-apt) {
    $pkgs ++ ["g++" "imagemagick" "starship" "pipx"]
  } else if (is-fedora) {
    $pkgs ++ ["g++" "nu" "pipx"]
  } else if (is-arch) {
    $pkgs ++ ["g++" "python-pipx" "nushell"]
  } else {
    $pkgs
  }

  log+ "Installing system packages"
  si $pkgs

  if (is-is-non-atomic-linux) {
    log+ "Updating locate database, this may take a while..."
    do -i { ^sudo updatedb }
  }
}

def pixi-install [] {
  log+ "Installing pixi"

  if not (has-cmd brew) {
    error make { msg: "brew is not installed. Please install brew first." }
  }

  ^brew install pixi

  if not (has-cmd pixi) {
    error make { msg: "pixi failed to install. Aborting pixi package setup." }
  }

  pixi-install-packages
}

def pixi-install-packages [] {
  log+ "Installing shell tools with pixi"

  let pixi_pkgs = [
    "bash-language-server"
    "bat"
    "bottom"
    "carapace"
    "direnv"
    "duf"
    "eza"
    "fd"
    "fzf"
    "gdu"
    "gh"
    "go-gum"
    "go-shfmt"
    "jq"
    "just"
    "lazygit"
    "mask"
    "ripgrep"
    "shellcheck"
    "tealdeer"
    "tectonic"
    "television"
    "tmuxp"
    "xh"
    "yazi"
    "zoxide"
  ]

  ^pixi global install ...$pixi_pkgs

  if not (has-cmd starship) { ^pixi global install starship }
  if not (has-cmd nu)       { ^pixi global install nushell }

  let tldr_path = ($env.HOME | path join ".pixi/bin/tldr")
  ^$tldr_path --update
}

def "main shell" [] {
  brew-install
  pixi-install
}

def "main rust" [] {
  if (has-cmd rustup) {
    log+ "rustup is already installed"
    return
  }

  log+ "Installing rustup"
  ^curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | ^sh
}

def nushell-setup [] {
  let nu_path = (which nu | first | get path)
  let shells = (open /etc/shells | lines)

  if not ($nu_path in $shells) {
    $nu_path | ^sudo tee -a /etc/shells
  }

  stow-package "nushell"
}

def "main nvim" [] {
  if not (has-cmd nvim) {
    ^brew install nvim
  }

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

def zshrc-setup [] {
  stow-package "zsh"

  log+ "Setting zsh as default shell"
  let zsh_path = (which zsh | first | get path)
  if (has-cmd chsh) {
    ^chsh -s $zsh_path
  }
}

def bashrc-setup [] {
  log+ "Setting up bashrc"
  let bashrc = ($env.HOME | path join ".bashrc")
  let source_line = "source ~/.local/share/linux-config/shellrc"

  if ($bashrc | path exists) {
    let content = (open $bashrc)
    if not ($content =~ "linux-config/shellrc") {
      $source_line | save -a $bashrc
    }
  } else {
    $source_line | save $bashrc
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

    warn "git pull --rebase failed. Attempting to abort rebase"
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

  warn "git pull --rebase failed with local changes. Restoring state"
  do -i { ^git -C $repo_dir rebase --abort }
  do -i { ^git -C $repo_dir stash pop }
  error make { msg: "git pull --rebase failed; local changes restored" }
}

def "main dotfiles" [] {
  dotfiles-clone

  if not (is-mac) {
    bashrc-setup
  }
  nushell-setup
  zshrc-setup
}

def "main devtools" [] {
  if not (has-cmd mise) {
    ^curl https://mise.run | ^sh
  }

  log+ "Installing devtools (mise, uv etc)"
  ^brew install uv mise

  let mise_bin = ($env.HOME | path join ".local/bin/mise")

  if not ($mise_bin | path exists) {
    error make { msg: "mise binary not found after install" }
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

  if (is-non-atomic-linux) {
    $items = $items ++ [
      { description: "Install system packages", handler: { main system-shell } }
      { description: "Install incus",           handler: { main incus } }
    ]
  }

  $items = $items ++ [
    { description: "Setup dotfiles with stow",        handler: { main dotfiles } }
    { description: "Install shell tools",             handler: { main shell } }
    { description: "Install devtools (mise, uv etc)", handler: { main devtools } }
    { description: "Install Neovim",                  handler: { main nvim } }
    { description: "Install claude",                  handler: { main claude } }
    { description: "Install rustup",                  handler: { main rust } }
  ]

  if not (is-fedora-atomic) {
    $items = $items ++ [
      { description: "Install nix",                     handler: { main nix } }
    ]
  }

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

def snapper-setup [] {
  if not (has-cmd snapper) {
    log+ "Snapper is not installed. Skipping setup."
    return
  }

  let result = (do -i { ^sudo snapper list-configs } | complete)
  if ($result.stdout =~ "/") {
    log+ "Snapper is already setup for /"
    return
  }

  log+ "Setting up snapper"
  ^sudo snapper create-config /
  ^sudo mkdir -p /var/lib/refind-btrfs
  ^sudo chmod 755 /var/lib/refind-btrfs
  ^sudo systemctl enable refind-btrfs --now
}

def wm-install [] {
  mut pkgs = [
    "cliphist"
    "grim"
    "gvfs"
    "imv"
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

  if (is-ubuntu) { $pkgs = $pkgs ++ ["bibata-cursor-theme"] }
  if (is-fedora) { $pkgs = $pkgs ++ ["gvfs-smb"] }
  if (is-tw) { $pkgs = $pkgs ++ ["pipewire-pulseaudio"] }
  if (is-arch) { $pkgs = $pkgs ++ ["pipewire-jack"] }

  si $pkgs

  if (is-arch) { paru-install }

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

    if (is-pikaos) {
      ^pikman install pika-niri-desktop-minimal pika-niri-settings dms
    } else if (is-fedora) {
      ^sudo dnf copr enable avengemedia/dms
      si ["niri" "dms"]
    } else if (is-questing) {
      ^sudo add-apt-repository ppa:avengemedia/danklinux
      ^sudo add-apt-repository ppa:avengemedia/dms
      ^sudo apt update
      si ["niri" "dms"]
    } else if (is-tw) {
      ^sudo zypper addrepo https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/openSUSE_Tumbleweed/home:AvengeMedia:dms.repo
      ^sudo zypper refresh
      si ["niri" "dms"]
    } else if (is-arch) {
      paru-install
      ^paru -S niri dms-shell-bin
    } else {
      error+ "OS not supported. Not installing niri."
      return
    }
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

  if (is-pikaos) {
    ^pikman install mangowc
  } else if (is-arch) {
    paru-install
    ^paru -S mangowc-git dms-shell-bin
  } else if (is-fedora) {
    if (prompt-yn "need terra repository for installing mango. This is NOT stable. Still enable it?") {
      ^sudo dnf install --nogpgcheck --repofrompath $"terra,https://repos.fyralabs.com/terra$releasever" terra-release
      ^sudo dnf copr enable avengemedia/dms
      si ["mangowc" "dms"]
    }
  } else {
    error+ "Unsupported OS. Not installing mangowc."
    return
  }

  stow-package "mango"
  stow-package "systemd"

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

  if (is-pikaos) {
    ^pikman install pika-hyprland-desktop-minimal pika-hyprland-settings dms
    ^pikman install hyprpolkitagent
  } else if (is-arch) {
    paru-install
    ^paru -S hyprland dms-shell-bin
  } else if (is-tw) {
    ^sudo zypper addrepo https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/openSUSE_Tumbleweed/home:AvengeMedia:dms.repo
    ^sudo zypper refresh
    si ["hyprland" "dms" "hyprpolkitagent"]
  } else {
    error+ "Unsupported OS. Not installing hyprland."
    return
  }

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

  mut pkgs = [
    "flatpak"
    "gnome-keyring"
    "pass"
    "plocate"
  ]

  if (is-tw) { $pkgs = $pkgs ++ ["gopass"] }
  if (is-apt) { $pkgs = $pkgs ++ ["libsecret-tools"] }
  if (is-pikaos) {
    $pkgs = $pkgs ++ ["snapper-gui" "pika-refind-btrfs-hooks" "refind-btrfs"]
  }

  log+ "Installing system packages"
  si $pkgs

  if (is-pikaos) { snapper-setup }

  log+ "Installing pywal packages"
  ^pipx install pywal pywalfox
}

def "main distrobox" [] {
  log+ "Installing distrobox"
  let packages = ["podman" "distrobox"]
  si $packages
}

def "main vscode" [] {
  if not (has-cmd code) {
    if not (has-cmd brew) { brew-install }

    log+ "Installing vscode"
    ^brew tap ublue-os/tap
    ^brew install --cask font-jetbrains-mono-nerd-font font-fontawesome
    ^brew install --cask visual-studio-code-linux
  }

  let extensions = [
    "jdinhlife.gruvbox"
    "jnoortheen.nix-ide"
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
  if not (has-cmd zed) {
    log+ "Installing zed"
    ^curl -f https://zed.dev/install.sh | ^sh
  }

  stow-package "zed"
}

def "main virt" [] {
  log+ "Installing virt-manager"
  let packages = ["virt-manager" "virt-install" "virt-viewer"]
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

def gnome-extensions-install [] {
  if not (has-cmd gext) {
    if not (has-cmd pipx) {
      if (has-cmd pip) {
        ^pip install --user pipx
      }
    }

    if not (has-cmd pipx) {
      warn "pipx not found, skipping gnome extensions"
      return
    }

    ^pipx install gnome-extensions-cli --system-site-packages
  }

  if not (has-cmd gext) {
    warn "gext not found, skipping gnome extensions"
    return
  }

  let extensions = [
    "AlphabeticalAppGrid@stuarthayhurst"
    "blur-my-shell@aunetx"
    "extension-list@tu.berry"
    "just-perfection-desktop@just-perfection"
    "paperwm@paperwm.github.com"
    "search-light@icedman.github.com"
    "switcher@landau.fi"
    "windowsNavigator@gnome-shell-extensions.gcampax.github.com"
  ]

  let optional = [
    "tilingshell@ferrarodomenico.com"
  ]

  for ext in $extensions {
    do -i { ^gext install $ext }
    do -i { ^gext enable $ext }
  }
  for ext in $optional {
    do -i { ^gext install $ext }
    do -i { ^gext disable $ext }
  }
}

def gnome-flatpaks-install [] {
  let flatpaks = [
    "com.mattjakeman.ExtensionManager"
    "org.gtk.Gtk3theme.adw-gtk3"
    "org.gtk.Gtk3theme.adw-gtk3-dark"
    "org.gnome.Logs"
    "io.github.swordpuffin.rewaita"
    "io.missioncenter.MissionCenter"
    "app.devsuite.Ptyxis"
  ]
  for pkg in $flatpaks {
    do -i { ^flatpak --user install -y flathub $pkg }
  }
}

def gnome-settings-install [] {
  ^gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
  ^gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"

  ^gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
  ^gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'
  ^gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

  ^gsettings set org.gnome.desktop.interface gtk-key-theme "Emacs"
  ^gsettings set org.gnome.desktop.interface accent-color 'teal'

  ^gsettings set org.gnome.mutter dynamic-workspaces false
  ^gsettings set org.gnome.desktop.wm.preferences num-workspaces 4

  ^gsettings set org.gnome.desktop.interface monospace-font-name 'JetbrainsMono Nerd Font 11'

  ^gsettings set org.gnome.desktop.wm.preferences resize-with-right-button true
}

def gnome-keybindings-install [] {
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/close-window "['<Super>BackSpace', '<Super>q']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-right "['<Super>Right']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-left "['<Super>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-up "['<Super>Up']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-down "['<Super>Down']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-up "['<Shift><Super>Up']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-down "['<Shift><Super>Down']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-left "['<Shift><Super>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-right "['<Shift><Super>Right']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-up-workspace "['<Super>Page_Up', '<Super><Control>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-down-workspace "['<Super>Page_Down', '<Super><Control>Right']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-up-workspace "['<Shift><Super>Page_Up', '<Super><Control><Shift>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-down-workspace "['<Shift><Super>Page_Down', '<Super><Control><Shift>Right']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/new-window "['<Super>n']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/open-window-position-down "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/open-window-position-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-next "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-previous "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/show-window-position-bar false

  ^dconf write /org/gnome/desktop/wm/keybindings/show-desktop "@as []"

  # Search Light keybindings
  ^dconf write /org/gnome/shell/extensions/search-light/secondary-shortcut-search "['<Super>d']"
  ^dconf write /org/gnome/shell/extensions/search-light/primary-shortcut-search "['<Super>Space']"

  ^dconf write /org/gnome/shell/extensions/dash-to-dock/hot-keys false
  ^dconf write /org/gnome/desktop/wm/preferences/num-workspaces 4
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-1 "['<Super>1']"
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-2 "['<Super>2']"
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-3 "['<Super>3']"
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-4 "['<Super>4']"
  ^dconf write /org/gnome/desktop/wm/preferences/workspace-names "['1', '2', '3', '4']"

  ^dconf write /org/gnome/shell/extensions/paperwm/show-workspace-indicator false
  ^dconf write /org/gnome/shell/extensions/paperwm/show-window-position-bar false

  ^dconf write /org/gnome/shell/extensions/blur-my-shell/panel/blur "false"
}

def "main gnome" [] {
  gnome-extensions-install
  gnome-keybindings-install
  gnome-settings-install
  gnome-flatpaks-install
}

def bootstrap [] {
  let pnpm_home    = ($env.HOME | path join ".local/share/pnpm")
  let dot_bin      = ($env.HOME | path join ".local/share/linux-config/bin")
  let linuxbrew_bin = "/home/linuxbrew/.linuxbrew/bin"
  let pixi_bin     = ($env.HOME | path join ".pixi/bin")
  let home_bin     = ($env.HOME | path join "bin")
  let local_bin    = ($env.HOME | path join ".local/bin")

  $env.PATH = [$dot_bin, $linuxbrew_bin, $pixi_bin, $home_bin, $local_bin, $pnpm_home, $env.PATH]
    | flatten
    | path expand
    | uniq

  brew-install
  keep-sudo-alive

  let supported = (is-fedora) or (is-trixie) or (is-questing) or (is-tw) or (is-arch) or (is-pikaos) or (is-mac) or (is-fedora-atomic)
  if not $supported {
    die "Only Fedora, Questing, Tumbleweed, Arch, PikaOS, macOS, and Fedora Atomic supported. Quitting."
  }
}

def "main setup-desktop" [] {
  mut items: list<record<description: string, handler: closure>> = []

  if not (is-fedora-atomic) {
    $items = $items ++ [
      { description: "Install desktop system packages", handler: { main system-desktop } }
      { description: "Install distrobox",               handler: { main distrobox } }
      { description: "Install virt-manager",            handler: { main virt } }
    ]
  }

  $items = $items ++ [
    { description: "Install vscode",  handler: { main vscode } }
    { description: "Install flatpaks", handler: { main flatpaks } }
    { description: "Install zed",      handler: { main zed } }
  ]

  if (is-gnome) {
    $items = $items ++ [
      { description: "Configure gnome desktop", handler: { main gnome } }
    ]
  }

  if (is-fedora) or (is-questing) or (is-pikaos) or (is-tw) or (is-arch) {
    $items = $items ++ [
      { description: "Install niri", handler: { main niri } }
    ]
  }

  if (is-fedora) or (is-pikaos) or (is-arch) {
    $items = $items ++ [
      { description: "Install mangowc", handler: { main mangowc } }
    ]
  }

  if (is-pikaos) or (is-tw) or (is-arch) {
    $items = $items ++ [
      { description: "Install hyprland", handler: { main hypr } }
    ]
  }

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
  print "setup.nu - Cross-platform Linux/macOS setup script"
  print ""
  print "Usage: nu setup.nu <command>"
  print ""
  print "Commands:"
  print "  setup-shell    Interactive shell setup (packages, dotfiles, tools)"
  print "  setup-desktop  Interactive desktop setup (WMs, flatpaks, apps)"
  print "  system-shell   Install system packages (non-interactive)"
  print "  system-desktop Install desktop packages (non-interactive)"
  print "  dotfiles       Clone and stow dotfiles"
  print "  stow <pkg>     Stow a specific package (niri, nushell, zsh, etc)"
  print "  incus          Install and configure incus"
  print "  nix            Install nix package manager"
  print "  home-manager   Setup home-manager with nix"
  print "  shell          Install shell tools (brew, pixi packages)"
  print "  rust           Install rustup"
  print "  nvim           Install AstroNvim"
  print "  devtools       Install dev tools (mise, uv, node, etc)"
  print "  claude         Install claude CLI"
  print "  niri           Install niri WM"
  print "  mangowc        Install mangowc WM"
  print "  hypr           Install hyprland WM"
  print "  vscode         Install vscode and extensions"
  print "  zed            Install zed editor"
  print "  flatpaks       Install flatpak applications"
  print "  distrobox      Install distrobox"
  print "  virt           Install virt-manager"
  print "  gnome          Configure GNOME desktop with extensions"
  print "  help           Show this help message"
  print ""
  print "Supported Systems:"
  print "  - Fedora (standard and atomic)"
  print "  - Debian Trixie"
  print "  - Ubuntu Questing"
  print "  - openSUSE Tumbleweed"
  print "  - Arch Linux"
  print "  - PikaOS"
  print "  - macOS"
}

def main [] {
  if (is-mac) {
    die "desktop option is not available for mac"
  }

  init-log-file
  bootstrap
  main setup-shell
  main setup-desktop
}
