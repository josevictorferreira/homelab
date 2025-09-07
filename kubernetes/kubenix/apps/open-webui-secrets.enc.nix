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
          "ENV" = "prod";
          "ENABLE_SIGNUP" = "True";
          "OFFLINE_MODE" = "True";
          "ENABLE_WEBSOCKET_SUPPORT" = "True";
          "WEBSOCKET_MANAGER" = "True";
          "ADMIN_EMAIL" = "root@josevictor.me";
          "DATABASE_URL" = "postgresql://postgres:${kubenix.lib.secretsFor "postgresql_admin_password"}+@postgresql-hl:5432/openwebui";
          "REDIS_URL" = "redis://:${kubenix.lib.secretsFor "redis_password"}+@redis-headless:6379/0";
          "WEBUI_SECRET_KEY" = kubenix.lib.secretsFor "openwebui_secret_key";
        };
      };
    };
  };
}
