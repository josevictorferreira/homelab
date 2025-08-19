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
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      pkgsFor = s: import nixpkgs { system = s; };

      evalLab = system:
        let lib = (pkgsFor system).lib;
        in (lib.evalModules { modules = [ ./config ]; }).config;

      homelab = (evalLab "x86_64-linux").homelab;

      extendedLib = nixpkgs.lib.extend (selfLib: superLib: {
        strings = (superLib.strings or { }) // (import ./lib/strings.nix { lib = superLib; });
        files = (superLib.files or { }) // (import ./lib/files.nix { lib = superLib; pkgs = null; });
      });

      kubenixFor = system:
        let
          pkgs = pkgsFor system;
          upstreamLib = import (kubenix + "/lib/default.nix") {
            lib = extendedLib;
            inherit pkgs;
          };
          myKubeLib = import ./lib/kubenix.nix {
            lib = extendedLib;
            homelab = (evalLab system).homelab;
            inherit pkgs;
          };
        in
        kubenix // { lib = upstreamLib // myKubeLib; };

      kubenixBundleFor = system:
        import ./kubernetes/kubenix {
          lib = extendedLib;
          kubenix = kubenixFor system;
          homelab = (evalLab system).homelab;
        };

      mkHost = hostName:
        nixpkgs.lib.nixosSystem {
          system = homelab.cluster.hosts.${hostName}.system;
          specialArgs = {
            lib = extendedLib;
            hostConfig = homelab.cluster.hosts.${hostName};
            inherit self inputs hostName homelab;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.mergeAttrs (nixpkgs.lib.mapAttrs (hostName: _system: mkHost hostName) homelab.cluster.hosts) {
        "recovery-iso" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./templates/nixos-recovery-iso.nix ];
        };
      };

      deploy.nodes = nixpkgs.lib.mapAttrs
        (hostName: hostCfg:
          let
            isRemoteNeeded = hostCfg.system != "x86_64-linux";
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

      packages = forAllSystems (system: {
        gen-manifests = (kubenixBundleFor system).mkRenderer system (pkgsFor system);
      });
    };
}
