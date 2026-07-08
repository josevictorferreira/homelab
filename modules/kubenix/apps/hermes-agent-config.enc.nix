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
      GEMINI_API_KEY = kubenix.lib.secretsFor "gemini_api_key";
      OPENROUTER_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_openclaw";
      OPENROUTER_BASE_URL = "https://openrouter.ai/api/v1";
      MINIMAX_API_KEY = kubenix.lib.secretsFor "minimax_api_key";
      NVIDIA_API_KEY = kubenix.lib.secretsFor "nvidia_api_key";
      NVIDIA_BASE_URL = "https://integrate.api.nvidia.com/v1";
      OPENCODE_GO_API_KEY = kubenix.lib.secretsFor "opencode_go_api_key";
      OPENCODE_GO_BASE_URL = "https://opencode.ai/zen/go/v1";
      ELEVENLABS_API_KEY = kubenix.lib.secretsFor "elevenlabs_api_key";
      GITHUB_TOKEN = kubenix.lib.secretsFor "github_token";
      GH_TOKEN = kubenix.lib.secretsFor "github_token";
      OPENAI_API_KEY = kubenix.lib.secretsFor "openai_api_key";
      OMNIROUTE_API_KEY = kubenix.lib.secretsFor "omniroute_api_key";
      OMNIROUTE_BASE_URL = "https://omniroute.josevictor.me/api/v1";
      MATRIX_HOMESERVER = kubenix.lib.secretsFor "hermes_matrix_homeserver";
      MATRIX_ACCESS_TOKEN = kubenix.lib.secretsFor "hermes_matrix_access_token";
      MATRIX_ALLOWED_USERS = kubenix.lib.secretsFor "hermes_matrix_allowed_users";
      MATRIX_ENCRYPTION = kubenix.lib.secretsFor "hermes_matrix_encryption";
      MATRIX_RECOVERY_KEY = kubenix.lib.secretsFor "hermes_matrix_recovery_key";
      MATRIX_HOME_ROOM = kubenix.lib.secretsFor "hermes_matrix_home_room";
      MATRIX_REQUIRE_MENTION = kubenix.lib.secretsFor "hermes_matrix_require_mention";
      MATRIX_AUTO_THREAD = kubenix.lib.secretsFor "hermes_matrix_auto_thread";

      # Profile-specific Matrix tokens for multi-agent deployment
      HERMES_KIRA_MATRIX_ACCESS_TOKEN = kubenix.lib.secretsFor "hermes_kira_matrix_access_token";
      HERMES_MEL_MATRIX_ACCESS_TOKEN = kubenix.lib.secretsFor "hermes_mel_matrix_access_token";
      HERMES_KIRA_WHATSAPP_ALLOWED_USERS = kubenix.lib.secretsFor "hermes_kira_whatsapp_allowed_users";
      HERMES_SPIKE_MATRIX_ACCESS_TOKEN = kubenix.lib.secretsFor "hermes_spike_matrix_access_token";
      HERMES_LUNA_MATRIX_ACCESS_TOKEN = kubenix.lib.secretsFor "hermes_luna_matrix_access_token";

      # Web search providers
      TAVILY_API_KEY = kubenix.lib.secretsFor "tavily_api_key";
      EXA_API_KEY = kubenix.lib.secretsFor "exa_api_key";
      SEARXNG_URL = kubenix.lib.secretsFor "searxng_url";
      FIRECRAWL_API_KEY = kubenix.lib.secretsFor "firecrawl_api_key";
      # Dashboard OIDC auth
      HERMES_DASHBOARD_OIDC_ISSUER = kubenix.lib.secretsFor "hermes_dashboard_oidc_issuer";
      HERMES_DASHBOARD_OIDC_CLIENT_ID = kubenix.lib.secretsFor "hermes_dashboard_oidc_client_id";
      HERMES_DASHBOARD_OIDC_CLIENT_SECRET = kubenix.lib.secretsFor "hermes_dashboard_oidc_client_secret";
      HERMES_DASHBOARD_PUBLIC_URL = "https://hermes.josevictor.me";
    };
  };
  kubernetes.resources.secrets."${name}-sandbox-nix-ssh" = {
    metadata = {
      name = "${name}-sandbox-nix-ssh";
      inherit namespace;
    };
    stringData = {
      "ssh-private-key" = kubenix.lib.secretsFor "sandbox_nix_ssh_private_key";
    };
  };
}
