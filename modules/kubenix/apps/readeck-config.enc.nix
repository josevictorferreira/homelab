{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."readeck-env" = {
    metadata.namespace = namespace;
    stringData = {
      READECK_SECRET_KEY = kubenix.lib.secretsFor "readeck_secret_key";
      READECK_DATABASE_SOURCE = kubenix.lib.secretsFor "readeck_database_source";
    };
  };
}
