{ homelab, kubenix, ... }:
let
  namespace = homelab.kubernetes.namespaces.applications;
  domain = kubenix.lib.domainFor "searxng";
  settings = {
    use_default_settings = true;
    general = {
      debug = false;
    };
    server = {
      base_url = "https://${domain}";
      limiter = false;
    };
    search = {
      safe_search = 0;
      default_lang = "en-US";
      favicon_resolver = "duckduckgo";
      autocomplete = "duckduckgo";
      formats = [ "html" "css" "json" ];
    };
    ui = {
      default_locale = "en-US";
      hotkeys = "vim";
    };
    redis = {
      url = "redis://:${kubenix.lib.secretsInlineFor "redis_password"}@redis-headless:6379/2";
    };
  };
  limiter = ''
    [botdetection]
    ipv4_prefix = 32
    ipv6_prefix = 48
    trusted_proxies = [
      '10.10.10.0/24',
      '10.42.0.0/16',
      '10.43.0.0/16',
      '10.0.0.0/8'
    ]

    [botdetection.ip_limit]
    filter_link_local = false
    link_token = false

    [botdetection.ip_lists]
    block_ip = []
    pass_ip = []
    pass_searxng_org = true
  '';
in
{
  kubernetes = {
    resources = {
      configMaps."searxng-config" = {
        metadata = {
          name = "searxng-config";
          namespace = namespace;
        };
        data = {
          "settings.yml" = kubenix.lib.toYamlStr settings;
          "limiter.toml" = limiter;
        };
      };
    };
  };
}
