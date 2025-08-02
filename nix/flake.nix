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
      domain = clusterConfig.clusterDomain;
      hosts = clusterConfig.hosts;

      mkHost = hostFqdn:
        nixpkgs.lib.nixosSystem {
          system = hosts.${builtins.head (builtins.split "\\." hostFqdn)}.system;
          specialArgs = {
            inherit self inputs hostFqdn username flakeRoot clusterConfig;
            hostConfig = hosts.${builtins.head (builtins.split "\\." hostFqdn)};
          };
          modules = [
            sops-nix.nixosModules.sops
            ./modules/hardware/${hosts.${builtins.head (builtins.split "\\." hostFqdn)}.machine}.nix
            ./hosts/base.nix
          ];
        };
    in
    {
      nixosConfigurations =
        nixpkgs.lib.mapAttrs'
          (hostName: _: {
            name = "${hostName}.${domain}"; # new key ➜ k8s-node-216-eta.homelab.local
            value = mkHost "${hostName}.${domain}"; # built with FQDN too
          })
          hosts;
    };
}

