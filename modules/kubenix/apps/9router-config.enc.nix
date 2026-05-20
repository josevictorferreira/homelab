{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "9router";
in
{
  kubernetes.resources.secrets."${app}-env" = {
    metadata.namespace = namespace;
    stringData = {
      JWT_SECRET = kubenix.lib.secretsFor "9router_jwt_secret";
      INITIAL_PASSWORD = kubenix.lib.secretsFor "9router_initial_password";
      API_KEY_SECRET = kubenix.lib.secretsFor "9router_api_key_secret";
      MACHINE_ID_SALT = kubenix.lib.secretsFor "9router_machine_id_salt";
      DATA_DIR = "/app/data";
      PORT = "20128";
      NODE_ENV = "production";
      HOSTNAME = "0.0.0.0";
      NEXT_TELEMETRY_DISABLED = "1";
      BASE_URL = "http://localhost:20128";
      NEXT_PUBLIC_BASE_URL = "http://localhost:20128";
      CLOUD_URL = "https://9router.com";
      NEXT_PUBLIC_CLOUD_URL = "https://9router.com";
      ENABLE_REQUEST_LOGS = "false";
      OBSERVABILITY_ENABLED = "true";
      AUTH_COOKIE_SECURE = "false";
      REQUIRE_API_KEY = "false";
    };
  };
}
