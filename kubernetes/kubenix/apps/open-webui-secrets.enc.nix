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
          "REDIS_URL" = "redis://:${kubenix.lib.secretsFor "redis_password"}+@${homelab.kubernetes.loadBalancer.services.redis}:6379/0";
        };
      };
    };
  };
}
