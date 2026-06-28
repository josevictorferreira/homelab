{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "omniroute";
in
{
  kubernetes.resources.secrets."${app}-env" = {
    metadata.namespace = namespace;
    stringData = {
      JWT_SECRET = kubenix.lib.secretsFor "omniroute_jwt_secret";
      INITIAL_PASSWORD = kubenix.lib.secretsFor "omniroute_initial_password";
      API_KEY_SECRET = kubenix.lib.secretsFor "omniroute_api_key_secret";
      MACHINE_ID_SALT = kubenix.lib.secretsFor "omniroute_machine_id_salt";
      OMNIROUTE_WS_BRIDGE_SECRET = kubenix.lib.secretsFor "omniroute_ws_bridge_secret";
      REDIS_URL = "redis://:${kubenix.lib.secretsFor "redis_password"}+@redis-master:6379";
      PORT = "20128";
      NODE_ENV = "production";
      HOSTNAME = "0.0.0.0";
      NEXT_TELEMETRY_DISABLED = "1";
      BASE_URL = "https://omniroute.josevictor.me";
      NEXT_PUBLIC_BASE_URL = "https://omniroute.josevictor.me";
      ENABLE_REQUEST_LOGS = "false";
      OBSERVABILITY_ENABLED = "true";
      AUTH_COOKIE_SECURE = "true";
      REQUIRE_API_KEY = "false";
      OMNIROUTE_MEMORY_MB = "3072";
      NODE_OPTIONS = "--max-old-space-size=3072";
    };
  };
}
