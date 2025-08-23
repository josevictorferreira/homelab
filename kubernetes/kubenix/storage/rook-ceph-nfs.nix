{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  nfsName = "homelab-nfs";
  pseudo = "/homelab";
  cephfs = "ceph-filesystem";
  cephfsPath = "/";
  allowedCIDRs = [ "10.10.10.0/24" ];
  lbIP = homelab.kubernetes.loadBalancer.services.${nfsName};
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
          protocols = [ 4 ];
          transports = [ "TCP" ];
          fsal = { name = "CEPH"; fs_name = cephfs; };
          clients = [
            { addresses = allowedCIDRs; access_type = "RW"; squash = "no_root_squash"; }
          ];
        };
        "conf-nfs.${nfsName}" = ''
          NFS_CORE_PARAM {
                  Enable_NLM = false;
                  Enable_RQUOTA = false;
                  Protocols = 4;
                  allow_set_io_flusher_fail = true;
          }

          MDCACHE {
                  Dir_Chunk = 0;
          }

          EXPORT_DEFAULTS {
                  Attr_Expiration_Time = 0;
          }

          EXPORT {
                  Access_Type = RW;
                  Path = "${cephfsPath}";
                  Pseudo = "${pseudo}";
                  Squash = No_Root_Squash;
                  Security_Label = false;
                  Protocols = 4;
                  Transports = TCP;
                  FSAL {
                          Name = CEPH;
                          FS_Name = "${cephfs}";
                  }
                  CLIENTS {
                    Addresses = ${builtins.concatStringsSep " " allowedCIDRs};
                    Access_Type = RW;
                    Squash = No_Root_Squash;
                  }
          }

          NFSv4 {
                  Delegations = false;
                  RecoveryBackend = "rados_cluster";
                  Minor_Versions = 0, 1, 2;
          }

          RADOS_KV {
                  ceph_conf = "/etc/ceph/ceph.conf";
                  userid = nfs-ganesha.${nfsName}.a;
                  nodeid = ${nfsName}.a;
                  pool = ".nfs";
                  namespace = "${nfsName}";
          }

          RGW {
                  name = "client.nfs-ganesha.${nfsName}.a";
          }
        '';
      };
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
                else echo "No ceph admin secret found in rook-ceph-mon"; exit 2; fi

                if [ -f /var/lib/rook-ceph-mon/ceph-username ]; then username=$(cat /var/lib/rook-ceph-mon/ceph-username)
                else username=client.admin; fi

                cat > "$KEYRING_FILE" <<EOF
                [$username]
                key = $ceph_secret
                EOF

                ceph -c "$CEPH_CONFIG" mgr module enable nfs || true

                cluster='${nfsName}'

                ceph -c "$CEPH_CONFIG" nfs export apply "$cluster" -i /etc/ganesha/export.json

                rados -p .nfs -N ${nfsName} put conf-nfs.${nfsName} /etc/ganesha/conf-nfs.${nfsName}
                
                echo "Current NFS-Ganesha configuration:"
                echo "---"
                ceph -c "$CEPH_CONFIG" nfs cluster config get "$cluster"
                echo "---"
                ceph -c "$CEPH_CONFIG" nfs export ls "$cluster" --detailed
                echo "---"
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
