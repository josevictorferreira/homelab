{ kubenix, homelab, ... }:
let
  name = "shared-subfolders-proton-sync";
  namespace = homelab.kubernetes.namespaces.backup;
in
{
  kubernetes.resources.secrets.${name} = {
    metadata = {
      name = "${name}-config";
      inherit namespace;
    };
    stringData = {
      PROTON_USERNAME = kubenix.lib.secretsFor "proton_drive_username";
      PROTON_PASSWORD = kubenix.lib.secretsFor "proton_drive_password";
    };
  };
}
