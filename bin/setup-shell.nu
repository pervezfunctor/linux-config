#!/usr/bin/env nu

use ../nu/logs.nu *
use ../nu/lib.nu *
use ../nu/setup-lib.nu *

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

def "main home-manager" [] {
  if not (has-cmd nix) {
    error make { msg: "nix is required for home-manager" }
  }
  log+ "Setting up home-manager"
  let flake_path = ($env.HOME | path join ".local/share/linux-config/home-manager")
  ^nix run home-manager -- switch --flake $"($flake_path)#($env.USER)" --impure
}

def "main system" [] {
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

  if (is-non-atomic-linux) {
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
  if not (has-cmd nu) { ^pixi global install nushell }

  let tldr_path = ($env.HOME | path join ".pixi/bin/tldr")
  if ($tldr_path | path exists) {
    ^$tldr_path --update
  }
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
  let nu_path = (which nu | get path.0? | default "/usr/bin/nu")
  let shells = (open /etc/shells | lines)

  if not ($nu_path in $shells) {
    $nu_path | ^sudo tee -a /etc/shells | ignore
  }

  stow-package "nushell"
}

def "main nvim" [] {
  if not (has-cmd nvim) {
    ^brew install nvim
  }

  let nvim_config = ($env.HOME | path join ".config/nvim")

  if (dir-exists $nvim_config) {
    if not (prompt-yn "Found existing nvim config. Do you want to backup and replace with AstroNvim?") {
      return
    }
  }

  log+ "Installing AstroNvim"

  let nvim_config_bak = ($env.HOME | path join ".config/nvim.bak")
  let nvim_share = ($env.HOME | path join ".local/share/nvim")
  let nvim_share_bak = ($env.HOME | path join ".local/share/nvim.bak")
  let nvim_state = ($env.HOME | path join ".local/state/nvim")
  let nvim_state_bak = ($env.HOME | path join ".local/state/nvim.bak")
  let nvim_cache = ($env.HOME | path join ".cache/nvim")
  let nvim_cache_bak = ($env.HOME | path join ".cache/nvim.bak")

  do -i { ^trash $nvim_config_bak $nvim_share_bak $nvim_state_bak $nvim_cache_bak }
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
  let zsh_path = (which zsh | get path.0? | default "/usr/bin/zsh")
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
    log+ "Cloning dotfiles"
    let clone_result = (do -i { ^git clone $repo_url $repo_dir } | complete)
    if $clone_result.exit_code != 0 {
      error make { msg: $"Failed to clone dotfiles: ($clone_result.stderr)" }
    }
    return
  }

  let is_git = (do -i { ^git -C $repo_dir rev-parse --is-inside-work-tree } | complete)
  if $is_git.exit_code != 0 {
    error make { msg: $"($repo_dir) exists but is not a git repository" }
  }

  let remote_url = (do -i { ^git -C $repo_dir remote get-url origin } | complete)
  if $remote_url.exit_code != 0 {
    error make { msg: "Unable to get remote URL. Is 'origin' configured?" }
  }
  let remote_url_str = ($remote_url.stdout | str trim)
  if ($remote_url_str | is-empty) {
    error make { msg: "Remote URL is empty. Is 'origin' configured?" }
  }
  if $remote_url_str != $repo_url {
    error make { msg: $"Unexpected remote: expected '($repo_url)', got '($remote_url_str)'" }
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
  let stash_result = (do -i { ^git -C $repo_dir stash push --include-untracked --message $stash_label } | complete)
  if $stash_result.exit_code != 0 {
    error make { msg: $"Failed to stash local changes: ($stash_result.stderr)" }
  }

  let pull = (do -i { ^git -C $repo_dir pull --rebase --stat } | complete)
  if $pull.exit_code == 0 {
    log+ "Pull succeeded. Restoring local changes"
    let pop_result = (do -i { ^git -C $repo_dir stash pop } | complete)
    if $pop_result.exit_code != 0 {
      warn+ "Stash pop had conflicts. Resolve manually and check your local changes."
      warn+ $pop_result.stderr
    }
    return
  }

  warn+ "git pull --rebase failed with local changes. Restoring state"
  do -i { ^git -C $repo_dir rebase --abort }
  let pop_result = (do -i { ^git -C $repo_dir stash pop } | complete)
  if $pop_result.exit_code != 0 {
    warn+ "Stash pop had conflicts after abort. Resolve manually."
    warn+ $pop_result.stderr
  }
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
  $npm_pkgs | each { |pkg|
    log+ $"Installing ($pkg)"
    if $use_pnpm { ^pnpm install -g $pkg } else { ^npm install -g $pkg }
  }
}

# Install claude CLI from Anthropic
def "main claude" [] {
  if (has-cmd claude) {
    log+ "claude is already installed"
    return
  }
  log+ "Installing claude"
  ^curl -fsSL https://claude.ai/install.sh | ^bash
}

def "main incus" [] {
  if not (has-cmd incus) {
    log+ "Installing incus"
    si ["incus"]
  }

  incus-setup
}


def "main setup-shell" [] {
  let supported = (is-fedora) or (is-trixie) or (is-questing) or (is-tw) or (is-arch) or (is-pikaos) or (is-mac) or (is-fedora-atomic)
  if not $supported {
    die "Only Fedora, Questing, Tumbleweed, Arch, PikaOS, macOS, and Fedora Atomic supported. Quitting."
  }

  init-log-file
  bootstrap

  let items = (
    []
    | if (is-non-atomic-linux) {
        append [
          { description: "Install system packages", handler: { main system } }
          { description: "Install incus", handler: { main incus } }
        ]
      } else {}
    | append [
        { description: "Setup dotfiles with stow", handler: { main dotfiles } }
        { description: "Install shell tools", handler: { main shell } }
        { description: "Install devtools (mise, uv etc)", handler: { main devtools } }
        { description: "Install Neovim", handler: { main nvim } }
        { description: "Install claude", handler: { main claude } }
        { description: "Install rustup", handler: { main rust } }
      ]
    | if (not (is-fedora-atomic)) {
        append [
          { description: "Install nix", handler: { main nix } }
        ]
      } else {}
  )

  let selected = ($items | input list --multi --display description "Select tasks to execute:")

  if ($selected | is-empty) {
    log+ "No tasks selected."
    return
  }

  for item in $selected {
    log+ $"Executing: ($item.description)"
    do $item.handler
  }

  cleanup-sudo
}

def "main help" [] {
  print "setup-shell.nu - Cross-platform shell setup script"
  print ""
  print "Usage: nu setup-shell.nu <command>"
  print ""
  print "Commands:"
  print "  setup-shell  Interactive shell setup (packages, dotfiles, tools)"
  print "  system       Install system packages (non-interactive)"
  print "  dotfiles     Clone and stow dotfiles"
  print "  shell        Install shell tools (brew, pixi packages)"
  print "  devtools     Install dev tools (mise, uv, node, etc)"
  print "  nvim         Install AstroNvim"
  print "  claude       Install claude CLI"
  print "  rust         Install rustup"
  print "  incus        Install and configure incus"
  print "  nix          Install nix package manager"
  print "  home-manager Setup home-manager with nix"
  print "  help         Show this help message"
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
  main setup-shell
}
