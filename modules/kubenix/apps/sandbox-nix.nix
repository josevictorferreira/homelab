{ kubenix, homelab, ... }:

let
  name = "sandbox-nix";
  namespace = homelab.kubernetes.namespaces.applications;
  image = "ghcr.io/josevictorferreira/sandbox-nix:0.1.1@sha256:451fc43fc788be37b6d01e7205f97ed2b2c90ab8b69b986ef240934adfd42b76";

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

  # sshd does NOT export the container environment into SSH sessions, so the
  # GITHUB_TOKEN/GH_TOKEN from ${name}-env are invisible to agents arriving over
  # ssh even though they are set on PID 1.  Bridge them through /etc/profile,
  # which the login shells hermes runs (`bash -l`) source; the image ships no
  # /etc/profile of its own.  Written to the container layer (not the CephFS
  # volume) so the token never lands on shared storage.
  #
  # /etc/gitconfig teaches git to authenticate with that token over HTTPS.  The
  # helper expands $GITHUB_TOKEN at call time, so the value is not stored in the
  # config file itself.  Kept in the system-level config so the agent's own
  # ~/.gitconfig (commit identity) stays independent of it.
  entrypointWrapper = ''
    set -e
    umask 022
    {
      printf 'export GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN"
      printf 'export GH_TOKEN=%s\n' "$GH_TOKEN"
    } > /etc/profile
    chmod 444 /etc/profile
    {
      printf '[credential "https://github.com"]\n'
      printf '\thelper = "!f() { echo username=x-access-token; echo password=$GITHUB_TOKEN; }; f"\n'
    } > /etc/gitconfig
    chmod 444 /etc/gitconfig
    exec /entrypoint.sh
  '';
in
{
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
                # The marker records WHICH image seeded the store, not merely that
                # seeding happened.  The PVC is mounted over /nix and hides the
                # image's own store, so after an image bump the entrypoint's
                # interpreter (a /nix/store/...-bash path) is absent from the
                # stale PVC and the container dies with "bad interpreter".
                # Re-seed whenever the image reference changes.
                ''
                  want='${image}'
                  if [ "$(cat /mnt/nix/.seeded 2>/dev/null)" != "$want" ]; then
                    rm -rf /mnt/nix/* /mnt/nix/.[!.]* 2>/dev/null || true
                    cp -a /nix/. /mnt/nix/ && printf '%s' "$want" > /mnt/nix/.seeded
                  fi
                ''
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
              command = [
                "/bin/sh"
                "-c"
                entrypointWrapper
              ];
              envFrom = [ { secretRef.name = "${name}-env"; } ];
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
              # Without this the pod reports 1/1 Running while sshd is not
              # listening, so a startup stall looks healthy and the Service
              # keeps routing to a socket that refuses connections.
              readinessProbe = {
                tcpSocket.port = 22;
                initialDelaySeconds = 5;
                periodSeconds = 10;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
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
                defaultMode = 292;
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
