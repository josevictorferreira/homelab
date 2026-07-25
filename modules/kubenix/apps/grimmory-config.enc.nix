{ kubenix, homelab, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
  dbHost = "grimmory-mariadb.${namespace}.svc.cluster.local";
in
{
  kubernetes = {
    helm.releases."grimmory-mariadb" = {
      chart = kubenix.lib.helm.fetch {
        chartUrl = "oci://registry-1.docker.io/bitnamicharts/mariadb";
        chart = "mariadb";
        version = "22.0.0";
        sha256 = "sha256-/NZT384qHsdtl0FI4dg7D9tFqEf3O5mbm3Fvio1ZNT8=";
      };
      includeCRDs = true;
      noHooks = true;
      inherit namespace;
      values = {
        auth = {
          existingSecret = "grimmory-config";
          secretKeys = {
            rootPasswordKey = "mariadb-root-password";
            userPasswordKey = "mariadb-password";
          };
          database = "grimmory";
          username = "grimmory";
        };
        primary = {
          persistence = {
            enabled = true;
            storageClass = kubenix.lib.defaultStorageClass;
            size = "10Gi";
            accessModes = [ "ReadWriteOnce" ];
          };
          service = kubenix.lib.plainServiceFor "grimmory-mariadb";
          resources = {
            requests = {
              cpu = "250m";
              memory = "512Mi";
            };
            limits = {
              cpu = "1";
              memory = "1Gi";
            };
          };
        };
      };
    };

    resources.secrets."grimmory-config" = {
      type = "Opaque";
      metadata.name = "grimmory-config";
      metadata.namespace = namespace;
      stringData = {
        "DATABASE_PASSWORD" = kubenix.lib.secretsFor "grimmory_mariadb_password";
        "mariadb-root-password" = kubenix.lib.secretsFor "grimmory_mariadb_root_password";
        "mariadb-password" = kubenix.lib.secretsFor "grimmory_mariadb_password";
      };
    };
  };
}
