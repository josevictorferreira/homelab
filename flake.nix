{
  description = "My Homelab Machines NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, nixpkgs, sops-nix, deploy-rs, ... }@inputs:
    let
      flakeRoot = ./.;
      commonsPath = "${flakeRoot}/modules/common";
      rolesPath = "${flakeRoot}/modules/roles";
      programsPath = "${flakeRoot}/modules/programs";
      servicesPath = "${flakeRoot}/modules/services";
      clusterConfig = import ./config/cluster.nix;
      usersConfig = import ./config/users.nix;
      hosts = clusterConfig.hosts;

      mkHost = hostName:
        nixpkgs.lib.nixosSystem {
          system = hosts.${hostName}.system;
          specialArgs = {
            inherit self inputs usersConfig flakeRoot commonsPath rolesPath programsPath servicesPath clusterConfig;
            hostName = hostName;
            hostConfig = hosts.${hostName};
          };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/default.nix
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs (hostName: _system: mkHost hostName) hosts;

      deploy.nodes = nixpkgs.lib.mapAttrs
        (_hostName: hostCfg:
          let
            sshUser = usersConfig.admin.username;
          in
          {
            hostname = hostCfg.ipAddress;
            sshUser = sshUser;
            fastConnection = true;
            remoteBuild = false;

            profiles.system = {
              user = sshUser;
              path = self.nixosConfigurations.${_hostName}.config.system.build.toplevel;
              autoRollback = true;
            };
          }
        )
        hosts;

      checks = nixpkgs.lib.mapAttrs
        (sys: deployLib:
          deployLib.deployChecks self.deploy)
        deploy-rs.lib;
    };
}

