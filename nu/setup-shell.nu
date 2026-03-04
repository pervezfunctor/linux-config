#!/usr/bin/env nu

use ./lib.nu *

def "main nix" [] {
  if (has-cmd nix) {
    log+ "nix is already installed"
    return
  }

  log+ "Installing nix..."
  http get https://install.determinate.systems/nix | ^sh -s -- install --determinate --no-confirm
}

def "main home-manager" [] {
  if not (has-cmd nix) {
    main nix
  }

  log+ "Setting up home-manager"
  let flake_path = ($env.HOME | path join ".local/share/linux-config/home-manager")
  ^nix run home-manager -- switch --flake $"($flake_path)#($env.USER)" --impure -b backup
}

def "main system" [] {
  update-packages

  let pkgs = [
    "cmake"
    "fish"
    "gcc"
    "git"
    "make"
    "micro"
    "stow"
    "tar"
    "tmux"
    "trash-cli"
    "tree"
    "unzip"
    "zstd"
  ]

  let pkgs = if (is-tw) {
    $pkgs ++ ["gcc-c++" "micro-editor" "python313-pipx" "starship"]
  } else if (is-apt) {
    $pkgs ++ ["g++" "starship" "pipx"]
  } else if (is-fedora) {
    $pkgs ++ ["g++" "nu" "pipx"]
  } else if (is-arch) {
    $pkgs ++ ["python-pipx" "nushell" "starship"]
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

def "main pixi packages" [] {
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
    "imagemagick"
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
  if not (has-cmd tmux) { ^pixi global install tmux }
  if not (has-cmd trash) { ^pixi global install trash-cli }

  do -i { ^tldr --update }
}

def "main pixi" [] {
  pixi-install
  main pixi packages
}

def "main shell" [] {
  main pixi
  main brew
}

def "main rust" [] {
  if (has-cmd rustup) {
    log+ "rustup is already installed"
    return
  }

  log+ "Installing rustup..."
  (http get https://sh.rustup.rs) | ^sh
}

def "main nushell config" [] {
  let nu_path = (which nu | get path.0? | default "/usr/bin/nu")
  stow-package "nushell"
}

def "main nvim install" [] {
  if (has-cmd nvim) {
    log+ "nvim already installed"
    return
  }

  if (has-cmd pixi) {
    log+ "Installing neovim with pixi..."
    ^pixi global install nvim
  } else if (has-cmd brew) {
    log+ "Installing neovim with brew..."
    ^brew install neovim
  } else {
    error+ "Cannot install neovim"
  }
}

def "main nvim config" [] {
  let nvim_config = ($env.HOME | path join ".config/nvim")

  if (dir-exists $nvim_config) {
    if not (prompt-yn "Found existing nvim config. Do you want to backup and replace with AstroNvim?") {
      return
    }
  }

  log+ "Setting up AstroNvim..."

  let nvim_config_bak = ($env.HOME | path join ".config/nvim.bak")
  let nvim_share = ($env.HOME | path join ".local/share/nvim")
  let nvim_share_bak = ($env.HOME | path join ".local/share/nvim.bak")
  let nvim_state = ($env.HOME | path join ".local/state/nvim")
  let nvim_state_bak = ($env.HOME | path join ".local/state/nvim.bak")
  let nvim_cache = ($env.HOME | path join ".cache/nvim")
  let nvim_cache_bak = ($env.HOME | path join ".cache/nvim.bak")

  do -i { ^trash $nvim_config_bak $nvim_share_bak $nvim_state_bak $nvim_cache_bak }
  do -i { ^mv $nvim_config $nvim_config_bak }
  do -i { ^mv $nvim_share $nvim_share_bak }
  do -i { ^mv $nvim_state $nvim_state_bak }
  do -i { ^mv $nvim_cache $nvim_cache_bak }

  mkdir $nvim_config
  ^git clone --depth 1 https://github.com/AstroNvim/template $nvim_config
  ^rm -rf $"($nvim_config)/.git"
}

def "main nvim" [] {
  main nvim install
  main nvim config
}

def "main fish config" [] {
  if not (has-cmd fish) {
    error+ "fish not found"
    return
  }

  log+ "setting up fish..."
  stow-package "fish"
}

def "main bash config" [] {
  if not (has-cmd bash) {
    error+ "bash not found"
    return
  }

  let bashrc = ($env.HOME | path join ".bashrc")
  let source_line = "source ~/.local/share/linux-config/shellrc"

  if ($bashrc | path exists) {
    let content = (open $bashrc)
    if not ($content =~ "linux-config/shellrc") {
      log+ "Setting up bashrc..."
      $source_line | save -a $bashrc
    }
  } else {
    log+ $"Creating $bashrc"
    $source_line | save $bashrc
  }
}

const DOTFILES_URL = "https://github.com/pervezfunctor/linux-config.git"
let DOT_DIR = ($nu.home-path | path join ".local/share/linux-config")

def abort-rebase-if-needed [] {
  let rebase_merge = ($DOT_DIR | path join ".git" "rebase-merge")
  let rebase_apply = ($DOT_DIR | path join ".git" "rebase-apply")
  if ($rebase_merge | path exists) or ($rebase_apply | path exists) {
    warn+ "Aborting rebase"
    do -i { ^git -C $DOT_DIR rebase --abort }
  }
}

def dotfiles-clone [] {
  log+ "Cloning dotfiles"
  ^git clone $DOTFILES_URL $DOT_DIR
}

def dotfiles-validate [] {
  ^git -C $DOT_DIR rev-parse --is-inside-work-tree
    | ignore
  let remote_url = (
    ^git -C $DOT_DIR remote get-url origin | str trim
  )
  if ($remote_url | is-empty) {
    error make {
      msg: "Remote URL is empty. Is 'origin' configured?"
    }
  }
  if $remote_url != $DOTFILES_URL {
    error make {
      msg: $"Unexpected remote: expected '($DOTFILES_URL)', got '($remote_url)'"
    }
  }

  ^git -C $DOT_DIR status --porcelain=v1
}

def dotfiles-pull-clean [] {
  log+ "Pulling latest changes (clean repo)"
  let result = (
    do { ^git -C $DOT_DIR pull --rebase --stat } | complete
  )
  if $result.exit_code != 0 {
    abort-rebase-if-needed
    error make {
      msg: "git pull --rebase failed on clean repo"
    }
  }
  log+ "Dotfiles updated"
}

def dotfiles-pull-dirty [] {
  log+ "Stashing local changes before pull"
  let stash_label = (
    $"setup-autostash-(date now | format date '%s')"
  )
  ^git -C $DOT_DIR stash push --include-untracked -m $stash_label

  let pull = (
    do { ^git -C $DOT_DIR pull --rebase --stat } | complete
  )
  if $pull.exit_code != 0 {
    abort-rebase-if-needed
  }

  log+ "Restoring local changes from stash"
  let pop = (
    do { ^git -C $DOT_DIR stash pop } | complete
  )
  if $pop.exit_code != 0 {
    error make {
      msg: "Stash pop failed — working tree may have conflicts"
    }
  }

  if $pull.exit_code != 0 {
    error make {
      msg: "git pull --rebase failed; local changes restored"
    }
  }
  log+ "Dotfiles updated"
}

def "main dotfiles clone" [] {
  let git_dir = ($DOT_DIR | path join ".git")
  if not ($git_dir | path exists) {
    dotfiles-clone
    return
  }

  let status = (dotfiles-validate)
  if ($status | is-empty) {
    dotfiles-pull-clean
  } else {
    dotfiles-pull-dirty
  }
}

def "main dotfiles" [] {
  main dotfiles clone

  main nushell config
  main fish config
}

def "main brew" [] {
  brew-install
}

def "main node" [] {
  if not (has-cmd volta) {
    log+ "Installing volta..."
    (http get https://get.volta.sh) | ^bash
  }

  log+ "Installing latest node with volta..."
  ^volta install node@latest
}

def "main uv" [] {
  if (has-cmd uv) {
    log+ "uv already installed"
  } else {
    log+ "Installing uv..."
    (http get https://astral.sh/uv/install.sh) | ^bash
  }

  if not (has-cmd pipx) {
    log+ "Installing pipx with uv..."
    ^uv tool install pipx
  }
}

def "main mise" [] {
  if (has-cmd mise) {
    log+ "mise already installed"
    return
  }

  log+ "Installing mise"
  (http get https://mise.run) | ^bash
}

def "main claude" [] {
  if (has-cmd claude) {
    log+ "claude is already installed"
    return
  }

  log+ "Installing claude"
  (http get https://claude.ai/install.sh) | ^bash
}

def "main devtools" [] {
  main mise
  main uv
  main node
  main claude

  let npm_pkgs = [
    "@mermaid-js/mermaid-cli"
    "@google/gemini-cli"
    "opencode-ai"
  ]

  log+ "Installing npm packages"
  for pkg in $npm_pkgs {
    ^npm install -g $pkg
  }
}

def "main setup-shell" [] {
  if not ((is-fedora) or (is-trixie) or (is-questing) or (is-tw) or (is-arch) or (is-pikaos) or (is-fedora-atomic)) {
    die "Only Fedora, Questing, Tumbleweed, Arch, PikaOS, and Fedora Atomic supported. Quitting."
  }

  init-log-file
  bootstrap

  mut items = []

  if (is-non-atomic-linux) {
    $items = $items ++ [
      { description: "Install system packages(required)", handler: { main system } }
    ]
  }

  $items = $items ++ [
    { description: "Install shell tools", handler: { main shell } }
    { description: "Setup dotfiles with stow", handler: { main dotfiles } }
    { description: "Install devtools (mise/node/uv/claude)", handler: { main devtools } }
    { description: "Install Neovim", handler: { main nvim } }
    { description: "Install rustup", handler: { main rust } }
  ]

  if not (is-fedora-atomic) {
    $items = $items ++ [
      { description: "Install nix", handler: { main nix } }
    ]
  }

  multi-task $items
}

def "main stow" [package: string] {
  stow-package $package
}

def "main help" [] {
  print "setup-shell.nu - Cross-platform shell setup script"
  print ""
  print "Usage: nu setup-shell.nu <command>"
  print ""
  print "Commands:"
  print "  setup-shell  Interactive shell setup (packages, dotfiles, tools)"
  print ""
  print "  stow         Single package config like nushell"
  print "  system       Install system packages (non-interactive)"
  print "  dotfiles     Clone and stow dotfiles"
  print "  shell        Install shell tools (brew, pixi packages)"
  print "  devtools     Install dev tools (mise, uv, node, etc)"
  print "  nvim         Install AstroNvim"
  print "  claude       Install claude CLI"
  print "  rust         Install rustup"
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
}

def main [] {
  let job_id = keep-sudo-alive
  bootstrap
  main setup-shell
  stop-sudo-alive $job_id
}
