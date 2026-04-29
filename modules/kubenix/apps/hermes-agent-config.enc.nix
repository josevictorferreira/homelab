{ kubenix, homelab, ... }:

let
  name = "hermes-agent";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${name}-env" = {
    metadata = {
      name = "${name}-env";
      inherit namespace;
    };
    stringData = {
      ANTHROPIC_API_KEY = kubenix.lib.secretsFor "anthropic_api_key";
      ANTHROPIC_MODEL = kubenix.lib.secretsFor "anthropic_model";
      GEMINI_API_KEY = kubenix.lib.secretsFor "gemini_api_key";
      COPILOT_GITHUB_TOKEN = kubenix.lib.secretsFor "copilot_github_token";
      ELEVENLABS_API_KEY = kubenix.lib.secretsFor "elevenlabs_api_key";
      GITHUB_TOKEN = kubenix.lib.secretsFor "github_token";
      ALIBABA_CODING_PLAN_API_KEY = kubenix.lib.secretsFor "alibaba_coding_plan_api_key";
      KIMI_API_KEY = kubenix.lib.secretsFor "moonshot_api_key";
      GLM_API_KEY = kubenix.lib.secretsFor "z_ai_api_key";
      MATRIX_HOMESERVER = kubenix.lib.secretsFor "hermes_matrix_homeserver";
      MATRIX_ACCESS_TOKEN = kubenix.lib.secretsFor "hermes_matrix_access_token";
      MATRIX_ALLOWED_USERS = kubenix.lib.secretsFor "hermes_matrix_allowed_users";
      MATRIX_ENCRYPTION = kubenix.lib.secretsFor "hermes_matrix_encryption";
      MATRIX_RECOVERY_KEY = kubenix.lib.secretsFor "hermes_matrix_recovery_key";
      MATRIX_HOME_ROOM = kubenix.lib.secretsFor "hermes_matrix_home_room";
      MATRIX_REQUIRE_MENTION = kubenix.lib.secretsFor "hermes_matrix_require_mention";
      MATRIX_AUTO_THREAD = kubenix.lib.secretsFor "hermes_matrix_auto_thread";
    };
  };
}
