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

    configMaps."ceph-nfs-userconf-${nfsName}" = {
      metadata = { name = "ceph-nfs-userconf-${nfsName}"; namespace = namespace; };
      data.userconf = ''
        NFSv4 {
          Minor_Versions = 0,1,2;
          Delegations = false;
          RecoveryBackend = rados_cluster;
        }
      '';
    };

    jobs."ceph-nfs-userconf-apply-${nfsName}" = {
      metadata = { name = "ceph-nfs-userconf-apply-${nfsName}"; namespace = namespace; };
      spec = {
        backoffLimit = 3;
        ttlSecondsAfterFinished = 3600;
        template.spec = {
          restartPolicy = "OnFailure";
          containers = [{
            name = "apply-userconf";
            image = "quay.io/ceph/ceph:v19";
            command = [
              "/bin/bash"
              "-lc"
              ''
                set -euo pipefail

                # ----- bootstrap ceph CLI (same as your export job) -----
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

                # ----- objects we manage -----
                cluster='${nfsName}'
                ns="$cluster"
                obj_conf="conf-nfs.$cluster"
                obj_user="userconf-nfs.$cluster"

                # 2a) Write/replace user config object from ConfigMap
                rados -p .nfs -N "$ns" put "$obj_user" /etc/ganesha/userconf

                # 2b) Ensure conf-nfs includes it (append if missing; create if absent)
                tmp=$(mktemp)
                if rados -p .nfs -N "$ns" get "$obj_conf" "$tmp" 2>/dev/null; then
                  if ! grep -q "$obj_user" "$tmp"; then
                    echo "%url \"rados://.nfs/$ns/$obj_user\"" >> "$tmp"
                    rados -p .nfs -N "$ns" put "$obj_conf" "$tmp"
                  fi
                else
                  printf '%%url "rados://.nfs/%s/%s"\n' "$ns" "$obj_user" > "$tmp"
                  rados -p .nfs -N "$ns" put "$obj_conf" "$tmp"
                fi

                echo "---- conf-nfs.$cluster (head) ----"
                head -n 100 "$tmp" || true
              ''
            ];
            volumeMounts = [
              { name = "mon-endpoints"; mountPath = "/etc/rook"; }
              { name = "ceph-config"; mountPath = "/etc/ceph"; }
              { name = "ceph-admin-secret"; mountPath = "/var/lib/rook-ceph-mon"; readOnly = true; }
              { name = "userconf"; mountPath = "/etc/ganesha"; } # provides /etc/ganesha/userconf
            ];
          }];
          volumes = [
            {
              name = "mon-endpoints";
              configMap = { name = "rook-ceph-mon-endpoints"; items = [{ key = "data"; path = "mon-endpoints"; }]; };
            }
            { name = "ceph-config"; emptyDir = { }; }
            { name = "ceph-admin-secret"; secret = { secretName = "rook-ceph-mon"; }; }
            {
              name = "userconf";
              configMap = { name = "ceph-nfs-userconf-${nfsName}"; items = [{ key = "userconf"; path = "userconf"; }]; };
            }
          ];
        };
      };
    };
  };
}
