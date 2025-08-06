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
      extendedLib = nixpkgs.lib.extend (selfLib: superLib: {
        strings = superLib.strings // (import ./lib/strings.nix { lib = superLib; });
      });
      clusterConfig = import ./config/cluster.nix;
      usersConfig = import ./config/users.nix;
      hosts = clusterConfig.hosts;

      mkHost = hostName:
        nixpkgs.lib.nixosSystem {
          system = hosts.${hostName}.system;
          specialArgs = {
            lib = extendedLib;
            inherit self inputs hostName usersConfig flakeRoot commonsPath rolesPath programsPath servicesPath clusterConfig;
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
        (hostName: hostCfg:
          let
            isRemoteNeeded = hostCfg.system != builtins.currentSystem;
            sshUser = usersConfig.admin.username;
          in
          {
            hostname = hostCfg.ipAddress;
            sshUser = sshUser;
            fastConnection = true;
            remoteBuild = isRemoteNeeded;

            profiles.system = {
              user = sshUser;
              path = deploy-rs.lib.${hostCfg.system}.activate.nixos self.nixosConfigurations.${hostName};
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
