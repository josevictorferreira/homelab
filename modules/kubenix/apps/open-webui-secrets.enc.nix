{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."open-webui-secrets" = {
        metadata = { inherit namespace; };
        stringData = {
          "ENV" = "prod";
          "ENABLE_SIGNUP" = "True";
          "OFFLINE_MODE" = "True";
          "ENABLE_WEBSOCKET_SUPPORT" = "True";
          "WEBSOCKET_MANAGER" = "True";
          "ADMIN_EMAIL" = "root@josevictor.me";
          "DATABASE_URL" =
            "postgresql://postgres:${kubenix.lib.secretsFor "postgresql_admin_password"}+@postgresql-18-hl:5432/openwebui";
          "REDIS_URL" = "redis://:${kubenix.lib.secretsFor "redis_password"}+@redis-headless:6379/0";
          "WEBUI_SECRET_KEY" = kubenix.lib.secretsFor "openwebui_secret_key";
          "ENABLE_RAG" = "True";
          "ENABLE_RAG_WEB_SEARCH" = "True";
          "RAG_OPENAI_API_BASE_URL" = "https://openrouter.ai/api/v1";
          "RAG_OPENAI_API_KEY" = kubenix.lib.secretsFor "openrouter_api_key_openwebui";
          "RAG_WEB_SEARCH_ENGINE" = "searxng";
          "RAG_WEB_SEARCH_RESULT_COUNT" = "3";
          "RAG_WEB_SEARCH_CONCURRENT_REQUESTS" = "10";
          "RAG_EMBEDDING_MODEL" = "sentence-transformers/all-MiniLM-L6-v2";
          "WHISPER_MODEL" = "Systran/faster-whisper-tiny";
          "WHISPER_MODEL_DIR" = "/app/backend/data/cache/whisper/models";
          "SEARXNG_QUERY_URL" = "http://searxng.apps.svc.cluster.local/search?q=<query>";
          "ENABLE_WEB_SEARCH" = "True";
          "WEB_SEARCH_ENGINE" = "searxng";
          "PDF_EXTRACT_IMAGES" = "True";
        };
      };
    };
  };
}
