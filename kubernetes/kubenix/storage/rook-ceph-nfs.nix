{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  nfsName = "homelab-nfs";
  pseudo = "/homelab";
  cephfs = "ceph-filesystem";
  cephfsPath = "/";
  allowedCIDRs = [ "10.10.10.0/24" ];
  lbIP = homelab.kubernetes.loadBalancer.services."homelab-nfs";
in
{
  kubernetes.resources = {
    cephnfs.${nfsName} = {
      metadata = {
        namespace = namespace;
      };
      spec = {
        server = {
          active = 2;
          resources = {
            requests = { cpu = "50m"; memory = "64Mi"; };
            limits = { memory = "512Mi"; };
          };
          placement = {
            tolerations = [
              { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
            ];
          };
        };
      };
    };

    services.${nfsName} = {
      metadata = {
        annotations = {
          "lbipam.cilium.io/ips" = lbIP;
        };
        namespace = namespace;
      };
      spec = {
        type = "LoadBalancer";
        externalTrafficPolicy = "Cluster";
        selector = {
          app = "rook-ceph-nfs";
          ceph_daemon_type = "nfs";
        };
        ports = [
          { name = "nfs"; port = 2049; targetPort = 2049; protocol = "TCP"; }
          { name = "nfs-udp"; port = 2049; targetPort = 2049; protocol = "UDP"; }
          { name = "mountd-tcp"; port = 20048; targetPort = 20048; protocol = "TCP"; }
          { name = "mountd-udp"; port = 20048; targetPort = 20048; protocol = "UDP"; }
          { name = "rpcbind-tcp"; port = 111; targetPort = 111; protocol = "TCP"; }
          { name = "rpcbind-udp"; port = 111; targetPort = 111; protocol = "UDP"; }
        ];
      };
    };

    configMaps."ceph-nfs-export-${nfsName}" = {
      metadata = {
        name = "ceph-nfs-export-${nfsName}";
        namespace = namespace;
      };
      data = {
        "export.json" = builtins.toJSON {
          access_type = "RW";
          path = cephfsPath;
          pseudo = pseudo;
          squash = "no_root_squash";
          security_label = false;
          protocols = [ 3 4 ];
          transports = [ "TCP" ];
          fsal = { name = "CEPH"; fs_name = cephfs; };
          clients = [
            { addresses = allowedCIDRs; access_type = "RW"; squash = "no_root_squash"; }
          ];
        };
      };
    };

    configMaps."rook-ceph-nfs-${nfsName}-a" = {
      metadata = {
        name = "rook-ceph-nfs-${nfsName}-a";
        namespace = namespace;
        labels = {
          "app" = "rook-ceph-nfs";
          "ceph_nfs" = nfsName;
          "ceph_daemon_id" = "${nfsName}-a";
          "ceph_daemon_type" = "nfs";
          "rook_cluster" = "rook-ceph";
          "instance" = "a";
          "nfs" = "${nfsName}-a";
        };
      };
      data.config = ''
        NFS_CORE_PARAM {
          Enable_NLM = false;
          Enable_RQUOTA = false;
          MNT_PORT = 20048;
          Protocols = 3, 4;
        }
        MDCACHE {
          Dir_Chunk = 0;
        }
        EXPORT_DEFAULTS {
          Attr_Expiration_Time = 0;
        }
        NFSv4 {
          Delegations = false;
          RecoveryBackend = "rados_cluster";
          Minor_Versions = 0, 1, 2;
        }
        RADOS_KV {
          ceph_conf = "/etc/ceph/ceph.conf";
          userid = nfs-ganesha.homelab-nfs.a;
          nodeid = homelab-nfs.a;
          pool = ".nfs";
          namespace = "homelab-nfs";
        }
        RADOS_URLS {
          ceph_conf = "/etc/ceph/ceph.conf";
          userid = nfs-ganesha.homelab-nfs.a;
          watch_url = "rados://.nfs/homelab-nfs/conf-nfs.homelab-nfs";
        }
        RGW {
          name = "client.nfs-ganesha.homelab-nfs.a";
        }

        %url  rados://.nfs/homelab-nfs/conf-nfs.homelab-nfs
      '';
    };

    configMaps."rook-ceph-nfs-${nfsName}-b" = {
      metadata = {
        name = "rook-ceph-nfs-${nfsName}-b";
        namespace = namespace;
        labels = {
          "app" = "rook-ceph-nfs";
          "ceph_nfs" = nfsName;
          "ceph_daemon_id" = "${nfsName}-b";
          "ceph_daemon_type" = "nfs";
          "rook_cluster" = "rook-ceph";
          "instance" = "b";
          "nfs" = "${nfsName}-b";
        };
      };
      data.config = ''
        NFS_CORE_PARAM {
          Enable_NLM = false;
          Enable_RQUOTA = false;
          MNT_PORT = 20048;
          Protocols = 3, 4;
        }
        MDCACHE {
          Dir_Chunk = 0;
        }
        EXPORT_DEFAULTS {
          Attr_Expiration_Time = 0;
        }
        NFSv4 {
          Delegations = false;
          RecoveryBackend = "rados_cluster";
          Minor_Versions = 0, 1, 2;
        }
        RADOS_KV {
          ceph_conf = "/etc/ceph/ceph.conf";
          userid = nfs-ganesha.homelab-nfs.b;
          nodeid = homelab-nfs.b;
          pool = ".nfs";
          namespace = "homelab-nfs";
        }
        RADOS_URLS {
          ceph_conf = "/etc/ceph/ceph.conf";
          userid = nfs-ganesha.homelab-nfs.b;
          watch_url = "rados://.nfs/homelab-nfs/conf-nfs.homelab-nfs";
        }
        RGW {
          name = "client.nfs-ganesha.homelab-nfs.b";
        }

        %url  rados://.nfs/homelab-nfs/conf-nfs.homelab-nfs
      '';
    };

    jobs."ceph-nfs-export-apply-${nfsName}" = {
      metadata = {
        name = "ceph-nfs-export-apply-${nfsName}";
        namespace = namespace;
      };
      spec = {
        backoffLimit = 3;
        ttlSecondsAfterFinished = 3600;
        template.spec = {
          restartPolicy = "OnFailure";
          serviceAccountName = "rook-ceph-default";
          containers = [{
            name = "apply";
            image = "quay.io/ceph/ceph:v19";
            command = [
              "/bin/bash"
              "-lc"
              ''
                set -euo pipefail

                CEPH_CONFIG=/etc/ceph/ceph.conf
                MON_CONFIG=/etc/rook/mon-endpoints
                KEYRING_FILE=/etc/ceph/keyring
                endpoints=$(cat "$MON_CONFIG")
                mon_endpoints=$(echo "$endpoints" | sed 's/[a-z0-9_-]\+=//g')
                mkdir -p /etc/ceph
                cat > "$CEPH_CONFIG" <<EOF
                [global]
                mon_host = $mon_endpoints
                [client.admin]
                keyring = $KEYRING_FILE
                EOF
                if   [ -f /var/lib/rook-ceph-mon/ceph-secret ];  then ceph_secret=$(cat /var/lib/rook-ceph-mon/ceph-secret)
                elif [ -f /var/lib/rook-ceph-mon/admin-secret ]; then ceph_secret=$(cat /var/lib/rook-ceph-mon/admin-secret)
                else echo "No ceph admin secret found"; exit 2; fi
                if [ -f /var/lib/rook-ceph-mon/ceph-username ]; then username=$(cat /var/lib/rook-ceph-mon/ceph-username); else username=client.admin; fi
                cat > "$KEYRING_FILE" <<EOF
                [$username]
                key = $ceph_secret
                EOF

                ceph -c "$CEPH_CONFIG" mgr module enable nfs || true

                cluster='${nfsName}'

                ceph -c "$CEPH_CONFIG" nfs export apply "$cluster" -i /etc/ganesha/export.json
              ''
            ];
            volumeMounts = [
              { name = "mon-endpoints"; mountPath = "/etc/rook"; }
              { name = "ceph-config"; mountPath = "/etc/ceph"; }
              { name = "ceph-admin-secret"; mountPath = "/var/lib/rook-ceph-mon"; readOnly = true; }
              { name = "export"; mountPath = "/etc/ganesha"; readOnly = true; }
            ];
          }];
          volumes = [
            { name = "mon-endpoints"; configMap = { name = "rook-ceph-mon-endpoints"; items = [{ key = "data"; path = "mon-endpoints"; }]; }; }
            { name = "ceph-config"; emptyDir = { }; }
            { name = "ceph-admin-secret"; secret = { secretName = "rook-ceph-mon"; }; }
            { name = "export"; configMap = { name = "ceph-nfs-export-${nfsName}"; }; }
          ];
        };
      };
    };
  };
}
