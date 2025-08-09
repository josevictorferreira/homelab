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
      flakeRoot = ./.;
      currentSystem = builtins.currentSystem or "x86_64-linux";
      pkgs = import nixpkgs { system = currentSystem; };
      commonsPath = "${flakeRoot}/modules/common";
      rolesPath = "${flakeRoot}/modules/roles";
      programsPath = "${flakeRoot}/modules/programs";
      servicesPath = "${flakeRoot}/modules/services";
      k8sManifestsPath = "${flakeRoot}/kubernetes/manifests";
      secretsPath = "${flakeRoot}/secrets";
      extendedLib = nixpkgs.lib.extend (selfLib: superLib: {
        strings = superLib.strings // (import ./lib/strings.nix { lib = superLib; });
      });
      clusterConfig = (import ./config/cluster.nix { lib = extendedLib; });
      usersConfig = import ./config/users.nix;
      hosts = clusterConfig.hosts;
      kubenixModules =
        let
          files = builtins.readDir ./kubernetes/kubenix;
        in
        nixpkgs.lib.filterAttrs
          (name: type: type == "regular" && nixpkgs.lib.hasSuffix ".nix" name)
          files;

      evalModule = filePath:
        (kubenix.evalModules.${currentSystem} {
          modules = [
            (import filePath)
          ];
          specialArgs = {
            inherit kubenix;
            clusterConfig = clusterConfig;
          };
        }).config.kubernetes.resultYAML;

      mkHost = hostName:
        nixpkgs.lib.nixosSystem {
          system = hosts.${hostName}.system;
          specialArgs = {
            lib = extendedLib;
            inherit flakeRoot commonsPath rolesPath programsPath servicesPath k8sManifestsPath secretsPath;
            inherit self inputs hostName usersConfig clusterConfig;
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
            isRemoteNeeded = hostCfg.system != currentSystem;
            sshUser = usersConfig.admin.username;
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
        hosts;

      listNodes = builtins.concatStringsSep "\n" (builtins.attrNames hosts);

      listNodeGroups = builtins.concatStringsSep "\n" (builtins.attrNames clusterConfig.nodeGroups);

      deployGroups = nixpkgs.lib.mapAttrs (_name: values: builtins.concatStringsSep ", " (builtins.map (v: ".#${v}") values)) clusterConfig.nodeGroups;

      checks = nixpkgs.lib.mapAttrs
        (sys: deployLib:
          deployLib.deployChecks self.deploy)
        deploy-rs.lib;

      packages.${currentSystem}.gen-manifests =
        pkgs.runCommand "gen-k8s-manifests" { } ''
          mkdir -p $out
          ${builtins.concatStringsSep "\n" (
            nixpkgs.lib.mapAttrsToList
              (fileName: _: ''
                cp ${evalModule ./kubernetes/kubenix/${fileName}} \
                    $out/${nixpkgs.lib.removeSuffix ".nix" fileName}.yaml
          '')
          kubenixModules
          )}
        '';
    };
}
