{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."rabbitmq-auth" = {
        metadata = {
          inherit namespace;
        };
        stringData = {
          "rabbitmq-password" = kubenix.lib.secretsFor "rabbitmq_password";
          "rabbitmq-erlang-cookie" = kubenix.lib.secretsFor "rabbitmq_erlang_cookie";
        };
      };
    };
  };
}
