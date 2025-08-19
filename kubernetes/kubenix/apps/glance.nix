{ lib, kubenix, labConfig, ... }:

let
  glanceConfig = {
    theme = {
      "background-color" = "50 1 6";
      "primary-color" = "24 97 58";
      "negative-color" = "209 88 54";
    };

    pages = [
      {
        name = "Home";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "calendar";
                "first-day-of-week" = "monday";
              }
              {
                type = "custom-api";
                title = "Bookmarks";
                cache = "1m";
                method = "GET";
                url = "http://${labConfig.kubernetes.loadBalancer.services.linkwarden}/api/v1/links";
                headers = {
                  Authorization = "Bearer RANDOM_TOKEN";
                };
                template = ''
                  <ul class="list list-gap-10 collapsible-container" data-collapse-after="7">
                    {{`{{ range .JSON.Array "response" }}`}}
                      <li>
                        {{`{{ $title := .String "name" }}`}}
                        {{`{{ if gt (len $title) 50 }}`}}
                          {{`{{ $title = (slice $title 0 50) | printf "%s..." }}`}}
                        {{`{{ end }}`}}
                        <a class="size-title-dynamic color-primary-if-not-visited" href="{{`{{ .String "url" }}`}}" target="_self" rel="noopener noreferrer">{{`{{ $title }}`}}</a>
                        <ul class="list-horizontal-text">
                          <li style="color: {{`{{ .String "collection.color" }}`}};">{{`{{ .String "collection.name" }}`}}</li>
                          {{`{{ $tags := .Array "tags" }}`}}
                          {{`{{ range $index, $tag := $tags }}`}}
                            <li>{{`{{ .String "name" }}`}} </li>
                          {{`{{ end }}`}}
                        </ul>
                      </li>
                    {{`{{ end }}`}}
                  </ul>
                '';
              }
            ];
          }
          {
            size = "full";
            widgets = [
              {
                type = "group";
                widgets = [
                  { type = "hacker-news"; }
                  { type = "lobsters"; }
                ];
              }
              {
                type = "videos";
                channels = [
                  "UCOuGATIAbd2DvzJmUgXn2IQ" # Network Chuck
                  "UCHnyfMqiRRG1u-2MsSQLbXA" # Veritasium
                  "UCR-DXc1voovS8nhAvccRZhg" # Jeff Geerling
                  "UCpMcsdZf2KkAnfmxiq2MfMQ" # Arvin Ash
                  "UC9PIn6-XuRKZ5HmYeu46AIw" # Barely Sociable
                  "UCqnYRbOnwVAWU6plY904eAg" # VULDAR
                ];
              }
              {
                type = "group";
                widgets = [
                  {
                    type = "reddit";
                    subreddit = "selfhosted";
                    "show-thumbnails" = true;
                  }
                  {
                    type = "reddit";
                    subreddit = "minilab";
                    "show-thumbnails" = true;
                  }
                  {
                    type = "reddit";
                    subreddit = "homelab";
                    "show-thumbnails" = true;
                  }
                ];
              }
            ];
          }
          {
            size = "small";
            widgets = [
              {
                type = "weather";
                location = "Londrina, Paraná, Brazil";
                units = "metric";
                "hour-format" = "24h";
              }
              {
                type = "markets";
                markets = [
                  { symbol = "BTC-USD"; name = "Bitcoin"; }
                  { symbol = "KAS-USD"; name = "Kaspa"; }
                  { symbol = "USDBRL=X"; name = "Brazilian Real"; }
                ];
              }
              {
                type = "releases";
                cache = "1d";
                repositories = [
                  "glanceapp/glance"
                  "pi-hole/pi-hole"
                  "grafana/grafana"
                  "linkwarden/linkwarden"
                  "drakkan/sftpgo"
                  "binwiederhier/ntfy"
                  "louislam/uptime-kuma"
                  "prowlarr/prowlarr"
                ];
              }
            ];
          }
        ];
      }
    ];
  };
in
{
  submodules.instances.glance = {
    submodule = "release";
    args = {
      namespace = "apps";
      image = {
        repository = "glanceapp/glance";
        tag = "v0.8.4@sha256:6df86a7e8868d1eda21f35205134b1962c422957e42a0c44d4717c8e8f741b1a";
        pullPolicy = "IfNotPresent";
      };
      subdomain = "glance";
      port = 8080;
      values = {
        service.main = {
          type = "LoadBalancer";
          annotations = kubenix.lib.serviceIpFor "glance";
          ports = {
            http = {
              enabled = true;
              port = 8080;
            };
          };
        };
        configMaps.config = {
          enabled = true;
          data."glance.yml" = lib.generators.toYAML { } glanceConfig;
        };
        persistence.glance = {
          type = "configMap";
          name = "glance";
          items = [
            {
              key = "glance.yml";
              path = "glance.yml";
            }
          ];
          advancedMounts = {
            main.main = [
              {
                path = "/app/config/glance.yml";
                readOnly = true;
                subPath = "glance.yml";
              }
            ];
          };
        };
      };
    };
  };
}
