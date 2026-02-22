{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.backup;
in
{
  kubernetes.resources.secrets."postgres-backup-s3-credentials" = {
    metadata.namespace = namespace;
    stringData = {
      "AWS_ACCESS_KEY_ID" = kubenix.lib.secretsFor "minio_postgres_backup_access_key_id";
      "AWS_SECRET_ACCESS_KEY" = kubenix.lib.secretsFor "minio_postgres_backup_secret_access_key";
    };
  };
}
