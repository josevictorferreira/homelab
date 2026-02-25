{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."openrouter-secrets" = {
        metadata = {
          inherit namespace;
        };
        stringData = {
          "OPENROUTER_MODEL" = "qwen/qwen3-next-80b-a3b-instruct";
          "OPENROUTER_API_KEY" = kubenix.lib.secretsFor "openrouter_api_key_linkwarden";
          "OPENROUTER_API_BASE_URL" = "https://openrouter.ai/api/v1";
        };
      };
    };
  };
}
