{ kubenix, labConfig, ... }: {
  imports = [
    kubenix.modules.helm
    kubenix.modules.k8s
    kubenix.modules.submodules
    ./_types.nix
    ./_submodules/release.nix
  ];

  kubenix.project = labConfig.project.name;

  kubernetes = {
    version = labConfig.kubernetes.version;
  };
}

