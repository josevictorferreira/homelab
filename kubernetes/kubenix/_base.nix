{ kubenix, homelab, ... }: {
  imports = [
    kubenix.modules.helm
    kubenix.modules.k8s
    kubenix.modules.submodules
    ./_types.nix
    ./_submodules/release.nix
  ];

  kubenix.project = homelab.name;

  kubernetes = {
    version = homelab.kubernetes.version;
  };
}

