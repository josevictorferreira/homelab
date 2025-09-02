{ homelab, ... }:

let
  pvName = "cephfs-shared-storage";
  pvcName = "cephfs-shared-storage";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources = {
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
