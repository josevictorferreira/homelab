{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.backup;
in

{
  kubernetes.helm.releases.velero = {
    includeCRDs = false;
    chart = kubenix.lib.helm.fetch {
      repo = "https://vmware-tanzu.github.io/helm-charts";
      chart = "velero";
      version = "12.2.2";
      sha256 = "sha256-ACcKsEe2foDG7gakvtvgYcZiYhzptJufMgIKIii2jiQ=";
    };
    inherit namespace;
    values = {
      configuration = {
        backupStorageLocation = [ ];
        volumeSnapshotLocation = [ ];
      };

      deployNodeAgent = false;

      metrics = {
        enabled = true;
        scrapeInterval = "30s";
        serviceMonitor = {
          enabled = true;
          autodetect = true;
        };
        nodeAgentPodMonitor = {
          enabled = false;
        };
      };

      credentials = {
        useSecret = true;
        existingSecret = "velero-s3-credentials";
      };

      initContainers = [
        {
          name = "velero-plugin-for-aws";
          image = "velero/velero-plugin-for-aws:v1.14.4@sha256:c85a7fa803569e3128c33e4f5766f84ab156c8d171c9f1dd2715581d45ce98fa";
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
        inherit namespace;
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
        inherit namespace;
      };
      spec = {
        schedule = "0 3 * * *";
        template = {
          ttl = "336h";
          includedNamespaces = [ "*" ];
          excludedNamespaces = [ homelab.kubernetes.namespaces.storage ];
          snapshotVolumes = false;
          defaultVolumesToFsBackup = false;
        };
      };
    }
  ];
}
