{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."rgw-mirror-s3-credentials" = {
    metadata.namespace = namespace;
    stringData = {
      # Ceph RGW (source) credentials
      "RCLONE_CONFIG_RGW_ACCESS_KEY_ID" = kubenix.lib.secretsFor "ceph_objectstore_access_key_id";
      "RCLONE_CONFIG_RGW_SECRET_ACCESS_KEY" = kubenix.lib.secretsFor "ceph_objectstore_secret_access_key";
      # MinIO (destination) credentials
      "RCLONE_CONFIG_MINIO_ACCESS_KEY_ID" = kubenix.lib.secretsFor "minio_rgw_access_key_id";
      "RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY" = kubenix.lib.secretsFor "minio_rgw_secret_access_key";
    };
  };
}
