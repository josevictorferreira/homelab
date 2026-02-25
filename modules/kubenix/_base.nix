{ kubenix, homelab, ... }: {
  imports = [
    kubenix.modules.helm
    kubenix.modules.k8s
    kubenix.modules.submodules
    ./_crds.nix
    ./_submodules/release.nix
  ];

  kubenix.project = homelab.name;

  kubernetes = {
    inherit (homelab.kubernetes) version;
  };
}

