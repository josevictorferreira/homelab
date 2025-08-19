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
      systems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      pkgsFor = s: import nixpkgs { system = s; };

      evalLab = system:
        let lib = (pkgsFor system).lib;
        in (lib.evalModules { modules = [ ./config ]; }).config;

      labConfig = (evalLab "x86_64-linux").homelab;

      extendedLib = nixpkgs.lib.extend (selfLib: superLib: {
        strings = superLib.strings // (import ./lib/strings.nix { lib = superLib; });
        files = superLib // (import ./lib/files.nix { lib = superLib; pkgs = nixpkgs.pkgs; });
      });

      kubenixLib = (import ./kubernetes/kubenix {
        flake = self;
        lib = extendedLib;
        pkgs = nixpkgs.pkgs;
        kubenix = kubenix.extend (selfLib: superLib: {
          lib = superLib // (import "${labConfig.project.paths.lib}/kubenix.nix" { lib = superLib; });
        });
        inherit labConfig;
      });

      mkHost = hostName:
        nixpkgs.lib.nixosSystem {
          system = labConfig.cluster.hosts.${hostName}.system;
          specialArgs = {
            lib = extendedLib;
            hostConfig = labConfig.cluster.hosts.${hostName};
            inherit self inputs hostName labConfig;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.mergeAttrs (nixpkgs.lib.mapAttrs (hostName: _system: mkHost hostName) labConfig.cluster.hosts) {
        "recovery-iso" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./templates/nixos-recovery-iso.nix ];
        };
      };

      deploy.nodes = nixpkgs.lib.mapAttrs
        (hostName: hostCfg:
          let
            isRemoteNeeded = hostCfg.system != "x86_64-linux";
            sshUser = labConfig.users.admin.username;
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
        labConfig.cluster.hosts;

      listNodes = builtins.concatStringsSep "\n" (builtins.attrNames labConfig.cluster.hosts);

      listNodeGroups = builtins.concatStringsSep "\n" (builtins.attrNames labConfig.cluster.nodeGroupHostNames);

      deployGroups = (builtins.mapAttrs (_: values: (builtins.concatStringsSep " " (builtins.map (v: "--targets='.#${v}'") values))) labConfig.cluster.nodeGroupHostNames);

      checks = nixpkgs.lib.mapAttrs
        (sys: deployLib:
          deployLib.deployChecks self.deploy)
        deploy-rs.lib;

      packages = forAllSystems (system: {
        gen-manifests = kubenixLib.mkRenderer system (pkgsFor system);
      });
    };
}
