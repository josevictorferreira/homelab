{ homelab, ... }:

let
  fsName = "ceph-filesystem";
  namespace = homelab.kubernetes.namespaces.backup;
in
{
  kubernetes.resources = {

    persistentVolumes."cephfs-shared-storage-root-backup" = {
      metadata.name = "cephfs-shared-storage-root-backup";
      spec = {
        capacity.storage = "1Gi";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
        volumeMode = "Filesystem";
        csi = {
          driver = "rook-ceph.cephfs.csi.ceph.com";
          volumeHandle = "cephfs-shared-storage-root-backup";
          nodeStageSecretRef = {
            name = "cephfs-user-secret";
            namespace = homelab.kubernetes.namespaces.applications;
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

    persistentVolumeClaims."cephfs-shared-storage-root" = {
      metadata = {
        name = "cephfs-shared-storage-root";
        inherit namespace;
      };
      spec = {
        accessModes = [ "ReadWriteMany" ];
        resources.requests.storage = "1Gi";
        storageClassName = "";
        volumeMode = "Filesystem";
        volumeName = "cephfs-shared-storage-root-backup";
      };
    };

  };
}
