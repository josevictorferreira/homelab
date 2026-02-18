{
  kubenix,
  lib,
  pkgs,
  ...
}:
let
  name = "shared-subfolders-proton-sync";
  namespace = "apps";
in
{
  kubernetes.resources.secrets.${name} = {
    metadata = {
      name = "${name}-config";
      inherit namespace;
    };
    stringData = ''
      KEYRING_PASSWORD: ${kubenix.lib.secretsFor "proton_drive_keyring_password"}
      PROTON_USERNAME: ${kubenix.lib.secretsFor "proton_drive_username"}
      PROTON_PASSWORD: ${kubenix.lib.secretsFor "proton_drive_password"}
      MINIO_ACCESS_KEY_ID: ${kubenix.lib.secretsFor "minio_shared_backup_access_key_id"}
      MINIO_SECRET_ACCESS_KEY: ${kubenix.lib.secretsFor "minio_shared_backup_secret_access_key"}
    '';
  };
}
