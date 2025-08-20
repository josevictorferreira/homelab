{
  description = "My Homelab Machines NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    deploy-rs.url = "github:serokell/deploy-rs";
    kubenix.url = "github:hall/kubenix";
  };

  outputs = { self, nixpkgs, sops-nix, deploy-rs, kubenix, ... }@inputs:
    let
      currentSystem = builtins.currentSystem or "x86_64-linux";

      pkgs = import nixpkgs { system = currentSystem; };

      homelab = (import ./config { lib = pkgs.lib; });

      kubenixModule = import ./kubernetes/kubenix {
        lib = pkgs.lib;
        inherit pkgs kubenix homelab;
      };

      mkHost = hostName:
        nixpkgs.lib.nixosSystem {
          system = homelab.cluster.hosts.${hostName}.system;
          specialArgs = {
            lib = pkgs.lib;
            hostConfig = homelab.hosts.${hostName};
            inherit self inputs hostName homelab;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/default.nix
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.mergeAttrs (nixpkgs.lib.mapAttrs (hostName: _system: mkHost hostName) homelab.cluster.hosts) {
        "recovery-iso" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./hosts/nixos-recovery-iso.nix ];
        };
      };

      deploy.nodes = nixpkgs.lib.mapAttrs
        (hostName: hostCfg:
          let
            isRemoteNeeded = hostCfg.system != currentSystem;
            sshUser = homelab.users.admin.username;
          in
          {
            hostname = hostCfg.ipAddress;
            sshUser = sshUser;
            fastConnection = true;
            remoteBuild = isRemoteNeeded;

            profiles.system = {
              user = "root";
              path = deploy-rs.lib.${hostCfg.system}.activate.nixos self.nixosConfigurations.${hostName};
              autoRollback = true;
            };
          }
        )
        homelab.cluster.hosts;

      listNodes = builtins.concatStringsSep "\n" (builtins.attrNames homelab.cluster.hosts);

      listNodeGroups = builtins.concatStringsSep "\n" (builtins.attrNames homelab.cluster.nodeGroupHostNames);

      deployGroups = (builtins.mapAttrs (_: values: (builtins.concatStringsSep " " (builtins.map (v: "--targets='.#${v}'") values))) homelab.cluster.nodeGroupHostNames);

      checks = nixpkgs.lib.mapAttrs
        (sys: deployLib:
          deployLib.deployChecks self.deploy)
        deploy-rs.lib;

      packages.${currentSystem}.gen-manifests =
        kubenixModule.mkRenderer currentSystem pkgs;
    };
}
