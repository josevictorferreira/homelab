{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets = {
        "synapse-env" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "postgres-password" = kubenix.lib.secretsFor "postgresql_admin_password";
            "macaroon-secret-key" = kubenix.lib.secretsFor "synapse_macaroon_secret_key";
            "form-secret" = kubenix.lib.secretsFor "synapse_form_secret";
            "registration-shared-secret" = kubenix.lib.secretsFor "synapse_registration_shared_secret";
          };
        };

        "synapse-signing-key" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "matrix.josevictor.me.key" = kubenix.lib.secretsFor "synapse_signing_key";
          };
        };

        "mautrix-whatsapp-registration" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "registration.yaml" = kubenix.lib.toYamlStr {
              id = "whatsapp";
              url = "http://mautrix-whatsapp.${namespace}.svc.cluster.local:29318";
              as_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_as_token";
              hs_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_hs_token";
              sender_localpart = "whatsapp";
              namespaces = {
                users = [
                  {
                    exclusive = true;
                    regex = "@whatsapp_.*";
                  }
                ];
                rooms = [ ];
                aliases = [ ];
              };
            };
          };
        };

        "mautrix-whatsapp-config" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "config.yaml" = kubenix.lib.toYamlStr {
              homeserver = {
                address = "http://synapse.${namespace}.svc.cluster.local:8008";
                domain = "josevictor.me";
              };
              appservice = {
                address = "http://mautrix-whatsapp.${namespace}.svc.cluster.local:29318";
                hostname = "0.0.0.0";
                port = 29318;
                database = {
                  type = "postgres";
                  uri = "postgres://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl.databases.svc.cluster.local:5432/mautrix_whatsapp?sslmode=disable";
                };
                as_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_as_token";
                hs_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_hs_token";
                id = "whatsapp";
                bot = {
                  username = "whatsappbot";
                  displayname = "WhatsApp Bridge Bot";
                };
              };
              bridge = {
                username_template = "whatsapp_{{.}}";
                displayname_template = "{{if .BusinessName}}{{.BusinessName}}{{else if .PushName}}{{.PushName}}{{else}}{{.JID}}{{end}} (WA)";
                permissions = {
                  "*" = "relay";
                  "@jose:josevictor.me" = "admin";
                };
                relay = {
                  enabled = true;
                };
              };
              logging = {
                min_level = "info";
                writers = [
                  {
                    type = "stdout";
                    format = "pretty-colored";
                  }
                ];
              };
            };
          };
        };
      };
    };
  };
}
