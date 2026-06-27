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
      image_proxy = true;
    };
    search = {
      safe_search = 0;
      default_lang = "en";
      autocomplete = "swisscows";
      formats = [
        "html"
        "json"
      ];
    };
    ui = {
      default_locale = "en";
      hotkeys = "vim";
      infinite_scroll = true;
    };
    redis = {
      url = "redis://:${kubenix.lib.secretsInlineFor "redis_password"}@redis-headless:6379/2";
    };
    valkey = {
      url = "redis://:${kubenix.lib.secretsInlineFor "redis_password"}@redis-headless:6379/2";
    };
    engines = [
      {
        name = "tavily";
        engine = "tavily";
        api_key = kubenix.lib.secretsFor "tavily_api_key";
        inactive = false;
      }
      {
        name = "github";
        disabled = false;
        weight = 3.0;
      }
      {
        name = "github code";
        disabled = false;
        weight = 3.0;
      }
      {
        name = "annas archive";
        disabled = false;
      }
      {
        name = "apple app store";
        disabled = false;
      }
      {
        name = "nixos wiki";
        disabled = false;
      }
      {
        name = "bing";
        disabled = false;
      }
      {
        name = "boardreader";
        disabled = false;
      }
      {
        name = "btdigg";
        disabled = false;
      }
      {
        name = "crossref";
        disabled = false;
      }
      {
        name = "crowdview";
        disabled = false;
      }
      {
        name = "encyclosearch";
        disabled = false;
      }
      {
        name = "apple maps";
        disabled = false;
      }
      {
        name = "fynd";
        disabled = false;
      }
      {
        name = "codeberg";
        disabled = false;
      }
      {
        name = "gitea.com";
        disabled = false;
      }
      {
        name = "gmx";
        disabled = false;
      }
      {
        name = "goodreads";
        disabled = false;
      }
      {
        name = "google play apps";
        disabled = false;
      }
      {
        name = "material icons";
        disabled = false;
      }
      {
        name = "hackernews";
        disabled = false;
      }
      {
        name = "imdb";
        disabled = false;
      }
      {
        name = "imgur";
        disabled = false;
      }
      {
        name = "library genesis";
        disabled = false;
      }
      {
        name = "lobste.rs";
        disabled = false;
      }
      {
        name = "nyaa";
        disabled = false;
      }
      {
        name = "openlibrary";
        disabled = false;
      }
      {
        name = "openrepos";
        disabled = false;
      }
      {
        name = "qwant";
        disabled = false;
      }
      {
        name = "qwant images";
        disabled = false;
      }
      {
        name = "reddit";
        disabled = false;
        weight = 3.0;
      }
      {
        name = "rottentomatoes";
        disabled = false;
      }
      {
        name = "searchmysite";
        disabled = false;
      }
      {
        name = "selfhst icons";
        disabled = false;
      }
      {
        name = "steam";
        disabled = false;
      }
      {
        name = "tokyotoshokan";
        disabled = false;
      }
      {
        name = "tmdb";
        disabled = false;
      }
      {
        name = "wikispecies";
        disabled = false;
      }
      {
        name = "1337x";
        disabled = false;
      }
      {
        name = "artic";
        disabled = true;
      }
      {
        name = "bandcamp";
        disabled = true;
      }
      {
        name = "wikipedia";
        disabled = true;
      }
      {
        name = "bing news";
        disabled = true;
      }
      {
        name = "openverse";
        disabled = true;
      }
      {
        name = "chefkoch";
        disabled = true;
      }
      {
        name = "wikidata";
        disabled = true;
      }
      {
        name = "gentoo";
        disabled = true;
      }
      {
        name = "hoogle";
        disabled = true;
      }
      {
        name = "lingva";
        disabled = true;
      }
      {
        name = "mdn";
        disabled = true;
      }
      {
        name = "mixcloud";
        disabled = true;
      }
      {
        name = "pypi";
        disabled = true;
      }
      {
        name = "soundcloud";
        disabled = true;
      }
      {
        name = "stackoverflow";
        disabled = true;
      }
      {
        name = "askubuntu";
        disabled = true;
      }
      {
        name = "superuser";
        disabled = true;
      }
      {
        name = "startpage";
        disabled = true;
      }
      {
        name = "startpage images";
        disabled = true;
      }
      {
        name = "wikicommons.audio";
        disabled = true;
      }
      {
        name = "mymemory translated";
        disabled = true;
      }
      {
        name = "brave";
        disabled = true;
      }
    ];
    default_doi_resolver = "oadoi.org";
    plugins = {
      "searx.plugins.oa_doi_rewrite.SXNGPlugin".active = true;
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
          inherit namespace;
        };
        data = {
          "settings.yml" = kubenix.lib.toYamlStr settings;
          "limiter.toml" = limiter;
        };
      };

      secrets."searxng-secret" = {
        metadata = {
          name = "searxng-secret";
          inherit namespace;
        };
        stringData = {
          "SEARXNG_HOSTNAME" = domain;
          "SEARXNG_SECRET" = kubenix.lib.secretsFor "searxng_secret_key";
          "TAVILY_API_KEY" = kubenix.lib.secretsFor "tavily_api_key";
        };
      };
    };
  };
}
