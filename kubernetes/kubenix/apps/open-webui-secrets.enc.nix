{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."open-webui-secrets" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "DATABASE_URL" = "postgresql://postgres:${kubenix.lib.secretsFor "postgresql_admin_password"}+@postgresql-hl:5432/open-webui";
          "WEBSOCKET_REDIS_URL" = "redis://${kubenix.lib.secretsFor "redis_password"}+@redis-headless:6379/0";
        };
      };
    };
  };
}
