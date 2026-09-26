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
              OPENJEV_SERVICE_URL.value = "http://10.10.10.10:8102";
              OPENJEV_SERVICE_ENABLED.value = "true";
              # Nota de Valor v2 (valoris spec 0089). Falls back to local
              # comparables when the service is down or has no estimate.
              VALUATION_SERVICE_URL.value = "http://valoris-valuation.${namespace}.svc.cluster.local:8000";
              VALUATION_SERVICE_ENABLED.value = "true";
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
        resources = {
          # 1Gi was OOMKilling the worker mid-scrape; steady state is ~840Mi and
          # parsing a large listing page spikes well past that.
          limits = {
            memory = "1536Mi";
          };
          # Peaks near the limit while scraping; the 2.5Gi Pi evicts anything
          # far above its request, so keep this close to real usage.
          requests = {
            memory = "768Mi";
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
              # One scraping job at a time. The default of 3 pushed peak memory
              # to ~925Mi and got the pod evicted off the Pi, failing in-flight jobs.
              JOB_THREADS.value = "1";
              OPENJEV_SERVICE_URL.value = "http://10.10.10.10:8102";
              OPENJEV_SERVICE_ENABLED.value = "true";
              # Nota de Valor v2 (valoris spec 0089). Falls back to local
              # comparables when the service is down or has no estimate.
              VALUATION_SERVICE_URL.value = "http://valoris-valuation.${namespace}.svc.cluster.local:8000";
              VALUATION_SERVICE_ENABLED.value = "true";
            };
          };
        };
      };
    };
    # Hedonic price model for the Nota de Valor (valoris spec 0089). Trains
    # on startup (~20 s) and nightly via Catalog::Jobs::TriggerValuationTrainingJob;
    # the model lives on the container filesystem, so a restart retrains.
    valoris-valuation = {
      submodule = "release";
      args = {
        inherit namespace;
        image = {
          repository = "ghcr.io/josevictorferreira/valoris-valuation";
          tag = imageTag;
          pullPolicy = "Always";
        };
        port = 8000;
        resources = {
          limits = {
            memory = "1Gi";
          };
          requests = {
            memory = "384Mi";
          };
        };
        priorityClassName = "preemptible";
        values = {
          defaultPodOptions = {
            imagePullSecrets = [
              { name = "ghcr-registry-secret"; }
            ];
          };
          controllers.main.containers.main = {
            # VALORIS_DATABASE_HOST / _PASSWORD, shared with the backend.
            envFrom = [
              { secretRef.name = secretName; }
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
