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
          REDIS_URL = "redis://:${kubenix.lib.secretsInlineFor "redis_password"}@redis-headless:6379/3";
          DB_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-hl:5432/immich";
          IMMICH_MACHINE_LEARNING_URL = "http://immich-machine-learning:3003";
        };
      };
    };
  };
}
