{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets.matrixx-config = {
    metadata.namespace = namespace;
    stringData = {
      "dendrite.yaml" = kubenix.lib.toYamlStr {
        global = {
          server_name = "josevictor.me";
          private_key = null;
          key_validity_period = "168h0m0s";
          database = {
            connection_string = "postgresql://postgres@postgresql-18-hl.apps.svc.cluster.local:5432/dendrite?sslmode=disable";
            max_open_conns = 90;
            max_idle_conns = 5;
            conn_max_lifetime = -1;
          };
          disable_federation = true;
        };
        client_api = {
          registration_disabled = true;
          guests_disabled = true;
        };
        media_api = {
          base_path = "/data/media";
          max_file_size_bytes = 104857600;
        };
        sync_api = {
          search = {
            enabled = false;
          };
        };
        user_api = {
          internal_api = {
            listen = "http://[::]:7777";
          };
        };
        federation_api = {
          internal_api = {
            listen = "http://[::]:7776";
          };
        };
        app_service_api = {
          internal_api = {
            listen = "http://[::]:7777";
          };
        };
        mscs = {
          mscs = [ ];
        };
      };
    };
  };

  kubernetes.resources.secrets."dendrite-test-password" = {
    metadata.namespace = namespace;
    stringData = {
      dendrite_test_user_password = kubenix.lib.secretsFor "dendrite_test_user_password";
    };
  };
}
