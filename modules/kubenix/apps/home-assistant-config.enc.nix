{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."home-assistant-secret" = {
    metadata = {
      inherit namespace;
    };
    stringData = {
      HASS_TOKEN = kubenix.lib.secretsFor "home_assistant_api_token";
    };
  };
}
