{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."attic-config" = {
    metadata.namespace = namespace;
    stringData = {
      # api server + garbage collector need the DB; url is constructed inline
      # from the shared postgres admin password (same pattern as bookorbit/dramaturge).
      ATTIC_SERVER_DATABASE_URL =
        "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl:5432/attic";
      # base64 of the HS256 JWT signing secret (openssl rand -base64 64)
      ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64 = kubenix.lib.secretsFor "attic_jwt_secret";
    };
  };
}
