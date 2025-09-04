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
        };
      };

      secrets."linkwarden-db" = {
        metadata = {
          namespace = namespace;
        };
        data = {
          "uri" = "postgresql://postgres:${kubenix.lib.secretsFor "postgresql_admin_password"}+@postgresql-hl:5432/linkwarden";
        };
      };
    };
  };
}
