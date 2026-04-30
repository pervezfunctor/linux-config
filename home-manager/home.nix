{ pkgs, vars, ... }:
{
  nixpkgs.config.allowUnfree = true;
  fonts.fontconfig.enable = true;

  home = {
    username = vars.username;
    homeDirectory = vars.homeDirectory;
    stateVersion = "25.11";

    packages = with pkgs; [
      devbox
      devenv
      nil
      nixd
      nixfmt
    ];
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  nix = {
    package = pkgs.nix;

    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      max-jobs = "auto";
      cores = 2;

      substituters = [
        "https://cache.nixos.org/"
      ];

      warn-dirty = false;
    };
  };
}
