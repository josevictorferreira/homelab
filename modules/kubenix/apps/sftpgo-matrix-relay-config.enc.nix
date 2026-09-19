{ kubenix, homelab, ... }:

let
  app = "sftpgo-matrix-relay";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets.${app} = {
    metadata = {
      inherit namespace;
    };
    stringData = {
      MATRIX_ACCESS_TOKEN = kubenix.lib.secretsFor "sftpgo_matrix_access_token";
    };
  };
}
