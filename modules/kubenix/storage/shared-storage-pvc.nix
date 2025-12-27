{ homelab, ... }:

let
  pvName = "cephfs-shared-storage";
  pvcName = "cephfs-shared-storage";
  fsName = "ceph-filesystem";
  exportPath = "/volumes/nfs-exports/homelab-nfs/dfd23da6-d80d-48c7-b568-025ec7badd17";
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
            namespace = namespace;
          };
          volumeAttributes = {
            clusterID = "rook-ceph";
            fsName = fsName;
            staticVolume = "true";
            rootPath = exportPath;
          };
        };
      };
    };

    persistentVolumeClaims.${pvcName} = {
      metadata = {
        name = pvcName;
        namespace = namespace;
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
