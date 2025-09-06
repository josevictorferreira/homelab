{ lib, kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  boostrapDatabases = [
    "linkwarden"
    "open-webui"
  ];
in
{
  kubernetes = {
    helm.releases."postgresql" = {
      chart = kubenix.lib.helm.fetch
        {
          chartUrl = "oci://registry-1.docker.io/bitnamicharts/postgresql";
          chart = "postgresql";
          version = "16.5.2";
          sha256 = "sha256-iJ4clEnUshRP/s/qwkn/07JTSonGzMRV6XpMvwI9pAQ=";
        };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;
      values = {
        global.postgresql.auth = {
          database = "linkwarden";
          existingSecret = "postgresql-auth";
          secretKeys = {
            adminPasswordKey = "admin-password";
            userPasswordKey = "user-password";
            replicationPasswordKey = "replication-password";
          };
        };

        primary.persistence = {
          enabled = true;
          storageClass = "rook-ceph-block";
          reclaimPolicy = "Retain";
          accessModes = [ "ReadWriteOnce" ];
        };

        primary.service = kubenix.lib.plainServiceFor "postgresql";
      };
    };

    jobs."postgresql-bootstrap" = let
      createDbCommands = lib.concatStringsSep "\n" (map (db: "CREATE DATABASE IF NOT EXISTS ${db};") boostrapDatabases);
      in {
      metadata = {
        name = "postgresql-bootstrap";
        namespace = namespace;
      };
      spec.template.spec = {
        restartPolicy = "OnFailure";
        containers = [
          {
            name = "psql";
            image = "bitnami/postgresql:16";
            env = [
              {
                name = "PGPASSWORD";
                valueFrom.secretKeyRef = {
                  name = "postgresql-auth";
                  key = "admin-password";
                };
              }
            ];
            command = [ "sh" "-c" ];
            args = [''
              psql -h postgresql -U postgres -U postgres -d postgres <<'EOF'
              ${createDbCommands}
              EOF
            ''];
          }
        ];
      };
    };

  };
}
