{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."hindsight-secrets" = {
    type = "Opaque";
    metadata = {
      name = "hindsight-secrets";
      inherit namespace;
    };
    stringData = {
      HINDSIGHT_API_DATABASE_URL = "postgresql://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl:5432/hindsight";
      HINDSIGHT_API_LLM_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_hindsight";
      HINDSIGHT_API_EMBEDDINGS_OPENROUTER_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_hindsight";
      HINDSIGHT_API_EMBEDDINGS_LITELLM_SDK_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_hindsight";
      HINDSIGHT_API_RERANKER_OPENROUTER_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_hindsight";
    };
  };
}
