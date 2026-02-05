{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets.openclaw-secrets = {
    metadata.namespace = namespace;
    stringData = {
      NODE_ENV = "production";
      OPENCLAW_DATA_DIR = "/home/node/.openclaw";
      OPENCLAW_CONFIG_PATH = "/home/node/.openclaw/openclaw.json";
      OPENCLAW_GATEWAY_TOKEN = kubenix.lib.secretsFor "openclaw_gateway_token";
    };
  };
}
