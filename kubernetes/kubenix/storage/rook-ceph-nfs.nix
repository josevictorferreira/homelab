{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  nfsName = "homelab-nfs";
  pseudo = "/homelab";
  cephfs = "ceph-filesystem";
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
          active = 1;
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
        loadBalancerIP = lbIP;
        externalTrafficPolicy = "Cluster";
        selector = {
          app = "rook-ceph-nfs";
          ceph_daemon_type = "nfs";
        };
        ports = [
          { name = "nfs-tcp"; port = 2049; targetPort = 2049; protocol = "TCP"; }
        ];
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
                SUBVOL_GROUP='nfs-exports'
                SUBVOL_NAME='${nfsName}'
                FS='${cephfs}'

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
                ceph -c "$CEPH_CONFIG" mgr module enable volumes || true

                ceph -c "$CEPH_CONFIG" fs subvolumegroup create "$FS" "$SUBVOL_GROUP" || true
                ceph -c "$CEPH_CONFIG" fs subvolume create "$FS" "$SUBVOL_NAME" \
                  --group_name "$SUBVOL_GROUP" --size 0 --uid 2002 --gid 2002 --mode 2775 || true

                SUBVOL_PATH="$(ceph -c "$CEPH_CONFIG" fs subvolume getpath "$FS" "$SUBVOL_NAME" --group_name "$SUBVOL_GROUP")"

                cluster='${nfsName}'

                cat > /tmp/export.json <<JSON
                {
                  "export_id": 1,
                  "path": "$SUBVOL_PATH",
                  "pseudo": "${pseudo}",
                  "access_type": "RW",
                  "squash": "no_root_squash",
                  "protocols": [4],
                  "transports": ["TCP"],
                  "fsal": {
                    "name": "CEPH",
                    "fs_name": "${cephfs}"
                  },
                  "clients": [
                    {
                      "addresses": $(printf '%s\n' '${builtins.toJSON allowedCIDRs}'),
                      "access_type": "RW",
                      "squash": "no_root_squash"
                    }
                  ]
                }
                JSON

                ceph -c "$CEPH_CONFIG" nfs export apply "$cluster" -i /tmp/export.json

                # Show the information about the NFS export
                ceph -c "$CEPH_CONFIG" nfs export info "$cluster" "${pseudo}"

                echo "All exports for cluster $cluster:"
                ceph -c "$CEPH_CONFIG" nfs export ls "$cluster"
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

    roles."patch-ganesha-cm-role" = {
      metadata = { name = "patch-ganesha-cm-role"; namespace = namespace; };
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

    roleBindings."patch-ganesha-cm-rb" = {
      metadata = { name = "patch-ganesha-cm-rb"; namespace = namespace; };
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "Role"; name = "patch-ganesha-cm-role"; };
      subjects = [{ kind = "ServiceAccount"; name = "rook-ceph-default"; namespace = namespace; }];
    };

    jobs."patch-ganesha-cm-${nfsName}" = {
      metadata = { name = "patch-ganesha-cm-${nfsName}"; namespace = namespace; };
      spec = {
        backoffLimit = 2;
        ttlSecondsAfterFinished = 3600;
        template.spec = {
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

                export PATH=/opt/bitnami/kubectl/bin:$PATH

                CM="$(kubectl -n "$NS" get cm -l app=rook-ceph-nfs -o name | grep -i rook-ceph | head -n1 || true)"

                [ -z "$CM" ] && { echo "ERROR: rook-ceph ganesha ConfigMap not found"; exit 1; }

                echo "Patching $CM in $NS"

                tmp="$(mktemp)"
                kubectl -n "$NS" get "$CM" -o jsonpath='{.data.config}' > "$tmp"

                cat > "$tmp.new" <<'GANESHA_EOF'
                NFS_CORE_PARAM {
                    Enable_NLM = false;
                    Enable_RQUOTA = false;
                    Protocols = 4;
                    NFS_Port = 2049;
                    HAProxy_Hosts = 127.0.0.1;
                    _9P_TCP_Port = 564;
                    _9P_RDMA_Port = 5640;
                    Heartbeat_Freq = 0;
                    Recovery_Backend = rados_cluster;
                    Minor_Versions = 0, 1, 2;
                }

                NFSv4 {
                    Graceless = true;
                    Minor_Versions = 1, 2;
                    RecoveryRoot = "/var/lib/nfs/ganesha";
                    IdmapConf = "/etc/idmapd.conf";
                }

                NFS_KRB5 {
                    Active_krb5 = false;
                }

                EXPORT_DEFAULTS {
                    Protocols = 4;
                    Transports = TCP;
                    Access_Type = RW;
                    Attr_Expiration_Time = 0;
                    Squash = no_root_squash;
                    Manage_Gids = false;
                }

                %url    rados://rook-ceph/${namespace}/ceph-nfs.${nfsName}

                LOG {
                    default_log_level = WARN;
                    Components {
                        ALL = WARN;
                    }
                }
                GANESHA_EOF

                NEW_CONFIG="$(cat "$tmp.new")"

                kubectl -n "$NS" patch "$CM" --type='merge' -p "{\"data\":{\"config\":\"$NEW_CONFIG\"}}"
              
                echo "ConfigMap patched."

                kubectl -n "$NS" rollout restart "$DEP"
                kubectl -n "$NS" rollout status  "$DEP"
                echo "Done."
              ''
            ];
          }];
        };
      };
    };


  };
}
