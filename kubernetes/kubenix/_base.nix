{ kubenix, labConfig, ... }: {
  imports = [
    kubenix.helm
    kubenix.k8s
    kubenix.submodules
    ./_types.nix
    ./_submodules/release.nix
  ];

  kubenix.project = labConfig.project.name;

  kubernetes = {
    version = labConfig.kubernetes.version;
  };
}

