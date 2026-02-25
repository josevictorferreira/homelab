{ homelab, ... }:

let
  fsName = "ceph-filesystem";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources = {

    persistentVolumes = {

      "cephfs-shared-storage-root" = {
        metadata.name = "cephfs-shared-storage-root";
        spec = {
          capacity.storage = "1Gi";
          accessModes = [ "ReadWriteMany" ];
          persistentVolumeReclaimPolicy = "Retain";
          volumeMode = "Filesystem";
          csi = {
            driver = "rook-ceph.cephfs.csi.ceph.com";
            volumeHandle = "cephfs-shared-storage-root";
            nodeStageSecretRef = {
              name = "cephfs-user-secret";
              inherit namespace;
            };
            volumeAttributes = {
              clusterID = "rook-ceph";
              inherit fsName;
              staticVolume = "true";
              rootPath = "/volumes/nfs-exports/homelab-nfs/5a434804-52fc-4e58-b09f-592a37a16a97";
            };
          };
        };
      };

      "cephfs-shared-storage-downloads" = {
        metadata.name = "cephfs-shared-storage-downloads";
        spec = {
          capacity.storage = "1Gi";
          accessModes = [ "ReadWriteMany" ];
          persistentVolumeReclaimPolicy = "Retain";
          volumeMode = "Filesystem";
          csi = {
            driver = "rook-ceph.cephfs.csi.ceph.com";
            volumeHandle = "cephfs-shared-storage-downloads";
            nodeStageSecretRef = {
              name = "cephfs-user-secret";
              inherit namespace;
            };
            volumeAttributes = {
              clusterID = "rook-ceph";
              inherit fsName;
              staticVolume = "true";
              rootPath = "/volumes/nfs-exports/homelab-nfs/5a434804-52fc-4e58-b09f-592a37a16a97/downloads";
            };
          };
        };
      };

    };

    persistentVolumeClaims = {

      "cephfs-shared-storage-root" = {
        metadata = {
          name = "cephfs-shared-storage-root";
          inherit namespace;
        };
        spec = {
          accessModes = [ "ReadWriteMany" ];
          resources.requests.storage = "1Gi";
          storageClassName = "";
          volumeMode = "Filesystem";
          volumeName = "cephfs-shared-storage-root";
        };
      };

      "cephfs-shared-storage-downloads" = {
        metadata = {
          name = "cephfs-shared-storage-downloads";
          inherit namespace;
        };
        spec = {
          accessModes = [ "ReadWriteMany" ];
          resources.requests.storage = "1Gi";
          storageClassName = "";
          volumeMode = "Filesystem";
          volumeName = "cephfs-shared-storage-downloads";
        };
      };

    };

  };
}
