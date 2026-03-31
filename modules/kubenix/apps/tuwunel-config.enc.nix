{ kubenix, homelab, ... }:

let
  app = "tuwunel";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-env" = {
    metadata = { inherit namespace; };
    stringData = {
      "registration_token" = kubenix.lib.secretsFor "tuwunel_registration_token";
      "TUWUNEL_EMERGENCY_PASSWORD" = kubenix.lib.secretsFor "tuwunel_emergency_password";
    };
  };
}
