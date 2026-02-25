{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{

  kubernetes = {
    resources = {
      secrets."docling-config" = {
        metadata = {
          inherit namespace;
        };
        type = "Opaque";
        stringData = {
          DOCLING_SERVE_UNABLE_UI = "true";
          UVICORN_TIMEOUT_KEEP_ALIVE = "180";
          DOCLING_SERVE_MAX_SYNC_WAIT = "180";
          DOCLING_SERVE_ENG_RQ_REDIS_URL = "redis://:${kubenix.lib.secretsFor "redis_password"}+@redis-headless:6379/4";
        };
      };
    };
  };
}
