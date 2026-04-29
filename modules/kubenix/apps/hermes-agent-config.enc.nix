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
    };
  };
}
