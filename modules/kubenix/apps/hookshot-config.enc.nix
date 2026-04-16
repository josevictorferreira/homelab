{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  appserviceUrl = "http://${kubenix.lib.serviceHostFor "hookshot" namespace}:9993";
  webhookUrl = "https://${kubenix.lib.domainFor "hookshot"}";

in
{
  kubernetes = {
    resources = {
      secrets = {
        "hookshot-config" = {
          metadata = { inherit namespace; };
          stringData = {
            "github-private-key.pem" = kubenix.lib.secretsFor "hookshot_github_private_key";
            "config.yml" = kubenix.lib.toYamlStr {
              bridge = {
                domain = "josevictor.me";
                url = "http://tuwunel.apps.svc.cluster.local:8008";
                port = 9993;
                bindAddress = "0.0.0.0";
              };
              passFile = "/data/passkey/passkey.pem";
              webhook = "/github/webhook";
              callback = "${webhookUrl}/oauth";
              listeners = [
                {
                  port = 9000;
                  bindAddress = "0.0.0.0";
                  resources = [ "webhooks" ];
                }
                {
                  port = 9001;
                  bindAddress = "0.0.0.0";
                  resources = [
                    "metrics"
                    "provisioning"
                  ];
                }
              ];
              permissions = [
                {
                  actor = "josevictor.me";
                  services = [
                    {
                      service = "*";
                      level = "admin";
                    }
                  ];
                }
              ];
              github = {
                auth = {
                  id = kubenix.lib.secretsInlineFor "hookshot_github_auth_id";
                  privateKeyFile = "/data/config/github-private-key.pem";
                };
                webhook = {
                  secret = kubenix.lib.secretsInlineFor "hookshot_github_webhook_secret";
                };
                oauth = {
                  client_id = kubenix.lib.secretsInlineFor "hookshot_github_oauth_client_id";
                  client_secret = kubenix.lib.secretsInlineFor "hookshot_github_oauth_client_secret";
                  redirect_uri = "${webhookUrl}/oauth";
                };
                defaultOptions = {
                  enableHooks = "workflow.run.failure";
                };
              };
            };
          };
        };

        "hookshot-registration" = {
          metadata = { inherit namespace; };
          stringData = {
            "registration.yml" = kubenix.lib.toYamlStr {
              id = "hookshot";
              url = appserviceUrl;
              as_token = kubenix.lib.secretsInlineFor "hookshot_as_token";
              hs_token = kubenix.lib.secretsInlineFor "hookshot_hs_token";
              sender_localpart = "hookshotbot";
              namespaces = {
                users = [
                  {
                    exclusive = true;
                    regex = "@hookshotbot:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@_github_.*:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@_gitlab_.*:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@_jira_.*:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@_webhooks_.*:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@feeds:josevictor\\.me";
                  }
                ];
                rooms = [ ];
                aliases = [
                  {
                    exclusive = true;
                    regex = "#github_.+:josevictor\\.me";
                  }
                ];
              };
              rate_limited = false;
            };
          };
        };

        "hookshot-passkey" = {
          metadata = { inherit namespace; };
          stringData = {
            "passkey.pem" = kubenix.lib.secretsFor "hookshot_passkey";
          };
        };
      };
    };
  };
}
