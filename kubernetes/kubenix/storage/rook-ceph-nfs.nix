{ lib, kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  replicaCount = 2;
  nodesIds = lib.lists.take replicaCount (builtins.genList (i: builtins.elemAt (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz") i) 26);
  nfsName = "homelab-nfs";
  pseudo = "/${nfsName}";
  cephfs = "ceph-filesystem";
  genGaneshaConfForNode = nodeId: ''
    NFS_CORE_PARAM {
      Enable_NLM = false;
      Enable_RQUOTA = false;
      Protocols = 4;
      Bind_addr = 0.0.0.0;
      NFS_Port = 2049;
      Allow_Set_Io_Flusher_Fail = true;
    }

    MDCACHE {
      Dir_Chunk = 0;
      Cache_FDs = true;
    }

    NFS_KRB5 { Active_krb5 = false; }

    NFSv4 {
      Graceless = false;
      Delegations = false;
      Minor_Versions = 0, 1, 2;
      Allow_Numeric_Owners = true;
      Only_Numeric_Owners = true;
      RecoveryBackend = "rados_cluster";
      pnfs_mds = true;
      pnfs_ds = true;
      Lease_Lifetime = 60;
    }

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

    RADOS_KV {
      ceph_conf = "/etc/ceph/ceph.conf";
      userid = nfs-ganesha.${nfsName}.${nodeId};
      nodeid = ${nfsName}.${nodeId};
      pool = ".nfs";
      namespace = "${nfsName}";
    }

    CEPH { Ceph_Conf = "/etc/ceph/ceph.conf"; }

    RADOS_URLS {
      ceph_conf = "/etc/ceph/ceph.conf";
      userid = nfs-ganesha.${nfsName}.${nodeId};
      watch_url = "rados://.nfs/${nfsName}/conf-nfs.${nfsName}";
    }

    LOG {
      Default_Log_Level = INFO;
      Components {
        ALL = "INFO";
        CLIENT = "DEBUG";
        FSA = "DEBUG";
        NFSV4 = "DEBUG";
        RADOS = "DEBUG";
        RADOS_URLS = "DEBUG";
      }
    }

    %url    "rados://.nfs/${nfsName}/conf-nfs.${nfsName}"

  '';
  baseExportConf = ''
    EXPORT {
      Export_Id = 0;
      Path = "/";
      Pseudo = "/";
      Access_Type = RW;
      Squash = No_Root_Squash;
      SecType = sys;
      Security_Label = false;
      FSAL {
        Name = CEPH;
        User_Id = "__USER_ID__";
        Filesystem = "${cephfs}";
      }
    }
  '';
  exportConf = {
    export_id = 10;
    path = "__SUBVOL_PATH__";
    pseudo = pseudo;
    security_label = false;
    access_type = "RW";
    squash = "all_squash";
    fsal = {
      name = "CEPH";
      fs_name = cephfs;
    };
    clients = [
      {
        addresses = "*";
        protocol = "4";
        access_type = "RW";
        squash = "all_squash";
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
          active = replicaCount;
          resources = {
            requests = { cpu = "50m"; memory = "64Mi"; };
            limits = { memory = "1Gi"; };
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
        annotations = kubenix.lib.serviceIpFor "nfs";
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

    jobs."${nfsName}-ceph-export-task" = {
      metadata = {
        name = "${nfsName}-ceph-export-task";
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
                for SUFFIX in ${builtins.concatStringsSep " " nodesIds}; do
                  ID="client.nfs-ganesha.$${CLUSTER}.$${SUFFIX}"
                  echo "Creating ID $ID"
                  ceph -c "$CEPH_CONFIG" auth get-or-create "$ID" \
                    mon 'allow r' \
                    mgr 'allow rw' \
                    osd "allow rw pool=$${RADOS_POOL} namespace=$${NFSNS}" >/dev/null || true
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

                EXPORT_JSON='${builtins.toJSON exportConf}'
                EXPORT_JSON="$${EXPORT_JSON/__SUBVOL_PATH__/$SUBVOL_PATH}"
                printf '%s' "$EXPORT_JSON" > /tmp/export_final.json

                echo "" > /tmp/empty-conf-nfs

                echo "Uploading empty conf to RADOS to reset any previous config..."

                rados -p .nfs --namespace $NFSNS put "conf-nfs.$CLUSTER"     /tmp/empty-conf-nfs || true

                ceph -c "$CEPH_CONFIG" nfs export apply "$CLUSTER" -i /tmp/export_final.json

                rados -p .nfs --namespace $NFSNS get "conf-nfs.$CLUSTER"     /tmp/conf-nfs                || true
                rados -p .nfs --namespace $NFSNS get "export-$EXPORT_ID"     /tmp/export-$$EXPORT_ID     || true

                echo "Fetching user_id from export-$EXPORT_ID"
                USER_ID="$(grep -oP 'user_id\s*=\s*"\K[^"]+' /tmp/export-$EXPORT_ID)"
                echo "User ID: $USER_ID"

                BASE_EXPORT_CONF='${baseExportConf}'
                BASE_EXPORT_CONF="$${BASE_EXPORT_CONF/__USER_ID__/$$USER_ID}"
                echo "Base export config:"
                echo "$BASE_EXPORT_CONF"
                printf '%s\n' "$BASE_EXPORT_CONF" > /tmp/export_base.conf

                cat /tmp/export_base.conf

                echo "Uploading updated configs to RADOS..."

                rados -p .nfs --namespace $NFSNS rm "export-0" || true
                rados -p .nfs --namespace $NFSNS put "export-0"     /tmp/export_base.conf

                echo "%url    \"rados://.nfs/$CLUSTER/export-0\"" >> /tmp/conf-nfs

                rados -p .nfs --namespace $NFSNS rm "conf-nfs.$CLUSTER" || true
                rados -p .nfs --namespace $NFSNS put "conf-nfs.$CLUSTER"     /tmp/conf-nfs
                rados -p .nfs --namespace $NFSNS get "conf-nfs.$CLUSTER"     /tmp/conf-nfs                || true

                echo "--------------------------- CONTENTS -----------------------------"
                cat /tmp/conf-nfs                || echo "(conf-nfs not found)"
                echo "------------------------------------------------------------------"
                cat "/tmp/export-$EXPORT_ID"     || echo "(export-$CLUSTER not found)"
                echo "------------------------------------------------------------------"
                cat /tmp/export_base.conf        || echo "(export_base.conf not found)"

                echo "Restarting NFS Ganesha grace..."
                for SUFFIX in ${builtins.concatStringsSep " " nodesIds}; do
                  ganesha-rados-grace --pool .nfs --ns "$NFSNS" add "$${CLUSTER}.$${SUFFIX}"   || true
                  ganesha-rados-grace --pool .nfs --ns "$NFSNS" start "$${CLUSTER}.$${SUFFIX}" || true
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
            ];
          }];
          volumes = [
            { name = "mon-endpoints"; configMap = { name = "rook-ceph-mon-endpoints"; items = [{ key = "data"; path = "mon-endpoints"; }]; }; }
            { name = "ceph-config"; emptyDir = { }; }
            { name = "ceph-admin-secret"; secret = { secretName = "rook-ceph-mon"; }; }
          ];
        };
      };
    };


    roles."${nfsName}-ganesha-conf-patch-role" = {
      metadata = { name = "${nfsName}-ganesha-conf-patch-role"; namespace = namespace; };
      rules = [
        {
          apiGroups = [ "" ];
          resources = [ "configmaps" ];
          verbs = [ "get" "list" "watch" "patch" ];
        }
        {
          apiGroups = [ "apps" ];
          resources = [ "deployments" ];
          verbs = [ "get" "list" "watch" "update" "patch" ];
        }
      ];
    };

    roleBindings."${nfsName}-ganesha-conf-patch-rb" = {
      metadata = { name = "${nfsName}-ganesha-conf-patch-rb"; namespace = namespace; };
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "Role"; name = "${nfsName}-ganesha-conf-patch-role"; };
      subjects = [{ kind = "ServiceAccount"; name = "rook-ceph-default"; namespace = namespace; }];
    };

    jobs."${nfsName}-ganesha-conf-patch" = {
      metadata = { name = "${nfsName}-ganesha-conf-patch"; namespace = namespace; };
      spec = {
        backoffLimit = 2;
        ttlSecondsAfterFinished = 3600;
        template.spec =
          let
            jsonPatchFor = nodeId: builtins.toJSON {
              data = { config = genGaneshaConfForNode nodeId; };
            };
            patchConfigMapFor = nodeId: ''
              echo "Starting patch routine for node ID ${nodeId}..."
              CM=""

              for i in {1..10}; do
                if [ -n "$CM" ]; then break; fi
                echo "Waiting for rook-ceph-nfs ConfigMap..."
                sleep 6
                CM="$(kubectl -n ${namespace} get cm -l app=rook-ceph-nfs,instance=${nodeId} -o name | grep -i rook-ceph | head -n1 || true)"
              done

              [ -z "$CM" ] && { echo "ERROR: rook-ceph ganesha ConfigMap not found"; exit 1; }

              echo "Patching $CM in ${namespace}..."

              kubectl -n ${namespace} patch "$CM" --type merge -p '${jsonPatchFor nodeId}'

            '';
            rolloutRestartFor = nodeId: ''
              echo "Restarting deployment for node ID ${nodeId}..."
              DEP="$(kubectl -n ${namespace} get deploy -l app=rook-ceph-nfs,instance=${nodeId} -o name | grep -i rook-ceph | head -n1 || true)"
              [ -z "$DEP" ] && { echo "WARN: deployment not found; skipping restart"; exit 0; }
              kubectl -n ${namespace} rollout restart "$DEP"
              kubectl -n ${namespace} rollout status  "$DEP"

            '';
          in
          {
            restartPolicy = "OnFailure";
            serviceAccountName = "rook-ceph-default";
            containers = [{
              name = "patch";
              image = "bitnami/kubectl:1.30";
              command = [ "/bin/bash" "-lc" ];
              args = [
                ''
                  set -euo pipefail
                  NS='${namespace}'
                  CLUSTER='${nfsName}'
                  CM=""

                  export PATH=/opt/bitnami/kubectl/bin:$PATH

                  ${builtins.concatStringsSep "" (map (nodeId: (patchConfigMapFor nodeId)) nodesIds)}

                  ${builtins.concatStringsSep "" (map (nodeId: (rolloutRestartFor nodeId)) nodesIds)}

                  echo "Done."
                ''
              ];
            }];
          };
      };
    };

  };
}
