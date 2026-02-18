{
  kubenix,
  lib,
  pkgs,
  ...
}:

let
  name = "proton-drive-auth-bootstrap";
  namespace = "apps";
  # Reference the same PVCs as the CronJob
  protonSyncName = "shared-subfolders-proton-sync";
in
{
  kubernetes.resources.jobs.${name} = {
    metadata = { inherit name namespace; };
    spec = {
      ttlSecondsAfterFinished = 86400; # Clean up after 24 hours
      template.spec = {
        restartPolicy = "Never";
        volumes = [
          {
            name = "proton-config";
            persistentVolumeClaim.claimName = "${protonSyncName}-config";
          }
          {
            name = "proton-state";
            persistentVolumeClaim.claimName = "${protonSyncName}-state";
          }
        ];
        containers = [
          {
            inherit name;
            image = "ghcr.io/damianb-bitflipper/proton-drive-sync:0.2.3-beta.3";
            stdin = true;
            tty = true;
            env = [
              {
                name = "KEYRING_PASSWORD";
                valueFrom.secretKeyRef = {
                  name = "${protonSyncName}-config";
                  key = "KEYRING_PASSWORD";
                };
              }
            ];
            volumeMounts = [
              {
                name = "proton-config";
                mountPath = "/config/proton-drive-sync";
              }
              {
                name = "proton-state";
                mountPath = "/state/proton-drive-sync";
              }
            ];
            command = [
              "sh"
              "-c"
            ];
            args = [
              ''
                echo "=============================================="
                echo "Proton Drive Auth Bootstrap Job"
                echo "=============================================="
                echo ""
                echo "This job is waiting for interactive authentication."
                echo ""
                echo "To authenticate, run:"
                echo "  kubectl attach -it job/${name} -n ${namespace}"
                echo ""
                echo "Then follow the prompts to log in with your Proton account."
                echo ""
                echo "After successful authentication, credentials will be"
                echo "stored in /config/proton-drive-sync/credentials.enc"
                echo ""
                echo "=============================================="
                echo "Waiting for interactive session..."
                echo "=============================================="
                echo ""

                # Keep container running for interactive attach
                exec sleep infinity
              ''
            ];
            resources = {
              requests = {
                cpu = "50m";
                memory = "128Mi";
              };
              limits = {
                cpu = "200m";
                memory = "256Mi";
              };
            };
          }
        ];
      };
    };
  };
}
