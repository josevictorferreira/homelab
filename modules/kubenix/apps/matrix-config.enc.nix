{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      # Synapse homeserver configuration secret
      secrets."synapse-env" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          # PostgreSQL connection
          "postgres-password" = kubenix.lib.secretsFor "postgresql_admin_password";

          # Synapse secrets
          "macaroon-secret-key" = kubenix.lib.secretsFor "synapse_macaroon_secret_key";
          "form-secret" = kubenix.lib.secretsFor "synapse_form_secret";
          "registration-shared-secret" = kubenix.lib.secretsFor "synapse_registration_shared_secret";
        };
      };

      # Synapse signing key (generated at first startup, but we can provide one)
      secrets."synapse-signing-key" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "matrix.josevictor.me.key" = kubenix.lib.secretsFor "synapse_signing_key";
        };
      };
    };
  };
}
