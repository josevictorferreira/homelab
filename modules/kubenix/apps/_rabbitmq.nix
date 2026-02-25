{ kubenix, homelab, ... }:

let
  app = "rabbitmq";
  namespace = homelab.kubernetes.namespaces.applications;
  image = {
    registry = "docker.io";
    repository = "bitnamilegacy/rabbitmq";
    tag = "4.1.3-debian-12-r1@sha256:a0745813602734f83fbdeba53dc0243a667f55fb7cded5b61f9192735b1dac1b";
  };
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        repo = "https://charts.bitnami.com/bitnami";
        chart = "rabbitmq";
        version = "16.0.14";
        sha256 = "sha256-fL0CmBadbyCRzRZs/GnjVFDQ8UaXdJewzl9RPLk8rxE=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        inherit image;

        global.security.allowInsecureImages = true;

        extraContainerPorts = [
          {
            name = "mqtt";
            protocol = "TCP";
            containerPort = 1883;
          }
          {
            name = "mqtts";
            protocol = "TCP";
            containerPort = 8883;
          }
        ];

        service = {
          type = "LoadBalancer";
          annotations = kubenix.lib.serviceAnnotationFor app;
          extraPorts = [
            {
              name = "mqtt";
              port = 1883;
              targetPort = 1883;
            }
            {
              name = "mqtts";
              port = 8883;
              targetPort = 8883;
            }
          ];
          extraPortsHeadless = [
            {
              name = "mqtt";
              port = 1883;
              targetPort = 1883;
            }
            {
              name = "mqtts";
              port = 8883;
              targetPort = 8883;
            }
          ];
        };

        networkPolicy.extraIngress = [
          {
            ports = [
              {
                protocol = "TCP";
                port = 1883;
              }
              {
                protocol = "TCP";
                port = 8883;
              }
            ];
          }
        ];

        persistence = {
          enabled = true;
          storageClass = "rook-ceph-block";
        };

        usePasswordFiles = true;

        auth = {
          existingPasswordSecret = "rabbitmq-auth";
          existingPasswordKey = "rabbitmq-password";
          existingErlangSecret = "rabbitmq-auth";
          existingErlangKey = "rabbitmq-erlang-cookie";
          updatePassword = true;
          username = "josevictor";
        };

        extraPlugins = "rabbitmq_management rabbitmq_auth_backend_ldap rabbitmq_prometheus rabbitmq_delayed_message_exchange rabbitmq_mqtt rabbitmq_web_mqtt";

        ingress = {
          enabled = true;
          annotations = {
            "cert-manager.io/cluster-issuer" = "cloudflare-issuer";
          };
          ingressClassName = "cilium";
          hostname = kubenix.lib.domainFor app;
          existingSecret = "wildcard-tls";
          tls = true;
        };

        metrics = {
          enabled = true;
          serviceMonitor = {
            inherit namespace;
            default.enabled = true;
          };
        };
      };
    };
  };
}
