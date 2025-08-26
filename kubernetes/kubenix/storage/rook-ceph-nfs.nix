{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  nfsName = "homelab-nfs";
  pseudo = "/homelab";
  cephfs = "ceph-filesystem";
  allowedCIDRs = [ "10.10.10.0/24" ];
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
          { name = "nfs"; nodePort = 30325; port = 2049; targetPort = 2049; protocol = "TCP"; }
          { name = "nfs"; nodePort = 30326; port = 2049; targetPort = 2049; protocol = "UDP"; }
        ];
      };
    };

    configMaps = {
      "${nfsName}-export" = {
        metadata = {
          name = "${nfsName}-export";
          namespace = namespace;
        };
        data."export.json" = builtins.toJSON {
          export_id = 1;
          path = "/exported/path"; # Placeholder, will be replaced in job
          pseudo = pseudo;
          security_label = false;
          access_type = "RW";
          squash = "all";
          fsal = {
            name = "CEPH";
            fs_name = cephfs;
          };
          clients = [
            {
              addresses = allowedCIDRs;
              access_type = "RW";
              squash = "all";
              protocols = [ 4 ];
              sectype = [ "sys" ];
            }
          ];
        };
      };
      "${nfsName}-ganesha-config" = {
        metadata = {
          name = "${nfsName}-ganesha-config";
          namespace = namespace;
          labels = {
            app = "rook-ceph-nfs";
            rook_cluster = nfsName;
            ceph_daemon_type = "nfs";
          };
        };
        data = {
          "ganesha.conf" = ''
            NFS_CORE_PARAM {
              Enable_NLM = false;
              Enable_RQUOTA = false;
              Protocols = 4;
              Bind_addr = 0.0.0.0;
              NFS_Port = 2049;
            }

            MDCACHE { Dir_Chunk = 0; }

            NFSv4 {
              Graceless = true;
              Delegations = false;
              Minor_Versions = 0;
              Allow_Numeric_Owners = true;
              Only_Numeric_Owners = true;
            }

            NFS_KRB5 { Active_krb5 = false; }

            EXPORT_DEFAULTS {
              Attr_Expiration_Time = 0;
              Protocols = 4;
              Transports = TCP;
              Access_Type = RW;
              Squash = All;
              Manage_Gids = true;
              Anonymous_uid = 1000;
              Anonymous_gid = 100;
              SecType = "sys";
            }

            RADOS_KV {
              ceph_conf = "/etc/ceph/ceph.conf";
              userid = "nfs-ganesha.${nfsName}.a";
              nodeid = "${nfsName}.a";
              pool = ".nfs";
              namespace = "${nfsName}";
            }

            RADOS_URLS {
              ceph_conf = "/etc/ceph/ceph.conf";
              userid = "nfs-ganesha.${nfsName}.a";
              watch_url = "rados://.nfs/${nfsName}/conf-nfs.${nfsName}";
            }

            CEPH { Ceph_Conf = "/etc/ceph/ceph.conf"; }

            LOG {
              default_log_level = INFO;
              Components {
                ALL = INFO;
                FSAL = DEBUG;
                NFS4 = DEBUG;
                EXPORT = DEBUG;
                DISPATCH = DEBUG;
                RADOS = DEBUG;
              }
            }

            %url	"rados://.nfs/${nfsName}/conf-nfs.${nfsName}"

          '';
        };
      };
    };

    jobs."${nfsName}-export-apply" = {
      metadata = {
        name = "${nfsName}-export-apply";
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

                awk -v newval="$SUBVOL_PATH" '{
                  gsub(/"path":[[:space:]]*"[^"]*"/, "\"path\": \"" newval "\"");
                  print
                }' /etc/ganesha/export.json > /tmp/export.json

                ceph -c "$CEPH_CONFIG" nfs export apply "$cluster" -i /tmp/export.json

                ceph -c "$CEPH_CONFIG" nfs export info "$cluster" "${pseudo}"
              ''
            ];
            volumeMounts = [
              { name = "mon-endpoints"; mountPath = "/etc/rook"; }
              { name = "ceph-config"; mountPath = "/etc/ceph"; }
              { name = "ceph-admin-secret"; mountPath = "/var/lib/rook-ceph-mon"; readOnly = true; }
              { name = "${nfsName}-export"; mountPath = "/etc/ganesha"; readOnly = true; }
            ];
          }];
          volumes = [
            { name = "mon-endpoints"; configMap = { name = "rook-ceph-mon-endpoints"; items = [{ key = "data"; path = "mon-endpoints"; }]; }; }
            { name = "ceph-config"; emptyDir = { }; }
            { name = "ceph-admin-secret"; secret = { secretName = "rook-ceph-mon"; }; }
            { name = "${nfsName}-export"; configMap = { name = "${nfsName}-export"; }; }
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
                CM=""

                export PATH=/opt/bitnami/kubectl/bin:$PATH

                for i in {1..10}; do
                  if [ -n "$CM" ]; then break; fi
                  echo "Waiting for rook-ceph-nfs ConfigMap..."
                  sleep 6
                  CM="$(kubectl -n "$NS" get cm -l app=rook-ceph-nfs -o name | grep -i rook-ceph | head -n1 || true)"
                done

                [ -z "$CM" ] && { echo "ERROR: rook-ceph ganesha ConfigMap not found"; exit 1; }

                echo "Patching $CM in $NS"

                kubectl -n "$NS" patch "$CM" --type merge -p '{"data":{"config": "'"$(cat /tmp/ganesha.conf | sed 's/"/\\"/g' | tr '\n' ' ' | tr  '\t' ' ')"'"}}'

                DEP="$(kubectl -n "$NS" get deploy -l app=rook-ceph-nfs,rook_cluster="$CLUSTER",ceph_daemon_type=nfs -o name | head -n1 || true)"
                if [ -z "$DEP" ]; then
                  DEP="$(kubectl -n "$NS" get deploy -l app=rook-ceph-nfs -o name | head -n1 || true)"
                fi
                [ -z "$DEP" ] && { echo "WARN: deployment not found; skipping restart"; exit 0; }

                kubectl -n "$NS" rollout restart "$DEP"
                kubectl -n "$NS" rollout status  "$DEP"
                echo "Done."
              ''
            ];
            volumeMounts = [
              { name = "${nfsName}-ganesha-config"; mountPath = "/tmp"; readOnly = true; }
            ];
          }];
          volumes = [
            { name = "${nfsName}-ganesha-config"; configMap = { name = "${nfsName}-ganesha-config"; }; }
          ];
        };
      };
    };


  };
}
