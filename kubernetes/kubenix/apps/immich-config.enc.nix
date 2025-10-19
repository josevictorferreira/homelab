{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."immich-secret" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          REDIS_URL = "ioredis://${kubenix.lib.secretsFor "redis_config_b64"}";
          DB_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-hl:5432/immich";
          DB_HOSTNAME = "postgresql-hl";
          DB_PASSWORD = kubenix.lib.secretsFor "postgresql_admin_password";
          DB_USERNAME = "postgres";
          DB_DATABASE_NAME = "immich";
          IMMICH_MACHINE_LEARNING_URL = "http://immich-machine-learning:3003";
        };
      };
    };
  };
}
