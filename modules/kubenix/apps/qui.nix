{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "qui";
  # Use the same PVC that qBittorrent uses for downloads
  # This is required for Local Filesystem Access features (orphan scan, hardlinks, reflinks, automations)
  downloadsPvcName = kubenix.lib.sharedStorage.downloadsPVC;
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        repository = "ghcr.io/autobrr/qui";
        tag = "v1.15.0@sha256:5d9afcb8fead8607e2b63ad7cb4bf6001fa2864fb36f499ae5c4f9a863a784b9";
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
