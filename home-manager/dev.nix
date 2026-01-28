{ pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    act
    antigravity
    bash-language-server
    bat
    bitwarden-cli
    bottom
    carapace
    claude-code
    cmake
    curl
    delta
    devbox
    devenv
    distrobox
    duf
    eza
    fd
    file
    fzf
    g++
    gcc
    gdu
    gemini-cli
    gh
    ghostscript
    git
    gnumake
    gum
    htop
    imagemagick
    jq
    just
    lazydocker
    lazygit
    luarocks
    mask
    neovim
    mermaid-cli
    nerd-fonts.jetbrains-mono
    newt
    nixd
    nixfmt-rfc-style
    nodejs
    nushell
    openssl
    p7zip
    pass
    passt
    plocate
    procs
    ptyxis
    python3
    rclone
    ripgrep
    rsync
    runme
    shellcheck
    shfmt
    stow
    tar
    tealdeer
    tectonic
    tectonic
    television
    tmux
    trash-cli
    tree
    tree-sitter
    unzip
    vscode
    wget
    xh
    yazi
    yq
    zed-editor
    zig
    zoxide
    zstd
  ];

  programs = {
    zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;

      shellAliases = {
        hms = "nix run home-manager -- switch --flake ~/niri-config/home-manager\#$USER" --impure --backup backup;
      };

      shellInit = ''
        if [[ -d "$HOME/niri-config/scripts" ]]; then
          source "$HOME/niri-config/scripts/shellrc"
        fi
      '';
    };

    starship = {
      enable = true;
      interactiveOnly = true;
      transientPrompt.right = true;
    };

    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    nushell = {
      enable = true;
    };

    nix-ld.enable = true;

    appimage = {
      enable = true;
      binfmt = true;
    };
  };
}
