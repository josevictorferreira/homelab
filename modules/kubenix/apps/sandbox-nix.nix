{ kubenix, homelab, ... }:

let
  name = "sandbox-nix";
  namespace = homelab.kubernetes.namespaces.applications;
  image = "ghcr.io/josevictorferreira/sandbox-nix:0.1.0@sha256:71ee80899882236104ebdfbe4aadcf7d047c69941e522acdbbf2190880b4dd1b";

  # CephFS-backed workspace where project repos and task workspaces live, so
  # state (checkouts, generated files) persists across sessions.
  workspaceVolumeMounts = [
    {
      name = "workspace";
      mountPath = "/workspace";
    }
  ];
  workspaceVolumes = [
    {
      name = "workspace";
      persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;
    }
  ];
in
{
  kubernetes.resources.secrets."${name}-ssh" = {
    metadata.namespace = namespace;
    stringData = {
      # Public key is mounted as authorized_keys so the private key owner
      # (hermes agents) can authenticate.
      "authorized_keys" = kubenix.lib.secretsFor "sandbox_nix_ssh_public_key";
    };
  };

  kubernetes.resources.statefulSets.${name} = {
    metadata = {
      inherit namespace;
      name = name;
      labels = {
        app = name;
      };
    };
    spec = {
      serviceName = "${name}";
      replicas = 1;
      selector.matchLabels = {
        app = name;
      };
      template = {
        metadata.labels = {
          app = name;
        };
        spec = {
          securityContext = {
            runAsNonRoot = false;
            runAsUser = 0;
            runAsGroup = 0;
          };
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
          initContainers = [
            {
              # Seed the persistent /nix PVC from the image's baked store on
              # first boot. The PVC is staged at /mnt/nix here (NOT /nix) so the
              # image's own /nix store stays visible for the copy; the main
              # container then mounts the populated PVC at /nix.
              name = "seed-nix-store";
              inherit image;
              imagePullPolicy = "IfNotPresent";
              command = [
                "/bin/sh"
                "-c"
                "if [ ! -f /mnt/nix/.seeded ]; then rm -rf /mnt/nix/* /mnt/nix/.[!.]* 2>/dev/null || true; cp -a /nix/. /mnt/nix/ && touch /mnt/nix/.seeded; fi"
              ];
              volumeMounts = [
                {
                  name = "nix-store";
                  mountPath = "/mnt/nix";
                }
              ];
            }
          ];
          containers = [
            {
              name = name;
              inherit image;
              imagePullPolicy = "IfNotPresent";
              command = [ "/entrypoint.sh" ];
              env = [
                {
                  name = "NIX_CONFIG";
                  value = "experimental-features = nix-command flakes\nsandbox = false";
                }
              ];
              ports = [
                {
                  name = "ssh";
                  containerPort = 22;
                  protocol = "TCP";
                }
              ];
              volumeMounts = workspaceVolumeMounts ++ [
                {
                  name = "nix-store";
                  mountPath = "/nix";
                }
                {
                  name = "ssh-authorized-keys";
                  mountPath = "/etc/ssh/authorized_keys";
                  subPath = "authorized_keys";
                  readOnly = true;
                }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "1Gi";
                };
                limits = {
                  cpu = "2000m";
                  memory = "4Gi";
                };
              };
            }
          ];
          volumes = workspaceVolumes ++ [
            {
              name = "ssh-authorized-keys";
              secret = {
                secretName = "${name}-ssh";
                defaultMode = 384;
              };
            }
          ];
        };
      };
      volumeClaimTemplates = [
        {
          metadata = {
            name = "nix-store";
            labels = {
              app = name;
            };
          };
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            storageClassName = "rook-ceph-block";
            resources.requests.storage = "100Gi";
          };
        }
      ];
    };
  };

  kubernetes.resources.services.${name} = {
    metadata = {
      inherit namespace;
      name = name;
      labels = {
        app = name;
      };
      annotations = kubenix.lib.serviceAnnotationFor name;
    };
    spec = {
      type = "LoadBalancer";
      selector = {
        app = name;
      };
      ports = [
        {
          name = "ssh";
          port = 22;
          targetPort = 22;
          protocol = "TCP";
        }
      ];
    };
  };
}
