{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."paperclip-env" = {
    type = "Opaque";
    metadata = {
      name = "paperclip-env";
      inherit namespace;
    };
    stringData = {
      # Superuser connection to the CNPG cluster, same pattern as hindsight.
      DATABASE_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@${kubenix.lib.postgresHost}:5432/paperclip";
      BETTER_AUTH_SECRET = kubenix.lib.secretsFor "paperclip_better_auth_secret";
      PAPERCLIP_TOOL_ACTION_SIGNING_SECRET = kubenix.lib.secretsFor "paperclip_tool_action_signing_secret";
    };
  };
}
