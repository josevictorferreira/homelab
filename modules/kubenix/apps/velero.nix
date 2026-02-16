{ kubenix, homelab, ... }:

let
  namespace = "velero";
in
{
  kubernetes.namespaces.${namespace} = { };

  kubernetes.helm.releases.velero = {
    chart = kubenix.lib.helm.fetch {
      repo = "https://vmware-tanzu.github.io/helm-charts";
      chart = "velero";
      version = "11.3.2";
      sha256 = "0qycxy93p8d3m2fq6f10zyaqlnkvh31dka6ag9z0nwncdz33v3mk";
    };
    namespace = namespace;
    includeCRDs = true;

    values = {
      configuration = {
        backupStorageLocation = [
          {
            name = "default";
            bucket = "homelab-backup-velero";
            config = {
              region = "minio";
              s3ForcePathStyle = true;
              s3Url = "http://10.10.10.209:9000";
            };
            provider = "aws";
          }
        ];
        volumeSnapshotLocation = [
          {
            name = "default";
            provider = "aws";
          }
        ];
      };

      # Use FSB (file system backup) via Kopia
      deployNodeAgent = true;

      credentials = {
        useSecret = true;
        existingSecret = "velero-s3-credentials";
      };

      initContainers = [
        {
          name = "velero-plugin-for-aws";
          image = "velero/velero-plugin-for-aws:v1.10.0";
          volumeMounts = [
            {
              mountPath = "/target";
              name = "plugins";
            }
          ];
        }
      ];

      schedules = {
        daily-backup = {
          disabled = false;
          schedule = "0 3 * * *";
          template = {
            ttl = "336h"; # 14 days
            includedNamespaces = [ "*" ];
            snapshotVolumes = false; # Use FSB instead of VolumeSnapshots
            defaultVolumesToFsBackup = false; # Opt-in via annotation
          };
        };
      };
    };
  };
}
