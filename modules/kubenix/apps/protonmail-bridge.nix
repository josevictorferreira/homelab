{ kubenix, homelab, ... }:

let
  app = "protonmail-bridge";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      persistentVolumeClaims.${app} = {
        metadata = { inherit namespace; };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          storageClassName = "rook-ceph-block";
          resources.requests.storage = "1Gi";
        };
      };

      services.${app} = {
        metadata = { inherit namespace; };
        spec = {
          selector = { inherit app; };
          ports = [
            {
              name = "smtp";
              port = 25;
              targetPort = 25;
            }
            {
              name = "imap";
              port = 143;
              targetPort = 143;
            }
          ];
        };
      };

      statefulSets.${app} = {
        metadata = { inherit namespace; };
        spec = {
          replicas = 1;
          serviceName = app;
          selector.matchLabels = { inherit app; };
          template = {
            metadata.labels = { inherit app; };
            spec = {
              initContainers = [
                {
                  name = "init-pass";
                  image = "shenxn/protonmail-bridge:build";
                  command = [
                    "sh"
                    "-c"
                  ];
                  args = [
                    ''
                      set -e
                      export GNUPGHOME=/root/.gnupg
                      export PASSWORD_STORE_DIR=/root/.password-store

                      # Check if pass is already initialized
                      if [ -d "$PASSWORD_STORE_DIR/.gpg-id" ] || [ -f "$PASSWORD_STORE_DIR/.gpg-id" ]; then
                        echo "pass already initialized, skipping"
                        exit 0
                      fi

                      echo "Initializing GPG and pass..."

                      # Create GPG home if not exists
                      mkdir -p "$GNUPGHOME"
                      chmod 700 "$GNUPGHOME"

                      # Generate GPG key batch
                      cat > /tmp/gpg-gen.conf <<EOF
                      %echo Generating Bridge key
                      Key-Type: RSA
                      Key-Length: 2048
                      Name-Real: Bridge
                      Name-Email: bridge@localhost
                      Expire-Date: 0
                      %no-protection
                      %commit
                      %echo done
                      EOF

                      gpg --batch --gen-key /tmp/gpg-gen.conf

                      # Initialize pass with the Bridge key
                      pass init "Bridge"

                      echo "pass initialization complete"
                    ''
                  ];
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/root";
                    }
                  ];
                }
              ];
              containers = [
                {
                  name = app;
                  image = "shenxn/protonmail-bridge:build";
                  ports = [
                    {
                      name = "smtp";
                      containerPort = 25;
                    }
                    {
                      name = "imap";
                      containerPort = 143;
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/root";
                    }
                  ];
                  resources = {
                    requests = {
                      memory = "256Mi";
                      cpu = "100m";
                    };
                    limits = {
                      memory = "512Mi";
                      cpu = "500m";
                    };
                  };
                  readinessProbe = {
                    tcpSocket.port = 143;
                    initialDelaySeconds = 10;
                    periodSeconds = 10;
                  };
                }
              ];
              volumes = [
                {
                  name = "data";
                  persistentVolumeClaim.claimName = app;
                }
              ];
            };
          };
        };
      };
    };
  };
}
