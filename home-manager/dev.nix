{ pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  home.packages = import ./dev-packages.nix { inherit pkgs; };

  programs = {
    zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;

      shellAliases = {
        update-os = "nix run home-manager -- switch --flake ~/.local/share/chezmoi/home-manager\#$USER" --impure --backup backup;
      };

      shellInit = ''
        if [[ -d "$HOME/.local/share/chezmoi/scripts" ]]; then
          source "$HOME/.local/share/chezmoi/scripts/shellrc"
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
  };

  programs.nix-ld.enable = true;

  services.flatpak.enable = true;

  programs.appimage = {
    enable = true;
    binfmt = true;
  };
}
