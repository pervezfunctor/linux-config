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
  let flake_path = ($env.HOME | path join ".linux-config/home-manager")
  ^nix run home-manager -- switch --flake $"($flake_path)#($env.USER)" --impure -b backup
}

def "main system" [] {
  update-packages

  mut pkgs = [
    "fish"
    "gcc"
    "git"
    "less"
    "make"
    "tar"
    "tmux"
    "tree"
    "unzip"
    "zstd"
  ]

  if (is-tw) or (is-apt) {
      $pkgs ++= ["libatomic1"]
  } else if ((is-fedora) or (is-arch)) {
      $pkgs ++= ["libatomic"]
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
    "nushell"
    "ripgrep"
    "shellcheck"
    "tealdeer"
    "tectonic"
    "television"
    "tmuxp"
    "trash-cli"
    "xh"
    "yazi"
    "zoxide"
  ]

  ^pixi global install ...$pixi_pkgs

  if not (has-cmd tmux) { ^pixi global install tmux }

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

  log+ "Installing neovim with pixi..."
  ^pixi global install nvim
}

def "main nvim astro" [] {
  let nvim = $env.HOME | path join ".config/nvim"
  let nvim_share = $env.HOME | path join ".local/share/nvim"
  let nvim_state = $env.HOME | path join ".local/state/nvim"
  let nvim_cache = $env.HOME | path join ".cache/nvim"

  if ($nvim | path exists) and not (prompt-yn "Found existing nvim config. Replace with AstroNvim?") {
    return
  }

  log+ "Configuring AstroNvim..."
  for dir in [$nvim, $nvim_share, $nvim_state, $nvim_cache] {
    if not ($dir | path exists) { continue }
    let bak = $"($dir).bak"
    ignore-error {|| ^trash $bak }
    ignore-error {|| ^mv $dir $bak }
  }

  ^git clone --depth 1 https://github.com/AstroNvim/template $nvim
  ^rm -rf $"($nvim)/.git"
}

def "main nvim" [] {
  main nvim install
  main nvim astro
}

def "main fish config" [] {
  if not (has-cmd fish) {
    error+ "fish not found"
    return
  }

  log+ "setting up fish..."
  stow-package "fish"

  log+ "Change default shell to fish"
  ignore-error {|| ^sudo chsh -s /usr/bin/fish $env.USER }
}

def "main fish" [] {
  si ["fish"]
  main fish config
}

const DOTFILES_URL = "https://github.com/pervezfunctor/linux-config.git"
const DOT_DIR = ($nu.home-dir | path join ".linux-config")

def abort-rebase-if-needed [] {
  let rebase_merge = ($DOT_DIR | path join ".git" "rebase-merge")
  let rebase_apply = ($DOT_DIR | path join ".git" "rebase-apply")
  if ($rebase_merge | path exists) or ($rebase_apply | path exists) {
    warn+ "Aborting rebase"
    ignore-error {|| ^git -C $DOT_DIR rebase --abort }
  }
}

def dotfiles-clone [] {
  log+ "Cloning dotfiles"
  ^git clone $DOTFILES_URL $DOT_DIR
}

def "main shell default" [shell: string] {
  log+ $"Setting ($shell) as default shell"
  let shell_path = (which $shell | get 0.path)
  if not (open /etc/shells | lines | any {|l| $l == $shell_path }) {
    $shell_path | sudo tee -a /etc/shells
  }
  if not (is-shell-default $shell_path) {
    do -i { chsh -s $shell_path $env.USER }
  }
}

def "main shell autostart" [shell: string, rc: string] {
  let rc_path = ($env.HOME | path join $rc)
  let marker = $"exec ($shell)"
  let launched_var = $"(($shell | str upcase))_LAUNCHED"

  let snippet = $"
# Auto-start ($shell) for interactive shells
if [[ \$- == *i* ]] && [[ -z \"\$($launched_var)\" ]]; then
  if command -v ($shell) >/dev/null 2>&1; then
    export ($launched_var)=1
    exec ($shell) || echo \"Failed to start ($shell)\"
  fi
fi
"

  if not ($rc_path | path exists) {
    error make {msg: $"($rc) not found"}
  }
  if not (open $rc_path | str contains $marker) {
    $snippet | save --append $rc_path
    log+ $"Added ($shell) auto-start to ($rc)"
  } else {
    log+ $"($shell) auto-start already in ($rc), skipping"
  }
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

def "main bun" [] {
  if (has-cmd bun) {
    warn+ "bun already installed. Skipping."
  }

  log+ "Installing bun..."
  curl -fsSL https://bun.com/install | bash
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

def "main npm pacakges" [] {
  if not (has-cmd npm) {
    error+ "npm not installed. Use 'setup-shell.nu node' to install."
    return
  }

  let npm_pkgs = [
    "@google/gemini-cli"
    "@mermaid-js/mermaid-cli"
    "opencode-ai"
    @openai/codex
    "typescript"
  ]

  log+ "Installing npm packages"
  for pkg in $npm_pkgs {
    ^npm install -g $pkg
  }
}

def "main devtools" [] {
  main mise
  main uv
  main claude
  main node
  main bun
  main npm pacakges
}

def "main setup-shell" [] {
  if not ((is-fedora) or (is-trixie) or (is-resolute) or (is-tw) or (is-arch) or (is-pikaos) or (is-fedora-atomic)) {
    die "Only Fedora, Ubuntu(resolute), Tumbleweed, Arch, PikaOS, and Fedora Atomic supported. Quitting."
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
      { description: "Install home-manager", handler: { main home-manager } }
    ]
  }

  multi-task $items
}

def "main stow" [package: string] {
  stow-package $package
}

def "main help" [] {
  print "setup-shell.nu - Linux shell setup script"
  print ""
  print "Usage:"
  print "  nu setup-shell.nu"
  print "  nu setup-shell.nu help"
  print "  nu setup-shell.nu <command> [args]"
  print ""
  print "Commands:"
  print "  setup-shell      Interactive shell setup (same as running with no command)"
  print "  help             Show this help message"
  print ""
  print "  system           Install system packages (non-interactive)"
  print "  shell            Install shell tools (pixi packages + brew)"
  print "  pixi             Install pixi and shell tool packages"
  print "  pixi packages    Install shell tool packages with pixi"
  print "  brew             Install Homebrew"
  print "  nix              Install nix package manager"
  print "  home-manager     Setup home-manager with nix"
  print ""
  print "  dotfiles         Clone/update dotfiles and apply shell config"
  print "  dotfiles clone   Clone/update dotfiles only"
  print "  nushell config   Stow Nushell config"
  print "  fish config      Stow fish config and set fish as default shell"
  print "  stow <package>   Stow a single package (example: nushell)"
  print ""
  print "  devtools         Install developer tools and global npm packages"
  print "  mise             Install mise"
  print "  uv               Install uv and pipx"
  print "  node             Install Node.js with volta"
  print "  bun              Install bun"
  print "  npm pacakges     Install global npm packages"
  print "  claude           Install claude CLI"
  print ""
  print "  nvim             Install and configure AstroNvim"
  print "  nvim install     Install Neovim only"
  print "  nvim astro       Configure AstroNvim only"
  print "  rust             Install rustup"
  print ""
  print "Supported Systems:"
  print "  - Fedora (standard and atomic)"
  print "  - Debian Trixie"
  print "  - Ubuntu resolute"
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
