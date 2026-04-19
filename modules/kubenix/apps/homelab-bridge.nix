{ homelab, kubenix, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "homelab-bridge";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/josevictorferreira/homelab-bridge";
        tag = "bd45fe8@sha256:130d3cfad91ee1ac63fbf956d96a89f5bc1e24a2844a9c89259bd146984279c7";
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
      secretName = "${app}-env";
      values = {
        controllers.main.containers.main.env = {
          PORT = "8080";
          MATRIX_SERVER_URL = "https://matrix.josevictor.me";
          MATRIX_USER = "@homelab-bridge:josevictor.me";
          MATRIX_ROOM_ID = "!qWanbKvLHfAkntFqrn:josevictor.me";
          MATRIX_LOGIN_TYPE = "m.login.password";
        };
      };
    };
  };
}
