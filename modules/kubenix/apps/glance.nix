{ homelab, kubenix, ... }:

let
  # A subPath-mounted ConfigMap is never refreshed by the kubelet, and a
  # ConfigMap-only change leaves the Deployment spec untouched, so Flux would
  # apply the new config while the running pod keeps the old one indefinitely
  # (see apps/AGENTS.md). Hashing the content into a pod annotation makes any
  # config edit roll the Deployment.
  #
  # The config lives in a sibling .enc.nix file because it embeds secrets, and
  # every file under modules/kubenix/ gets its own evalModules call, so the
  # rendered YAML has to be imported directly instead of read from module state.
  # The hash covers the pre-vals text, so editing the config rolls the pod but
  # rotating only a secret value does not.
  glanceConfigYaml =
    (import ./glance-config.enc.nix { inherit homelab kubenix; })
    .kubernetes.resources.configMaps."glance".data."glance.yml";

  configHash = builtins.hashString "sha256" glanceConfigYaml;
in
{
  submodules.instances.glance = {
    submodule = "release";
    args = {
      namespace = homelab.kubernetes.namespaces.applications;
      image = {
        repository = "glanceapp/glance";
        tag = "v0.8.5@sha256:32ab73d80f2b8b5fb0735b0431deb36b93fbb6b2fb43592449b0178c8b83e350";
        pullPolicy = "IfNotPresent";
      };
      port = 8080;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "200m";
          memory = "256Mi";
        };
      };
      config = {
        filename = "glance.yml";
        mountPath = "/app/config";
      };

      values = {
        controllers.main.pod.annotations."glance.josevictor.me/config-hash" = configHash;

        defaultPodOptions.affinity = homelab.kubernetes.affinities.piNode;
        defaultPodOptions.tolerations = [
          {
            key = "pi-only";
            operator = "Equal";
            value = "true";
            effect = "NoSchedule";
          }
        ];
      };
    };
  };
}
