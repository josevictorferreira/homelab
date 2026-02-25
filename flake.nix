{
  description = "My Homelab Machines NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    deploy-rs.url = "github:serokell/deploy-rs";
    kubenix.url = "github:hall/kubenix";
    nix-openclaw.url = "git+https://github.com/openclaw/nix-openclaw?ref=main";
  };

  outputs =
    { self
    , nixpkgs
    , sops-nix
    , deploy-rs
    , kubenix
    , ...
    }@inputs:
    let
      currentSystem = builtins.currentSystem or "x86_64-linux";

      inherit (nixpkgs) lib;

      pkgs = import nixpkgs { system = currentSystem; };

      homelabEval = lib.evalModules {
        modules = [
          ./modules/homelab-options.nix
          ./config/default.nix
        ];
        specialArgs = {
          inherit lib;
        };
      };

      inherit (homelabEval.config) homelab;

      kubenixModule = import ./modules/kubenix {
        inherit
          lib
          pkgs
          kubenix
          homelab
          ;
      };

      mkHost =
        hostName:
        lib.nixosSystem {
          inherit (homelab.nodes.hosts.${hostName}) system;
          specialArgs = {
            hostConfig = homelab.nodes.hosts.${hostName};
            inherit
              lib
              self
              inputs
              hostName
              homelab
              ;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/default.nix
          ];
        };

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    {
      nixosConfigurations =
        lib.mergeAttrs (lib.mapAttrs (hostName: _system: mkHost hostName) homelab.nodes.hosts)
          {
            "recovery-iso" = lib.nixosSystem {
              system = "x86_64-linux";
              modules = [ ./hosts/nixos-recovery-iso.nix ];
            };
          };

      deploy = {
        nodes = lib.mapAttrs
          (
            hostName: hostCfg:
              let
                isRemoteNeeded = hostCfg.system != currentSystem;
                # sshUser = homelab.users.admin.username;
                sshUser = "root";
              in
              {
                hostname = hostCfg.ipAddress;
                inherit sshUser;
                fastConnection = true;
                remoteBuild = isRemoteNeeded;

                profiles.system = {
                  user = "root";
                  path = deploy-rs.lib.${hostCfg.system}.activate.nixos self.nixosConfigurations.${hostName};
                  autoRollback = true;
                };
              }
          )
          homelab.nodes.hosts;
      };

      nodesList = builtins.concatStringsSep "\n" (builtins.attrNames homelab.nodes.hosts);

      nodeGroupsList = builtins.concatStringsSep "\n" homelab.nodes.groups;

      deployGroups = builtins.mapAttrs
        (
          _: values: (builtins.concatStringsSep " " (builtins.map (v: "--targets='.#${v}'") values.names))
        )
        homelab.nodes.group;

      checks = lib.optionalAttrs (lib.hasAttr currentSystem deploy-rs.lib) {
        ${currentSystem} = deploy-rs.lib.${currentSystem}.deployChecks {
          nodes = lib.filterAttrs
            (
              hostName: _: homelab.nodes.hosts.${hostName}.system == currentSystem
            )
            self.deploy.nodes;
        };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      packages = forAllSystems (
        system:
        let
          sysPkgs = nixpkgs.legacyPackages.${system};
          commands = import ./modules/commands.nix {
            pkgs = sysPkgs;
            inherit lib;
            deploy-rs-pkg = deploy-rs.packages.${system}.default;
          };
          openclawNixImage = import ./oci-images/openclaw-nix {
            pkgs = sysPkgs;
            inherit lib inputs system;
          };
        in
        {
          gen-manifests = kubenixModule.mkRenderer system sysPkgs;
          openclaw-nix-image = openclawNixImage;
          inherit (commands)
            lgroups
            check
            lint
            format
            run_ddeploy
            run_deploy
            run_gdeploy
            secrets
            manifests
            kubesync
            reconcile
            events
            wusbiso
            docker-build
            docker-login
            docker-init-repo
            docker-push
            backup-postgres
            restore-postgres
            image-updater
            image-scan
            image-outdated
            push-openclaw
            ghcr-size
            ;
        }
      );

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          buildInputs = with nixpkgs.legacyPackages.${system}; [
            fluxcd
            postgresql
          ];
          shellHook = ''
            git config core.hooksPath .githooks
          '';
        };
      });
    };
}
