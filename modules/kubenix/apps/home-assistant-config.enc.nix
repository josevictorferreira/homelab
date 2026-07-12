{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  domain = "hass.${homelab.domain}";
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

  kubernetes.resources.configMaps."home-assistant-config" = {
    metadata = {
      inherit namespace;
    };
    data = {
      "configuration.yaml" = ''
                  # Configure HTTP proxy settings so Home Assistant trusts the cluster ingress
                  http:
                    use_x_forwarded_for: true
                    trusted_proxies:
                      - 10.0.0.0/8
                      - 172.16.0.0/12
                      - 192.168.0.0/16
                      - 127.0.0.0/8

                  # OpenID Connect authentication via Keycloak homelab realm
                  auth_oidc:
                    client_id: "homeassistant"
                    discovery_url: "https://identity.${homelab.domain}/realms/homelab/.well-known/openid-configuration"
                    display_name: "Keycloak"
        groups_scope: "homeassistant-groups"
            roles:
                      user: homeassistant
                      admin: homeassistantadmin
      '';
    };
  };
}
