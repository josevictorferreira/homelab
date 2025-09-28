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
              namespace = namespace;
            };
            volumeAttributes = {
              clusterID = "rook-ceph";
              fsName = fsName;
              staticVolume = "true";
              rootPath = "/volumes/nfs-exports/homelab-nfs/dfd23da6-d80d-48c7-b568-025ec7badd17";
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
              namespace = namespace;
            };
            volumeAttributes = {
              clusterID = "rook-ceph";
              fsName = fsName;
              staticVolume = "true";
              rootPath = "/volumes/nfs-exports/homelab-nfs/dfd23da6-d80d-48c7-b568-025ec7badd17/downloads";
            };
          };
        };
      };

      "cephfs-shared-storage-images" = {
        metadata.name = "cephfs-shared-storage-images";
        spec = {
          capacity.storage = "1Gi";
          accessModes = [ "ReadWriteMany" ];
          persistentVolumeReclaimPolicy = "Retain";
          volumeMode = "Filesystem";
          csi = {
            driver = "rook-ceph.cephfs.csi.ceph.com";
            volumeHandle = "cephfs-shared-storage-images";
            nodeStageSecretRef = {
              name = "cephfs-user-secret";
              namespace = namespace;
            };
            volumeAttributes = {
              clusterID = "rook-ceph";
              fsName = fsName;
              staticVolume = "true";
              rootPath = "/volumes/nfs-exports/homelab-nfs/dfd23da6-d80d-48c7-b568-025ec7badd17/images";
            };
          };
        };
      };

    };

    persistentVolumeClaims = {

      "cephfs-shared-storage-root" = {
        metadata = {
          name = "cephfs-shared-storage-root";
          namespace = namespace;
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
          namespace = namespace;
        };
        spec = {
          accessModes = [ "ReadWriteMany" ];
          resources.requests.storage = "1Gi";
          storageClassName = "";
          volumeMode = "Filesystem";
          volumeName = "cephfs-shared-storage-downloads";
        };
      };

      "cephfs-shared-storage-images" = {
        metadata = {
          name = "cephfs-shared-storage-images";
          namespace = namespace;
        };
        spec = {
          accessModes = [ "ReadWriteMany" ];
          resources.requests.storage = "1Gi";
          storageClassName = "";
          volumeMode = "Filesystem";
          volumeName = "cephfs-shared-storage-images";
        };
      };

    };

  };
}
