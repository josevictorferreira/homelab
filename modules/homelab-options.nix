{ lib, ... }:

with lib;
let
  t = types;

  discoveredProfiles = lib.map (filename: lib.strings.replaceString ".nix" "" filename) (lib.attrNames (builtins.readDir ./profiles));

  discoveredHardwares = lib.map (filename: lib.strings.replaceString ".nix" "" filename) (lib.attrNames (builtins.readDir ./../hosts/hardware));

  roleEnum = t.enum discoveredProfiles;

  machineEnum = t.enum discoveredHardwares;

  nodeHostType = t.submodule {
    options = {
      ipAddress = mkOption { type = t.str; description = "IP address of the node."; };
      system = mkOption { type = t.str; description = "NixOS system architecture, e.g. x86_64-linux or aarch64-linux."; default = "x86_64-linux"; };
      machine = mkOption { type = machineEnum; description = "Hardware type of the node, used to load specific hardware configuration."; };
      interface = mkOption { type = t.str; description = "Primary network interface of the node, e.g. eth0 or enp3s0."; default = "enp1s0"; };
      mac = mkOption { type = t.str; description = "MAC address of the primary network interface of the node."; };
      disks = mkOption { type = t.listOf t.str; description = "List of disk device names (e.g. /dev/sda) attached to the node."; default = [ ]; };
      roles = mkOption { type = t.listOf roleEnum; description = "List of roles assigned to the node, used to load specific configuration profiles."; default = [ ]; };
    };
  };

  nodeGroupType = t.submodule {
    options = {
      configs = mkOption { type = t.attrsOf nodeHostType; description = "Map of node host configurations in this group."; };
      names = mkOption { type = t.listOf t.str; description = "List of node host names in this group."; default = [ ]; };
    };
  };

  nodesConfigType = t.submodule {
    options = {
      hosts = mkOption { type = t.attrsOf nodeHostsType; description = "Map of all node host configurations."; };
      groups = mkOption { type = t.listOf t.str; description = "List of all node group names."; default = [ ]; };
      group = mkOption { type = t.attrsOf nodeGroupType; description = "Map of all node group configurations."; };
    };
  };

  userType = t.submodule {
    options = {
      name = mkOption { type = t.str; description = "Full name of the user."; };
      username = mkOption { type = t.str; description = "Username of the user."; };
      email = mkOption { type = t.str; description = "Email address of the user."; };
      keys = mkOption {
        type = t.listOf t.str;
        description = "List of SSH public keys for the user.";
        default = [ ];
      };
    };
  };

  usersConfigType = mkOption { type = t.attrsOf userType; description = "Map of all user configurations."; };

  loadBalancerType = t.submodule {
    options = {
      address = mkOption { type = t.str; description = "Virtual IP address of the load balancer."; };
      range = mkOption {
        type = t.submodule {
          options = {
            start = mkOption { type = t.str; description = "Start of the floating IP address range."; };
            stop = mkOption { type = t.str; description = "End of the floating IP address range."; };
          };
        };
        description = "Floating IP address range managed by the load balancer.";
      };
      services = mkOption { type = t.attrsOf t.str; description = "Map of service names to their respective ports managed by the load balancer."; default = { http = "80"; https = "443"; }; };
    };
  };

  kubernetesConfigType = t.submodule {
    options = {
      vipAddress = mkOption { type = t.str; description = "Virtual IP address for the Kubernetes API server."; };
      version = mkOption { type = t.str; description = "Kubernetes version to deploy."; default = "stable"; };
      namespaces = mkOption { type = t.attrsOf t.str; description = "List of Kubernetes namespaces to create."; default = [ "default" "kube-system" "kube-public" ]; };
      loadBalancer = mkOption { type = loadBalancerType; description = "Configuration for the load balancer managing Kubernetes API access."; };
    };
  };

  homelabConfigType = t.submodule {
    options = {
      name = mkOption { type = t.str; description = "Name of the homelab cluster."; };
      domain = mkOption { type = t.str; description = "Domain name for the homelab cluster."; };
      timeZone = mkOption { type = t.str; description = "Time zone for the homelab cluster."; default = "UTC"; };
      gateway = mkOption { type = t.str; description = "Default gateway IP address for the homelab network."; };
      dnsServers = mkOption { type = t.listOf t.str; description = "List of DNS server IP addresses."; default = [ ]; };
      paths = mkOption {
        type = t.submodule {
          options = {
            root = mkOption { type = t.str; description = "Root path of the homelab configuration repository."; };
            commons = mkOption { type = t.str; description = "Path to common modules."; };
            profiles = mkOption { type = t.str; description = "Path to configuration profiles."; };
            programs = mkOption { type = t.str; description = "Path to program modules."; };
            services = mkOption { type = t.str; description = "Path to service modules."; };
            kubenix = mkOption { type = t.str; description = "Path to Kubenix configuration."; };
            manifests = mkOption { type = t.str; description = "Path to Kubernetes manifests."; };
            secrets = mkOption { type = t.str; description = "Path to secrets storage."; };
            config = mkOption { type = t.str; description = "Path to additional configuration files."; };
          };
        };
        description = "Paths used in the homelab configuration.";
        default = { };
      };
      users = mkOption { type = usersConfigType; description = "Map of all user configurations."; };
      nodes = mkOption { type = nodesConfigType; description = "Configuration for all nodes in the homelab."; };
      kubernetes = mkOption { type = kubernetesConfigType; description = "Kubernetes cluster configuration."; };
    };
  };

in
{
  options.homelab = mkOption {
    type = homelabConfigType;
    description = "Unified homelab configuration (cluster + nodes + users + kubernetes).";
  };
}
