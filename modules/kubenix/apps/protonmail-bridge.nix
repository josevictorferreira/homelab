{ homelab, ... }:

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
          resources.requests.storage = "10Gi";
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
                  stdin = true;
                  tty = true;
                  command = [
                    "sh"
                    "-c"
                    ''
                      set -e

                      # Install required libraries and socat for proxy
                      apt-get update
                      apt-get install -y libfido2-1 socat procps libglx0 libgl1 libglib2.0-0 libopengl0 libegl1 libgssapi-krb5-2 libxkbcommon0 libxkbcommon-x11-0 libfontconfig1 libfreetype6 libdbus-1-3

                      # Update library cache
                      ldconfig

                      export QT_QPA_PLATFORM=offscreen

                      LOCK_FILE="/root/.cache/protonmail/bridge-v3/bridge-v3.lock"

                      cleanup_lock() {
                        rm -f "$LOCK_FILE"
                        echo "Lock file cleaned up"
                      }

                      start_bridge() {
                        cleanup_lock
                        echo "Starting ProtonMail Bridge..."
                        /protonmail/proton-bridge --noninteractive &
                        BRIDGE_PID=$!
                        sleep 5
                        echo "Bridge started on PID $BRIDGE_PID"
                      }

                      start_socat() {
                        pkill -f "socat TCP-LISTEN" 2>/dev/null || true
                        sleep 1
                        echo "Setting up port forwarding..."
                        socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
                        socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &
                        echo "Port forwarding active: 143->1143, 25->1025"
                      }

                      start_bridge
                      start_socat

                      echo "Bridge is ready"
                      echo "---"
                      echo "To reauthenticate:"
                      echo "  1. kubectl exec -n apps protonmail-bridge-0 -- pkill -f proton-bridge"
                      echo "  2. kubectl exec -it -n apps protonmail-bridge-0 -- /protonmail/proton-bridge --cli"
                      echo "---"

                      # Keep container alive even if bridge dies (for reauth)
                      while true; do
                        wait $BRIDGE_PID 2>/dev/null || true
                        cleanup_lock
                        echo "Bridge process exited. Container staying alive for CLI access."
                        echo "Run: /protonmail/proton-bridge --cli"
                        echo "After reauth, restart the pod."
                        sleep infinity &
                        wait $!
                      done
                    ''
                  ];
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
