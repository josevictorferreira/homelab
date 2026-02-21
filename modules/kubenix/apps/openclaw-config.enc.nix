{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets.openclaw-secrets = {
    metadata.namespace = namespace;
    stringData = {
      NODE_ENV = "production";
      OPENCLAW_DATA_DIR = "/home/node/.openclaw";
      OPENCLAW_CONFIG_PATH = "/home/node/.openclaw/openclaw.json";
      OPENCLAW_GATEWAY_TOKEN = kubenix.lib.secretsFor "openclaw_gateway_token";
      TS_AUTHKEY = kubenix.lib.secretsFor "openclaw_tailscale_authkey";
      GEMINI_API_KEY = kubenix.lib.secretsFor "gemini_api_key";
      OPENROUTER_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_openclaw";
      MINIMAX_API_KEY = kubenix.lib.secretsFor "minimax_api_key";
      KIMI_API_KEY = kubenix.lib.secretsFor "moonshot_api_key";
      OPENCLAW_MATRIX_TOKEN = kubenix.lib.secretsFor "openclaw_matrix_token";
      ELEVENLABS_API_KEY = kubenix.lib.secretsFor "elevenlabs_api_key";
      GITHUB_TOKEN = kubenix.lib.secretsFor "github_token";
      WHATSAPP_NUMBER = kubenix.lib.secretsFor "whatsapp_number";
      WHATSAPP_BOT_NUMBER = kubenix.lib.secretsFor "whatsapp_bot_number";
    };
  };
}
