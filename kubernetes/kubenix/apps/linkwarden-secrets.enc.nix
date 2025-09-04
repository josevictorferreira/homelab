{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."linkwarden-secrets" = {
        metadata = {
          namespace = namespace;
        };
        data = {
          "ANTHROPIC_MODEL" = kubenix.lib.secretsFor "anthropic_model";
          "ANTHROPIC_API_KEY" = kubenix.lib.secretsFor "anthropic_api_key";
          "uri" = kubenix.lib.secretsFor "linkwarden_database_uri";
        };
      };
    };
  };
}
