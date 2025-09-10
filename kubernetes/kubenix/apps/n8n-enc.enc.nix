{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."n8n-env" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "redis-password" = kubenix.lib.secretsFor "redis_password";
          "postgres-password" = kubenix.lib.secretsFor "postgresql_admin_password";
          "access-key-id" = kubenix.lib.secretsFor "ceph_objectstore_access_key_id";
          "secret-access-key" = kubenix.lib.secretsFor "ceph_objectstore_secret_access_key";
        };
      };
    };
  };
}
