{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."openrouter-secrets" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "OPENROUTER_MODEL" = kubenix.lib.secretsFor "open_router_model";
          "OPENROUTER_API_KEY" = kubenix.lib.secretsFor "open_router_api_key";
          "OPENROUTER_API_BASE_URL" = "https://openrouter.ai/api/v1";
        };
      };
    };
  };
}
