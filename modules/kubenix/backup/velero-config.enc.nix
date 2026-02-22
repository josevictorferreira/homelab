{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.backup;
in
{
  kubernetes.resources.secrets."velero-s3-credentials" = {
    metadata.namespace = namespace;
    stringData = {
      cloud = ''
        [default]
        aws_access_key_id=${kubenix.lib.secretsFor "minio_velero_access_key_id"}
        aws_secret_access_key=${kubenix.lib.secretsFor "minio_velero_secret_access_key"}
      '';
    };
  };
}
