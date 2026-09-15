{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.databases;
in
{
  kubernetes.resources.secrets = {
    # Superuser of the CNPG cluster (spec.superuserSecret). Same password the
    # apps already use, so the cutover is a hostname change only. Also used as
    # the externalClusters password for the import from postgresql-18.
    "postgresql-superuser" = {
      metadata = {
        inherit namespace;
      };
      type = "kubernetes.io/basic-auth";
      stringData = {
        username = "postgres";
        password = kubenix.lib.secretsFor "postgresql_admin_password";
      };
    };

    # Pi MinIO credentials for the barman-cloud ObjectStore.
    "postgresql-backup-s3" = {
      metadata = {
        inherit namespace;
      };
      stringData = {
        ACCESS_KEY_ID = kubenix.lib.secretsFor "minio_postgres_backup_access_key_id";
        ACCESS_SECRET_KEY = kubenix.lib.secretsFor "minio_postgres_backup_secret_access_key";
      };
    };
  };
}
