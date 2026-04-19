{ kubenix, homelab, ... }:

let
  app = "tuwunel";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-env" = {
    metadata = { inherit namespace; };
    stringData = {
      "registration_token" = kubenix.lib.secretsFor "tuwunel_registration_token";
      "TUWUNEL_EMERGENCY_PASSWORD" = kubenix.lib.secretsFor "tuwunel_emergency_password";
    };
  };

  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData."tuwunel.toml" = ''
      [global]
      server_name = "josevictor.me"
      database_path = "/var/lib/tuwunel"
      address = "0.0.0.0"
      port = 8008
      allow_federation = false
      allow_registration = true
      new_user_displayname_suffix = ""

      allow_legacy_media = true
      url_preview_domain_contains_allowlist = ["*"]
      max_request_size = 52428800

      allow_local_presence = true
      allow_encryption = true

      [global.well_known]
      client = "https://matrix.josevictor.me"
      server = "matrix.josevictor.me:443"

      [rocksdb]
      write_buffer_size = 268435456
      max_background_flushes = 8
      max_background_compactions = 8
      compression = "zstd"

      [dns]
      query_over_tcp_only = true
      dns_cache_entries = 10000
      ip_lookup_strategy = "Ipv4Only"
    '';
  };
}
