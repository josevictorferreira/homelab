{
  description = "My Homelab Machines NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
  };
  outputs = { self, nixpkgs, sops-nix, ... }@inputs:
    let
      flakeRoot = ./.;
      username = "josevictor";
      clusterConfig = import ./shared/cluster-config.nix;
      hosts = clusterConfig.hosts;

      mkHost = hostName:
        nixpkgs.lib.nixosSystem {
          system = hosts.${hostName}.system;
          specialArgs = {
            inherit self inputs hostName username flakeRoot clusterConfig;
            hostConfig = hosts.${hostName};
          };
          modules = [
            sops-nix.nixosModules.sops
            ./modules/hardware/${hosts.${hostName}.machine}.nix
            ./hosts/base.nix
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs (hostName: _system: mkHost hostName) hosts;
    };
}
