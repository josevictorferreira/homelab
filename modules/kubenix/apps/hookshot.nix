{ kubenix, homelab, ... }:

let
  app = "hookshot";
  dataPvcName = "${app}-data";
  namespace = homelab.kubernetes.namespaces.applications;
  domain = kubenix.lib.domainFor app;
in
{
  kubernetes.resources = {
    persistentVolumeClaims.${dataPvcName} = {
      metadata = {
        name = dataPvcName;
        inherit namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = kubenix.lib.defaultStorageClass;
        resources.requests.storage = "2Gi";
      };
    };

    services.${app} = {
      metadata = {
        inherit namespace;
        name = app;
      };
      spec = {
        type = "ClusterIP";
        selector.app = app;
        ports = [
          {
            name = "webhook";
            port = 9000;
            targetPort = "webhook";
          }
          {
            name = "metrics";
            port = 9001;
            targetPort = "metrics";
          }
          {
            name = "appservice";
            port = 9993;
            targetPort = "appservice";
          }
        ];
      };
    };

    deployments.${app} = {
      metadata = {
        inherit namespace;
        name = app;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = app;
        template = {
          metadata.labels.app = app;
          spec = {
            initContainers = [
              {
                name = "copy-config";
                image = "busybox:1.37";
                command = [
                  "sh"
                  "-c"
                  ''
                    set -eu

                    mkdir -p /data/config /data/passkey
                    cp /config-src/config.yml /data/config/config.yml
                    cp /config-src/github-private-key.pem /data/config/github-private-key.pem
                    cp /registration-src/registration.yml /data/config/registration.yml
                    cp /passkey-src/passkey.pem /data/passkey/passkey.pem
                    chmod 644 /data/config/config.yml /data/config/registration.yml
                    chmod 600 /data/config/github-private-key.pem /data/passkey/passkey.pem
                  ''
                ];
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                  {
                    name = "config";
                    mountPath = "/config-src";
                    readOnly = true;
                  }
                  {
                    name = "registration";
                    mountPath = "/registration-src";
                    readOnly = true;
                  }
                  {
                    name = "passkey";
                    mountPath = "/passkey-src";
                    readOnly = true;
                  }
                ];
              }
            ];
            containers = [
              {
                name = app;
                image = "docker.io/halfshot/matrix-hookshot:7.3.2@sha256:1c5cefb5d7d8842fd6ec8b63b3753722aaff76ba9106e8649a73d377117f5c32";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "node"
                  "/bin/matrix-hookshot/App/BridgeApp.js"
                  "/data/config/config.yml"
                  "/data/config/registration.yml"
                ];
                ports = [
                  {
                    name = "webhook";
                    containerPort = 9000;
                    protocol = "TCP";
                  }
                  {
                    name = "metrics";
                    containerPort = 9001;
                    protocol = "TCP";
                  }
                  {
                    name = "appservice";
                    containerPort = 9993;
                    protocol = "TCP";
                  }
                ];
                startupProbe = {
                  tcpSocket.port = "appservice";
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  failureThreshold = 30;
                  timeoutSeconds = 5;
                };
                readinessProbe = {
                  tcpSocket.port = "appservice";
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  failureThreshold = 6;
                  timeoutSeconds = 5;
                };
                livenessProbe = {
                  tcpSocket.port = "appservice";
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  failureThreshold = 5;
                  timeoutSeconds = 5;
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "data";
                persistentVolumeClaim.claimName = dataPvcName;
              }
              {
                name = "config";
                secret.secretName = "hookshot-config";
              }
              {
                name = "registration";
                secret.secretName = "hookshot-registration";
              }
              {
                name = "passkey";
                secret.secretName = "hookshot-passkey";
              }
            ];
          };
        };
      };
    };

    ingresses."${app}-webhook" = {
      metadata = {
        name = "${app}-webhook";
        inherit namespace;
        annotations."cert-manager.io/cluster-issuer" = kubenix.lib.defaultClusterIssuer;
      };
      spec = {
        ingressClassName = kubenix.lib.defaultIngressClass;
        rules = [
          {
            host = domain;
            http.paths = [
              {
                path = "/github/webhook";
                pathType = "Prefix";
                backend.service = {
                  name = app;
                  port.name = "webhook";
                };
              }
              {
                path = "/oauth";
                pathType = "Prefix";
                backend.service = {
                  name = app;
                  port.name = "webhook";
                };
              }
            ];
          }
        ];
        tls = [
          {
            hosts = [ domain ];
            secretName = kubenix.lib.defaultTLSSecret;
          }
        ];
      };
    };
  };
}
