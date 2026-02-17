{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."etcd-snapshot-offload-s3-credentials" = {
    metadata.namespace = namespace;
    stringData = {
      "AWS_ACCESS_KEY_ID" = kubenix.lib.secretsFor "minio_etcd_access_key_id";
      "AWS_SECRET_ACCESS_KEY" = kubenix.lib.secretsFor "minio_etcd_secret_access_key";
    };
  };
}
