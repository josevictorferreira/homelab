{ homelab, ... }:

let
  pvName = "cephfs-shared-storage";
  pvcName = "cephfs-shared-storage";
  fsName = "ceph-filesystem";
  exportPath = "/volumes/nfs-exports/homelab-nfs/5a434804-52fc-4e58-b09f-592a37a16a97";
  namespace = homelab.kubernetes.namespaces.storage;
in
{
  kubernetes.resources = {

    persistentVolumes.${pvName} = {
      metadata.name = pvName;
      spec = {
        capacity.storage = "1Gi";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
        volumeMode = "Filesystem";
        csi = {
          driver = "rook-ceph.cephfs.csi.ceph.com";
          volumeHandle = pvName;
          nodeStageSecretRef = {
            name = "cephfs-user-secret";
            inherit namespace;
          };
          volumeAttributes = {
            clusterID = "rook-ceph";
            inherit fsName;
            staticVolume = "true";
            rootPath = exportPath;
          };
        };
      };
    };

    persistentVolumeClaims.${pvcName} = {
      metadata = {
        name = pvcName;
        inherit namespace;
      };
      spec = {
        accessModes = [ "ReadWriteMany" ];
        resources.requests.storage = "1Gi";
        storageClassName = "";
        volumeMode = "Filesystem";
        volumeName = pvName;
      };
    };

  };
}
