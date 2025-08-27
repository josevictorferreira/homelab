{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  nfsName = "homelab-nfs";
  pseudo = "/${nfsName}";
  cephfs = "ceph-filesystem";
  allowedCIDRs = [
    "10.10.10.0/24"
    "10.0.0.0/24"
  ];
  customGaneshaConf = ''

    NFSv4 {
      Delegations = false;
      RecoveryBackend = "rados_cluster";
      Minor_Versions = 0, 1, 2;
      Only_Numeric_Owners = true;
    }
  
    NFS_KRB5 { Active_krb5 = false; }

    CEPH { ceph_conf = "/etc/ceph/ceph.conf"; }
  
    EXPORT_DEFAULTS {
      Attr_Expiration_Time = 0;
      Protocols = 4;
      Transports = TCP;
      Access_Type = RW;
      Squash = All_Squash;
      Manage_Gids = true;
      Anonymous_uid = 2002;
      Anonymous_gid = 2002;
      SecType = "sys";
    }


  '';
  exportConf = {
    export_id = 10;
    path = "/exported/path";
    pseudo = pseudo;
    security_label = false;
    access_type = "RW";
    squash = "all_squash";
    sectype = [ "sys" ];
    fsal = {
      name = "CEPH";
      fs_name = cephfs;
    };
    clients = [
      {
        addresses = allowedCIDRs;
        access_type = "RW";
        squash = "all_squash";
        protocols = [ 4 ];
        sectype = [ "sys" ];
      }
    ];
  };
in
{
  kubernetes.resources = {
    cephnfs.${nfsName} = {
      metadata = {
        namespace = namespace;
      };
      spec = {
        server = {
          active = 1;
          resources = {
            requests = { cpu = "50m"; memory = "64Mi"; };
            limits = { memory = "2Gi"; };
          };
          placement = {
            tolerations = [
              { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
            ];
          };
          logLevel = "NIV_FULL_DEBUG";
        };
      };
    };

    services.${nfsName} = {
      metadata = {
        annotations = kubenix.lib.serviceIpFor nfsName;
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
          { name = "nfs-tcp"; nodePort = 30325; port = 2049; targetPort = 2049; protocol = "TCP"; }
          { name = "nfs-udp"; nodePort = 30326; port = 2049; targetPort = 2049; protocol = "UDP"; }
        ];
      };
    };

    configMaps = {
      "${nfsName}-ganesha-custom-config" = {
        metadata = {
          name = "${nfsName}-ganesha-custom-config";
          namespace = namespace;
        };
        data = {
          "custom.ganesha.conf" = customGaneshaConf;
          "export.json" = builtins.toJSON exportConf;
        };
      };
    };

    jobs."${nfsName}-ganesha-config-patcher" = {
      metadata = {
        name = "${nfsName}-ganesha-config-patcher";
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
                EXPORT_ID=${toString exportConf.export_id}
                SUBVOL_GROUP='nfs-exports'
                SUBVOL_NAME='${nfsName}'
                FS='${cephfs}'
                CLUSTER='${nfsName}'
                NFSNS='${nfsName}'
                RADOS_POOL='.nfs'

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
                ceph -c "$CEPH_CONFIG" mgr module enable rook || true
                ceph -c "$CEPH_CONFIG" orch set backend rook || true

                echo "Updating RADOS pool $RADOS_POOL Auth Caps"
                for SUFFIX in a b c d; do
                  ID="client.nfs-ganesha.$${CLUSTER}.$${SUFFIX}"
                  echo "Creating ID $ID"
                  ceph -c "$CEPH_CONFIG" auth get-or-create "$ID" \
                    mon 'allow r' \
                    mgr 'allow rw' \
                    osd "allow rw pool=$${RADOS_POOL} namespace=$${NFSNS}" >/dev/null || true
                done

                echo "Updating NFS Ganesha cluster $CLUSTER Auth Caps"
                for ID in $(ceph -c "$CEPH_CONFIG" auth ls | awk '/client\.nfs-ganesha\.'"$CLUSTER"'\./{print $1}'); do
                  echo "Setting caps for $ID"
                  ceph -c "$CEPH_CONFIG" auth caps "$ID" \
                    mon 'allow r' \
                    mgr 'allow rw' \
                    osd "allow rw pool=$${RADOS_POOL} namespace=$${NFSNS}" || true
                done

                if ! SUBVOL_PATH="$(
                  ceph -c "$CEPH_CONFIG" fs subvolume getpath "$FS" "$SUBVOL_NAME" --group_name "$SUBVOL_GROUP" 2>/dev/null
                )"; then
                  echo "Creating subvolume group and subvolume..."
                  if ! ceph -c "$CEPH_CONFIG" fs subvolumegroup ls "$FS" -f json 2>/dev/null \
                      | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$SUBVOL_GROUP\""; then
                    echo "Creating subvolume group $SUBVOL_GROUP in filesystem $FS"
                    ceph -c "$CEPH_CONFIG" fs subvolumegroup create "$FS" "$SUBVOL_GROUP"
                  fi

                  if ! ceph -c "$CEPH_CONFIG" fs subvolume info "$FS" "$SUBVOL_NAME" --group_name "$SUBVOL_GROUP" >/dev/null 2>&1; then
                    echo "Creating subvolume $SUBVOL_NAME in group $SUBVOL_GROUP"
                    ceph -c "$CEPH_CONFIG" fs subvolume create "$FS" "$SUBVOL_NAME" \
                      --group_name "$SUBVOL_GROUP" --size 0 --uid 2002 --gid 2002 --mode 2775
                  fi

                  SUBVOL_PATH="$(ceph -c "$CEPH_CONFIG" fs subvolume getpath "$FS" "$SUBVOL_NAME" --group_name "$SUBVOL_GROUP")"
                fi

                echo "Subvolume path: $SUBVOL_PATH"

                awk -v newval="$SUBVOL_PATH" '{
                  gsub(/"path":[[:space:]]*"[^"]*"/, "\"path\": \"" newval "\"");
                  print
                }' /tmp/ganesha/export.json > /tmp/export_final.json

                ceph -c "$CEPH_CONFIG" nfs export apply "$CLUSTER" -i /tmp/export_final.json
                ceph -c "$CEPH_CONFIG" nfs cluster config reset "$CLUSTER" || true
                ceph -c "$CEPH_CONFIG" nfs cluster config set "$CLUSTER" -i /tmp/ganesha/custom.ganesha.conf

                rados -p .nfs --namespace $NFSNS get "conf-nfs.$CLUSTER"     /tmp/conf-nfs                || true
                rados -p .nfs --namespace $NFSNS get "export-$EXPORT_ID"     /tmp/export-$$EXPORT_ID     || true
                rados -p .nfs --namespace $NFSNS get "userconf-nfs.$CLUSTER" /tmp/userconf-nfs            || true

                echo "--------------------------- CONTENTS -----------------------------"
                cat /tmp/conf-nfs                || echo "(conf-nfs not found)"
                echo "------------------------------------------------------------------"
                cat "/tmp/export-$EXPORT_ID"     || echo "(export-$CLUSTER not found)"
                echo "------------------------------------------------------------------"
                cat /tmp/userconf-nfs            || echo "(userconf-nfs not found)"

                echo "Restarting NFS Ganesha grace..."
                for SUFFIX in a b c d; do
                  ganesha-rados-grace --pool .nfs --ns "$NFSNS" add "$${CLUSTER}-$${SUFFIX}"   || true
                  ganesha-rados-grace --pool .nfs --ns "$NFSNS" start "$${CLUSTER}-$${SUFFIX}" || true
                done

                echo "Removing orchestrator backend..."
                ceph -c "$CEPH_CONFIG" orch set backend "" || true

                echo "DONE."
              ''
            ];
            volumeMounts = [
              { name = "mon-endpoints"; mountPath = "/etc/rook"; }
              { name = "ceph-config"; mountPath = "/etc/ceph"; }
              { name = "ceph-admin-secret"; mountPath = "/var/lib/rook-ceph-mon"; readOnly = true; }
              { name = "${nfsName}-ganesha-custom-config"; mountPath = "/tmp/ganesha"; readOnly = true; }
            ];
          }];
          volumes = [
            { name = "mon-endpoints"; configMap = { name = "rook-ceph-mon-endpoints"; items = [{ key = "data"; path = "mon-endpoints"; }]; }; }
            { name = "ceph-config"; emptyDir = { }; }
            { name = "ceph-admin-secret"; secret = { secretName = "rook-ceph-mon"; }; }
            { name = "${nfsName}-ganesha-custom-config"; configMap = { name = "${nfsName}-ganesha-custom-config"; }; }
          ];
        };
      };
    };

  };
}
