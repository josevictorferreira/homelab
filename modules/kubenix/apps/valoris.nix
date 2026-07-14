{ homelab, ... }:

let
  imageTag = "latest";
  namespace = homelab.kubernetes.namespaces.applications;
  bucketName = "valoris-s3";
  secretName = "valoris-config";
in
{
  submodules.instances = {
    valoris = {
      submodule = "release";
      args = {
        inherit namespace;
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-frontend";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 80;
        resources = {
          limits = {
            memory = "1Gi";
          };
          requests = {
            memory = "256Mi";
          };
        };
        priorityClassName = "preemptible";
        values = {
          defaultPodOptions = {
            affinity = homelab.kubernetes.affinities.piNode;
            tolerations = [
              {
                key = "pi-only";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              }
            ];
            imagePullSecrets = [
              { name = "ghcr-registry-secret"; }
            ];
          };
          controllers.main.containers.main = {
            envFrom = [
              { secretRef.name = secretName; }
              { secretRef.name = "valoris-s3"; }
            ];
            env = {
              KEYCLOAK_AUTHORITY.value = "https://identity.josevictor.me/realms/valoris";
              KEYCLOAK_CLIENT_ID.value = "valoris-frontend";
            };
          };
        };
      };
    };
    valoris-backend = {
      submodule = "release";
      args = {
        inherit namespace;
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-backend";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 80;
        command = [
          "bundle"
          "exec"
          "rails"
          "server"
          "-p"
          "80"
        ];
        resources = {
          limits = {
            memory = "512Mi";
          };
          requests = {
            memory = "256Mi";
          };
        };
        priorityClassName = "preemptible";
        values = {
          defaultPodOptions = {
            affinity = homelab.kubernetes.affinities.piNode;
            tolerations = [
              {
                key = "pi-only";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              }
            ];
            imagePullSecrets = [
              { name = "ghcr-registry-secret"; }
            ];
          };
          controllers.main.containers.main = {
            envFrom = [
              { secretRef.name = secretName; }
              { secretRef.name = "valoris-s3"; }
            ];
            env = {
              KEYCLOAK_ISSUER.value = "https://identity.josevictor.me/realms/valoris";
              KEYCLOAK_JWKS_URL.value = "http://keycloak.apps.svc.cluster.local:8080/realms/valoris/protocol/openid-connect/certs";
              KEYCLOAK_AZP.value = "valoris-frontend";
            };
          };
        };
      };
    };
    valoris-worker = {
      submodule = "release";
      args = {
        inherit namespace;
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-backend";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 3000;
        command = [
          "bundle"
          "exec"
          "bin/jobs"
          "start"
        ];
        priorityClassName = "preemptible";
        values = {
          defaultPodOptions = {
            affinity = homelab.kubernetes.affinities.piNode;
            tolerations = [
              {
                key = "pi-only";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              }
            ];
            imagePullSecrets = [
              { name = "ghcr-registry-secret"; }
            ];
          };
          controllers.main.containers.main = {
            envFrom = [
              { secretRef.name = secretName; }
              { secretRef.name = "valoris-s3"; }
            ];
          };
        };
      };
    };
  };

  kubernetes = {
    resources = {
      objectbucketclaim."valoris-s3" = {
        metadata = {
          inherit namespace;
        };
        spec = {
          inherit bucketName;
          storageClassName = "rook-ceph-objectstore";
        };
      };
    };
  };
}
