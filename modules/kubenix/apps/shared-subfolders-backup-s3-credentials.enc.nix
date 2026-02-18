{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."shared-subfolders-backup-s3-credentials" = {
    metadata.namespace = namespace;
    stringData = {
      "AWS_ACCESS_KEY_ID" = kubenix.lib.secretsFor "minio_shared_backup_access_key_id";
      "AWS_SECRET_ACCESS_KEY" = kubenix.lib.secretsFor "minio_shared_backup_secret_access_key";
    };
  };
}
