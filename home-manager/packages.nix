{ pkgs, ... }:
{
  home.packages = with pkgs; [
    devbox
    devenv
    nil
    nixd
    nixfmt
  ];
}
