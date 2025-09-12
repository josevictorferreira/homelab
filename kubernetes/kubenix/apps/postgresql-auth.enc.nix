{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  mkDatasource = database: {
    name = "app-postgres";
    uid = "ds-app-postgres";
    access = "proxy";
    url = "postgresql-hl:5432";
    database = database;
    user = "postgres";
    isDefault = false;
    editable = false;
    jsonData = {
      sslMode = "disable";
      postgresVersion = 1700;
      timescaledb = false;
    };
    secureJsonData = {
      password = kubenix.lib.secretsInlineFor "postgresql_admin_password";
    };
  };
  grafanaDatasource = {
    apiVersion = 1;
    datasources = map mkDatasource homelab.kubernetes.databases.postgres;
  };
in
{
  kubernetes = {
    resources = {
      secrets = {
        "postgresql-auth" = {
          type = "Opaque";
          metadata.name = "postgresql-auth";
          metadata.namespace = namespace;
          stringData = {
            "admin-password" = kubenix.lib.secretsFor "postgresql_admin_password";
            "user-password" = kubenix.lib.secretsFor "postgresql_user_password";
            "replication-password" = kubenix.lib.secretsFor "postgresql_replication_password";
          };
        };
        "grafana-ds-postgres" = {
          type = "Opaque";
          metadata = {
            name = "grafana-ds-postgres";
            namespace = namespace;
            labels.grafana_datasource = "1";
          };
          stringData = {
            "postgresql-datasource.yaml" = kubenix.lib.toYamlStr grafanaDatasource;
          };
        };
      };
    };
  };
}
