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

        "mautrix-whatsapp-env" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            MAUTRIX_WHATSAPP_POSTGRES_URI = "postgres://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl.databases.svc.cluster.local:5432/mautrix_whatsapp?sslmode=disable";
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
      };
    };
  };
}
