{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.backup;
in
{
  kubernetes.resources.secrets."postgresql-auth" = {
    type = "Opaque";
    metadata.name = "postgresql-auth";
    metadata.namespace = namespace;
    stringData = {
      "admin-password" = kubenix.lib.secretsFor "postgresql_admin_password";
      "user-password" = kubenix.lib.secretsFor "postgresql_user_password";
      "replication-password" = kubenix.lib.secretsFor "postgresql_replication_password";
    };
  };
}
