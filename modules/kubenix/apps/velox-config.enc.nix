{ kubenix, homelab, ... }:

let
  app = "velox";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  # Velox reads no credentials from its TOML config; each *_env key there names
  # one of these variables. Velox refuses to start if any is missing or empty,
  # so a rotation that drops a key fails the readiness probe rather than
  # silently 502-ing at request time.
  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData = {
      # Comma-separated client keys. Clients authenticate with:
      #   Authorization: Bearer <key>
      VELOX_API_KEYS = kubenix.lib.secretsFor "velox_api_keys";

      # --- provider credentials (one per providers.<id>.api_key_env) ---
      OPENCODE_GO_API_KEY = kubenix.lib.secretsFor "velox_opencode_go_api_key";
      OPENROUTER_API_KEY = kubenix.lib.secretsFor "velox_openrouter_api_key";
      GLM_API_KEY = kubenix.lib.secretsFor "velox_glm_api_key";
      ALIBABA_TOKEN_PLAN_API_KEY = kubenix.lib.secretsFor "velox_alibaba_token_plan_api_key";
      YOLOAUTO_API_KEY = kubenix.lib.secretsFor "velox_yoloauto_api_key";
      NEURALWATT_API_KEY = kubenix.lib.secretsFor "velox_neuralwatt_api_key";
      XIAOMI_MIMO_API_KEY = kubenix.lib.secretsFor "velox_xiaomi_mimo_api_key";
      CEREBRAS_API_KEY = kubenix.lib.secretsFor "velox_cerebras_api_key";
      NVIDIA_API_KEY = kubenix.lib.secretsFor "velox_nvidia_api_key";
      MISTRAL_API_KEY = kubenix.lib.secretsFor "velox_mistral_api_key";
      BAZAARLINK_API_KEY = kubenix.lib.secretsFor "velox_bazaarlink_api_key";
      PUTER_API_KEY = kubenix.lib.secretsFor "velox_puter_api_key";
      NANOGPT_API_KEY = kubenix.lib.secretsFor "velox_nanogpt_api_key";
      KIMI_API_KEY = kubenix.lib.secretsFor "moonshot_api_key";
    };
  };
}
