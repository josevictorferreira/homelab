{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."linkwarden-secrets" = {
        metadata = {
          inherit namespace;
        };
        stringData = {
          "NEXTAUTH_SECRET" = kubenix.lib.secretsFor "linkwarden_auth_secret";
        };
      };

      secrets."linkwarden-db" = {
        metadata = {
          inherit namespace;
        };
        stringData = {
          "uri" =
            "postgresql://postgres:${kubenix.lib.secretsFor "postgresql_admin_password"}+@postgresql-18-hl:5432/linkwarden";
        };
      };
    };
  };
}
