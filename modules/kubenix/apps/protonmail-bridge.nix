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
                      apt-get install -y libfido2-1 socat libglx0 libgl1 libglib2.0-0 libopengl0 libegl1 libgssapi-krb5-2 libxkbcommon0 libxkbcommon-x11-0 libfontconfig1 libfreetype6 libdbus-1-3

                      # Update library cache
                      ldconfig

                      echo "Starting ProtonMail Bridge..."


                      export QT_QPA_PLATFORM=offscreen

                      # Set QT to use offscreen platform for headless GUI
                      export QT_QPA_PLATFORM=offscreen

                      # Start bridge in background
                      /protonmail/proton-bridge --noninteractive &
                      BRIDGE_PID=$!

                      # Wait for bridge to start listening
                      sleep 5

                      echo "Bridge started on PID $BRIDGE_PID"
                      echo "Setting up port forwarding..."

                      # Forward external 0.0.0.0:143 -> 127.0.0.1:1143
                      socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &

                      # Forward external 0.0.0.0:25 -> 127.0.0.1:1025
                      socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &

                      echo "Port forwarding active: 143->1143, 25->1025"
                      echo "Bridge is ready for connections"

                      # Wait for bridge process
                      wait $BRIDGE_PID
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
