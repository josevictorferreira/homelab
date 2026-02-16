{ kubenix, homelab, ... }:

let
  namespace = "velero";
in

{
  kubernetes.helm.releases.velero = {
    includeCRDs = false;
    chart = kubenix.lib.helm.fetch {
      repo = "https://vmware-tanzu.github.io/helm-charts";
      chart = "velero";
      version = "11.3.2";
      sha256 = "0qycxy93p8d3m2fq6f10zyaqlnkvh31dka6ag9z0nwncdz33v3mk";
    };
    namespace = namespace;
    values = {
      configuration = {
        backupStorageLocation = [ ];
        volumeSnapshotLocation = [ ];
      };

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
    };
  };

  kubernetes.objects = [
    {
      apiVersion = "velero.io/v1";
      kind = "BackupStorageLocation";
      metadata = {
        name = "default";
        namespace = namespace;
      };
      spec = {
        provider = "aws";
        objectStorage = {
          bucket = "homelab-backup-velero";
        };
        config = {
          region = "sa-east-1";
          s3ForcePathStyle = "true";
          s3Url = "http://10.10.10.209:9000";
        };
        credential = {
          name = "velero-s3-credentials";
          key = "cloud";
        };
      };
    }
    {
      apiVersion = "velero.io/v1";
      kind = "Schedule";
      metadata = {
        name = "daily-backup";
        namespace = namespace;
      };
      spec = {
        schedule = "0 3 * * *";
        template = {
          ttl = "336h";
          includedNamespaces = [ "*" ];
          snapshotVolumes = false;
          defaultVolumesToFsBackup = false;
        };
      };
    }
  ];
}
