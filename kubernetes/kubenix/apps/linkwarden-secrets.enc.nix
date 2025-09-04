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
          "NEXTAUTH_SECRET" = kubenix.lib.secretsFor "linkwarden_auth_secret";
        };
      };

      secrets."linkwarden-db" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "uri" = "postgresql://postgres:${kubenix.lib.secretsFor "postgresql_admin_password"}+@postgresql-hl:5432/linkwarden";
        };
      };
    };
  };
}
