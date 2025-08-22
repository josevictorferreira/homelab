{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  nfsName = "homelab-nfs";
  pseudo = "/homelab";
  cephfs = "ceph-filesystem";
  cephfsPath = "/";
  allowedCIDRs = [ "10.10.10.0/24" ];
  lbIP = homelab.kubernetes.loadBalancer.services.nfs;
in
{
  kubernetes.resources = {
    cephnfs.${nfsName} = {
      namespace = namespace;
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

    services."nfs" = {
      metadata = {
        annotations = {
          "lbipam.cilium.io/ips" = lbIP;
          "lbipam.cilium.io/sharing-key" = "nfs";
        };
      };
      namespace = namespace;
      spec = {
        type = "LoadBalancer";
        externalTrafficPolicy = "Local";
        selector = {
          "app" = "rook-ceph-nfs";
          "ceph_daemon_type" = "nfs";
          "ceph_nfs" = "${nfsName}-a";
        };
        ports = [
          { name = "nfs"; port = 2049; targetPort = 2049; protocol = "TCP"; }
        ];
      };
    };

    configmaps."ceph-nfs-export-${nfsName}" = {
      namespace = namespace;
      data."export.json" = builtins.toJSON {
        path = cephfsPath;
        pseudo = pseudo;
        access_type = "RW";
        squash = "root_squash";
        security_label = false;
        protocols = [ 4 ];
        transports = [ "TCP" ];
        fsal = { name = "CEPH"; fs_name = cephfs; };
        clients = [
          { addresses = allowedCIDRs; access_type = "RW"; }
        ];
      };
    };

    jobs."ceph-nfs-export-apply-${nfsName}" = {
      namespace = namespace;
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
                CEPH_CONFIG="/etc/ceph/ceph.conf"
                MON_CONFIG="/etc/rook/mon-endpoints"
                KEYRING_FILE="/etc/ceph/keyring"
                # build ceph.conf from rook’s mon endpoints (same approach as toolbox)
                endpoints=$(cat \$\{MON_CONFIG\})
                mon_endpoints=$(echo "$endpoints" | sed 's/[a-z0-9_-]\+=//g')
                mkdir -p /etc/ceph
                cat > "$CEPH_CONFIG" <<EOF
                [global]
                mon_host = \$\{mon_endpoints\}
                [client.admin]
                keyring = \$\{KEYRING_FILE\}
                EOF
                ceph_secret=$(cat /var/lib/rook-ceph-mon/secret.keyring)
                username=$(cat /var/run/ceph/ceph-username)
                cat > "$KEYRING_FILE" <<EOF
                [\$\{username\}]
                key = \$\{ceph_secret\}
                EOF
                # idempotent: apply (create or update) the export JSON
                cluster='${nfsName}'
                ceph -c "$CEPH_CONFIG" nfs export apply "$cluster" -i /etc/ganesha/export.json
                # print final state
                jq -r .pseudo /etc/ganesha/export.json | xargs -I{} ceph -c "$CEPH_CONFIG" nfs export info "$cluster" {}
              ''
            ];
            volumeMounts = [
              { name = "mon-endpoints"; mountPath = "/etc/rook"; }
              { name = "ceph-config"; mountPath = "/etc/ceph"; }
              { name = "ceph-admin-secret"; mountPath = "/var/lib/rook-ceph-mon"; readOnly = true; }
              { name = "ceph-username"; mountPath = "/var/run/ceph"; readOnly = true; }
              { name = "export"; mountPath = "/etc/ganesha"; readOnly = true; }
            ];
          }];
          volumes = [
            { name = "mon-endpoints"; configMap = { name = "rook-ceph-mon-endpoints"; items = [{ key = "data"; path = "mon-endpoints"; }]; }; }
            { name = "ceph-config"; emptyDir = { }; }
            { name = "ceph-admin-secret"; secret = { secretName = "rook-ceph-mon"; items = [{ key = "ceph-secret"; path = "secret.keyring"; }]; }; }
            { name = "ceph-username"; secret = { secretName = "rook-ceph-mon"; items = [{ key = "ceph-username"; path = "ceph-username"; }]; }; }
            { name = "export"; configMap = { name = "ceph-nfs-export-${nfsName}"; }; }
          ];
        };
      };
    };
  };
}
