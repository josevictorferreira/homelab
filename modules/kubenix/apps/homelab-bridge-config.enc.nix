{ kubenix, homelab, ... }:

let
  app = "homelab-bridge";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-env" = {
    metadata.namespace = namespace;
    stringData = {
      GITHUB_WEBHOOK_SECRET = kubenix.lib.secretsFor "homelab_bridge_github_webhook_secret";
      MATRIX_PASSWORD = kubenix.lib.secretsFor "homelab_bridge_matrix_password";
      TS_AUTHKEY = kubenix.lib.secretsFor "homelab_bridge_tailscale_authkey";
    };
  };
}
