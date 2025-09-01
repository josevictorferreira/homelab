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
      metadata = { name = pvName; };
      spec = {
        capacity.storage = "1Gi";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
        volumeMode = "Filesystem";
        storageClassName = "rook-ceph-filesystem";
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
        storageClassName = "rook-ceph-filesystem";
        volumeName = pvName;
      };
    };

    configMaps."${appName}-conf" = {
      metadata = {
        name = "${appName}-conf";
        namespace = namespace;
      };
      data."smb.conf" = ''
        [global]
          server min protocol = SMB2
          map to guest = Bad User
          security = user
          load printers = no
          printing = bsd
          disable spoolss = yes
          smb2 leases = yes
          aio read size = 1
          aio write size = 1
          # Preserve/propagate ACLs on CephFS and store NT ACLs in xattrs
          vfs objects = acl_xattr
          ea support = yes
          map acl inherit = yes
          inherit acls = yes
          inherit permissions = yes

        [cephfs]
          path = /export
          browseable = yes
          read only = no
          guest ok = no
          valid users = @smbusers

          # >>> Squash everything to uid/gid 2002 via a fixed unix account <<<
          force user = smb2002
          force group = smb2002

          # Sensible masks; adjust if you need stricter perms
          create mask = 0664
          force create mode = 0664
          directory mask = 0775
          force directory mode = 0775
      '';
    };


    deployments.${appName} = {
      metadata = {
        name = appName;
        namespace = namespace;
        labels = { app = appName; };
      };
      spec = {
        replicas = 1;
        selector.matchLabels = { app = appName; };
        template = {
          metadata.labels = { app = appName; };
          spec = {
            securityContext = {
              fsGroup = 2002;
              fsGroupChangePolicy = "OnRootMismatch";
              supplementalGroups = [ 2002 ];
            };

            containers = [
              {
                name = "samba";
                image = "quay.io/samba.org/samba-server:latest";
                imagePullPolicy = "IfNotPresent";

                command = [ "/bin/sh" ];
                args = [
                  "-c"
                  ''
                    set -eu

                    getent group 2002 >/dev/null 2>&1 || groupadd -g 2002 smb2002
                    getent group smbusers >/dev/null 2>&1 || groupadd smbusers

                    id -u smb2002 >/dev/null 2>&1 || useradd -u 2002 -g 2002 -M -s /sbin/nologin smb2002

                    if ! id "$${SMB_USERNAME}" >/dev/null 2>&1; then
                      useradd -M -s /sbin/nologin "$${SMB_USERNAME}" || true
                    fi
                    usermod -a -G smbusers "$${SMB_USERNAME}" || true

                    printf "%s\n%s\n" "$${SMB_PASSWORD}" "$${SMB_PASSWORD}" | smbpasswd -a -s "$${SMB_USERNAME}" || true

                    chown -R 2002:2002 /export || true

                    smbd -F --no-process-group
                  ''
                ];

                ports = [{ name = "smb"; containerPort = 445; protocol = "TCP"; }];

                env = [
                  {
                    name = "SMB_USERNAME";
                    valueFrom.secretKeyRef = { name = "smb-export-credentials"; key = "username"; };
                  }
                  {
                    name = "SMB_PASSWORD";
                    valueFrom.secretKeyRef = { name = "smb-export-credentials"; key = "password"; };
                  }
                ];

                readinessProbe = { tcpSocket.port = 445; initialDelaySeconds = 5; periodSeconds = 10; };
                livenessProbe = { tcpSocket.port = 445; initialDelaySeconds = 15; periodSeconds = 20; };

                securityContext = {
                  runAsUser = 0;
                  runAsGroup = 0;
                  capabilities.add = [ "NET_BIND_SERVICE" ];
                };

                volumeMounts = [
                  { name = "conf"; mountPath = "/etc/samba/smb.conf"; subPath = "smb.conf"; }
                  { name = "data"; mountPath = "/export"; }
                  { name = "state"; mountPath = "/var/lib/samba"; }
                  { name = "cache"; mountPath = "/var/cache/samba"; }
                  { name = "run"; mountPath = "/run"; }
                ];
              }
            ];

            volumes = [
              { name = "conf"; configMap = { name = "${appName}-conf"; }; }
              { name = "data"; persistentVolumeClaim = { claimName = pvcName; }; }
              { name = "state"; emptyDir = { }; }
              { name = "cache"; emptyDir = { }; }
              { name = "run"; emptyDir = { }; }
            ];
          };
        };
      };
    };


    services.${appName} = {
      metadata = {
        name = appName;
        namespace = namespace;
        labels = { app = appName; };
      };
      spec = {
        type = "LoadBalancer";
        selector = { app = appName; };
        ports = [
          { name = "smb"; port = 445; targetPort = 445; protocol = "TCP"; }
        ];
      };
    };
  };
}

