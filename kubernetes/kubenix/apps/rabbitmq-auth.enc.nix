{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."rabbitmq-auth" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "RABBITMQ_PASSWORD" = kubenix.lib.secretsFor "rabbitmq_password";
          "RABBITMQ_ERLANG_COOKIE" = kubenix.lib.secretsFor "rabbitmq_erlang_cookie";
        };
      };
    };
  };
}
