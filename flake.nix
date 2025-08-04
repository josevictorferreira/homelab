{
  description = "My Homelab Machines NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, sops-nix, ... }@inputs:
    let
      flakeRoot = ./.;
      commonsPath = "${flakeRoot}/modules/commons";
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
    };
}

