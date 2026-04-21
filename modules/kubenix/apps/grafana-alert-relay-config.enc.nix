{ kubenix, homelab, ... }:

let
  app = "grafana-alert-relay";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-env" = {
    metadata.namespace = namespace;
    stringData = {
      MATRIX_HOMESERVER = "http://tuwunel.apps.svc.cluster.local:8008";
      MATRIX_USER = "@homelab-bridge:josevictor.me";
      MATRIX_PASSWORD = kubenix.lib.secretsFor "homelab_bridge_matrix_password";
      MATRIX_ROOM_ID = "!d0dYdkGOcX7cchTc4H:josevictor.me";
    };
  };
}
