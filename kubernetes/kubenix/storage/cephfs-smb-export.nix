{ kubenix, homelab, lib, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  pvName = "cephfs-shared-storage";
  pvcName = "cephfs-shared-storage";
  appName = "cephfs-smb-export";
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
            fsName = "ceph-filesystem";
            staticVolume = "true";
            rootPath = "/volumes/nfs-exports/homelab-nfs/dfd23da6-d80d-48c7-b568-025ec7badd17";
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

    configMaps."${appName}-config" = {
      metadata = {
        name = "${appName}-config";
        namespace = namespace;
      };
      data."config.yml" = ''
        auth:
          - user: homelab
            group: homelab
            uid: 2002
            gid: 2002
            password: teste123

        global:
          - "server min protocol = SMB2"
          - "server max protocol = SMB3"
          - "map to guest = Bad User"
          - "ea support = yes"
          - "vfs objects = fruit streams_xattr"
          - "fruit:metadata = stream"
          - "fruit:model = MacSamba"
          - "inherit permissions = yes"
          - "create mask = 0664"
          - "directory mask = 0775"

        share:
          - name: cephfs
            path: /samba/share
            browsable: yes
            readonly: no
            guestok: no
            validusers: homelab
            writelist: homelab
            veto: no
            recycle: yes
      '';
    };

    # --- Samba Deployment ---
    deployments.${appName} = {
      metadata = {
        name = appName;
        namespace = namespace;
        labels.app = appName;
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = appName;
        template = {
          metadata.labels.app = appName;
          spec = {
            containers = [
              {
                name = "samba";
                image = "ghcr.io/crazy-max/samba:4.21.4";
                imagePullPolicy = "IfNotPresent";
                ports = [
                  { name = "smb"; containerPort = 445; protocol = "TCP"; }
                ];
                volumeMounts = [
                  { name = "config"; mountPath = "/data/config.yml"; subPath = "config.yml"; }
                  { name = "share"; mountPath = "/samba/share"; }
                ];
              }
            ];
            volumes = [
              { name = "config"; configMap.name = "${appName}-config"; }
              { name = "share"; persistentVolumeClaim.claimName = pvcName; }
            ];
          };
        };
      };
    };

    services.${appName} = {
      metadata = {
        name = appName;
        namespace = namespace;
        labels.app = appName;
      };
      spec = {
        type = "LoadBalancer";
        selector.app = appName;
        ports = [
          { name = "smb"; port = 445; targetPort = 445; protocol = "TCP"; }
        ];
      };
    };
  };
}
