{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "qui";
  # Use the same PVC that qBittorrent uses for downloads
  # This is required for Local Filesystem Access features (orphan scan, hardlinks, reflinks, automations)
  downloadsPvcName = "cephfs-shared-storage-downloads";
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/autobrr/qui";
        tag = "v1.13.1@sha256:05b9badae10d21f54722464e8b51abc9487ba93f9bb2fff649fbc09944d0d111";
        pullPolicy = "IfNotPresent";
      };
      port = 7476;

      # Mount the same downloads path as qBittorrent for Local Filesystem Access
      # IMPORTANT: Path must match exactly what qBittorrent uses (/downloads)
      values = {
        persistence.downloads = {
          enabled = true;
          type = "persistentVolumeClaim";
          existingClaim = downloadsPvcName;
          globalMounts = [
            {
              path = "/downloads";
              readOnly = false;
            }
          ];
        };
      };
    };
  };
}
