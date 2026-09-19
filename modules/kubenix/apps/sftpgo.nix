{ kubenix, homelab, ... }:

let
  app = "sftpgo";
  namespace = homelab.kubernetes.namespaces.applications;
  pvcName = kubenix.lib.sharedStorage.rootPVC;

  relayPort = 9000;
  eventRulesPath = "/etc/sftpgo/eventrules";

  # The sidecar reads its script and the event rules from config maps defined in
  # sftpgo-matrix-relay.nix; hashing them here rolls the pod when either changes,
  # since both are mounted with subPath-free config map volumes.
  relayConfigMaps = (import ./sftpgo-matrix-relay.nix { inherit homelab; }).kubernetes.resources.configMaps;
  relayConfigHash = builtins.hashString "sha256" (builtins.toJSON relayConfigMaps);
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://ghcr.io/sftpgo/helm-charts/sftpgo";
        chart = "sftpgo";
        version = "0.47.0";
        sha256 = "sha256-lfPoY0tniuxL3vw+PFYS3KwR8MGDmZZUIZGqobnSA8s=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;

      values = {
        image = {
          repository = "ghcr.io/drakkan/sftpgo";
          tag = "v2.7.4";
          pullPolicy = "IfNotPresent";
        };

        envFrom = [
          {
            secretRef = {
              name = "sftpgo-config";
            };
          }
        ];

        # Event actions and rules live in git and are re-applied on every start.
        # Mode 0 updates the objects named in the dump and leaves everything else
        # (users, folders, admins) untouched.
        env = {
          SFTPGO_LOADDATA_FROM = "${eventRulesPath}/loaddata.json";
          SFTPGO_LOADDATA_MODE = "0";
        };

        # /var/lib/sftpgo is a ReadWriteOnce RBD volume, so the old pod has to
        # release it before the new one starts or the rollout deadlocks on
        # Multi-Attach. Recreate would express this too, but it cannot be applied
        # over the chart's default rollingUpdate block without a manual patch.
        deploymentStrategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };

        podAnnotations = {
          "homelab.io/relay-config-hash" = relayConfigHash;
        };

        securityContext = {
          runAsUser = 2002;
          runAsGroup = 2002;
          readOnlyRootFilesystem = false;
        };

        # fsGroup must be 100 (users) to match the shared CephFS volume root,
        # which is uid 10000 / gid 100. With OnRootMismatch, a differing fsGroup
        # (e.g. 2002) makes kubelet recursively chown every inode on the whole
        # shared volume on each mount; that exceeds kubelet's 2min mount timeout,
        # retries forever, wedges the node's volume manager and saturates the MDS.
        # The process still reaches gid 2002 paths via runAsGroup above.
        podSecurityContext = {
          fsGroup = 100;
          fsGroupChangePolicy = "OnRootMismatch";
        };

        config = {
          sftpd = {
            max_auth_tries = 4;
            bindings = [
              { port = 22; }
            ];
          };
          ftpd = {
            bindings = [
              {
                port = 21;
                tls_mode = 0;
                debug = true;
                active_connections_security = 1;
                passive_connections_security = 1;
                force_passive_ip = homelab.kubernetes.loadBalancer.services.sftpgo;
              }
            ];
            passive_port_range = {
              start = 50000;
              end = 50009;
            };
          };
        };

        sftpd.enabled = true;
        ftpd.enabled = true;
        webdavd.enabled = true;
        httpd.enabled = true;

        hostNetwork = false;

        service = {
          type = "LoadBalancer";
          externalTrafficPolicy = "Cluster";
          annotations = kubenix.lib.serviceAnnotationFor "sftpgo";
          ports.ftp.passiveRange.start = 50000;
          ports.ftp.passiveRange.end = 50009;
        };

        persistence = {
          enabled = true;
          pvc = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "1Gi";
            storageClassName = kubenix.lib.defaultStorageClass;
          };
        };

        volumes = [
          {
            name = "shared-storage";
            persistentVolumeClaim = {
              claimName = pvcName;
            };
          }
          {
            name = "event-rules";
            configMap.name = "sftpgo-event-rules";
          }
          {
            name = "matrix-relay";
            configMap.name = "sftpgo-matrix-relay";
          }
        ];

        volumeMounts = [
          {
            name = "shared-storage";
            mountPath = "/mnt/shared_storage";
            readOnly = false;
          }
          {
            name = "event-rules";
            mountPath = eventRulesPath;
            readOnly = true;
          }
        ];

        # Turns SFTPGo upload events into Matrix messages; see
        # sftpgo-matrix-relay.nix for why this cannot be a plain HTTP action.
        extraContainers = [
          {
            name = "matrix-relay";
            image = "python:3.13-alpine";
            imagePullPolicy = "IfNotPresent";
            command = [
              "python3"
              "/opt/relay/relay.py"
            ];
            env = [
              {
                name = "MATRIX_HOMESERVER";
                value = "http://tuwunel.apps.svc.cluster.local:8008";
              }
              {
                name = "MATRIX_ROOM_ID";
                value = "!adz2tOeDu1eB6CeUlG:josevictor.me"; # #cctv:josevictor.me
              }
              {
                name = "RELAY_PORT";
                value = toString relayPort;
              }
              {
                name = "MATRIX_ACCESS_TOKEN";
                valueFrom.secretKeyRef = {
                  name = "sftpgo-matrix-relay";
                  key = "MATRIX_ACCESS_TOKEN";
                };
              }
            ];
            volumeMounts = [
              {
                name = "matrix-relay";
                mountPath = "/opt/relay";
                readOnly = true;
              }
              {
                name = "shared-storage";
                mountPath = "/mnt/shared_storage";
                readOnly = true;
              }
            ];
            securityContext = {
              runAsUser = 2002;
              runAsGroup = 2002;
              allowPrivilegeEscalation = false;
              readOnlyRootFilesystem = true;
              capabilities.drop = [ "ALL" ];
            };
            resources = {
              requests = {
                cpu = "50m";
                memory = "64Mi";
              };
              limits = {
                cpu = "200m";
                memory = "128Mi";
              };
            };
          }
        ];

        ui.ingress = {
          enabled = true;
          className = kubenix.lib.defaultIngressClass;
          annotations = { };
          tls = [
            {
              secretName = kubenix.lib.defaultTLSSecret;
              hosts = [ "sftpgo.${homelab.domain}" ];
            }
          ];
          hosts = [
            {
              host = "sftpgo.${homelab.domain}";
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
        };

        api.ingress = {
          enabled = true;
          className = kubenix.lib.defaultIngressClass;
          annotations = { };
          tls = [
            {
              secretName = kubenix.lib.defaultTLSSecret;
              hosts = [ "sftpgoapi.${homelab.domain}" ];
            }
          ];
          hosts = [
            {
              host = "sftpgoapi.${homelab.domain}";
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
        };
      };
    };
  };
}
