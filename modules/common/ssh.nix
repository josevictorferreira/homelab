{ lib, config, ... }:

let
  cfg = config.services.ssh;
in
{
  options.services.ssh = {
    enable = lib.mkEnableOption "Enable OpenSSH server";
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
