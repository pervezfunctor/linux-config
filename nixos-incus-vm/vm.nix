{ pkgs, ... }:

{
  users.users.pervez = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "__SSH_KEY__" ];
    shell = pkgs.bash;
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  environment.systemPackages = with pkgs; [
    wget
    curl
  ];
}
