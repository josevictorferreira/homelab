{ homelab, kubenix, ... }:
let
  linkwardenTemplate = ''
    <ul class="list list-gap-10 collapsible-container" data-collapse-after="7">
      {{ range .JSON.Array "response" }}
        <li>
          {{ $title := .String "name" }}
          {{ if gt (len $title) 50 }}
            {{ $title = (slice $title 0 50) | printf "%s..." }}
          {{ end }}
          <a class="size-title-dynamic color-primary-if-not-visited"
             href="{{ .String "url" }}"
             target="_self"
             rel="noopener noreferrer">{{ $title }}</a>
          <ul class="list-horizontal-text">
            <li style="color: {{ .String "collection.color" }};">{{ .String "collection.name" }}</li>
            {{ $tags := .Array "tags" }}
            {{ range $index, $tag := $tags }}
              <li>{{ .String "name" }}</li>
            {{ end }}
          </ul>
        </li>
      {{ end }}
    </ul>
  '';
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
                cache = "1h";
                method = "GET";
                url = "http://${homelab.kubernetes.loadBalancer.services.linkwarden}/api/v1/links";
                headers = {
                  Authorization = "Bearer ${kubenix.lib.secretsFor "linkwarden_api_key"}+";
                };
                template = linkwardenTemplate;
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
                cache = "1h";
                channels = [
                  "UCOuGATIAbd2DvzJmUgXn2IQ" # Network Chuck
                  "UCHnyfMqiRRG1u-2MsSQLbXA" # Veritasium
                  "UCR-DXc1voovS8nhAvccRZhg" # Jeff Geerling
                  "UCpMcsdZf2KkAnfmxiq2MfMQ" # Arvin Ash
                  "UC9PIn6-XuRKZ5HmYeu46AIw" # Barely Sociable
                  "UCqnYRbOnwVAWU6plY904eAg" # VULDAR
                  "UC_zBdZ0_H_jn41FDRG7q4Tw" # Vimjoyer
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
                location = "${kubenix.lib.secretsFor "weather_location"}+";
                units = "metric";
                "hour-format" = "24h";
              }
              {
                type = "markets";
                cache = "1h";
                markets = [
                  {
                    symbol = "BTC-USD";
                    name = "Bitcoin";
                  }
                  {
                    symbol = "KAS-USD";
                    name = "Kaspa";
                  }
                  {
                    symbol = "USDBRL=X";
                    name = "Brazilian Real";
                  }
                ];
              }
              {
                type = "releases";
                cache = "1d";
                show-source-icon = true;
                repositories = [
                  # Homelab Apps
                  "glanceapp/glance"
                  "0xERR0R/blocky"
                  "n8n-io/n8n"
                  "open-webui/open-webui"
                  "grafana/grafana"
                  "linkwarden/linkwarden"
                  "rook/rook"
                  "drakkan/sftpgo"
                  "cilium/cilium"
                  "prometheus/prometheus"
                  "cert-manager/cert-manager"
                  "fluxcd/flux2"
                  "k3s-io/k3s"
                  "binwiederhier/ntfy"
                  "louislam/uptime-kuma"
                  "prowlarr/prowlarr"
                  "dockerhub:searxng/searxng"
                  "dockerhub:mjmeli/qbittorrent-port-forward-gluetun-server"
                  "immich-app/immich"
                  "rishikanthc/scriberr"
                  # Work Apps
                  "kong/kong"
                  "keycloak/keycloak"
                  "ruby/ruby"
                  "rails/rails"
                  # Daily Usage
                  "neovim/neovim"
                  "kovidgoyal/kitty"
                  "hyprwm/hyprland"
                  "hyprwm/hyprlock"
                  "derailed/k9s"
                  "davatorium/rofi"
                  "tmux/tmux"
                  "erikreider/swaynotificationcenter"
                  "weechat/weechat"
                  "alexays/waybar"
                  "jtheoof/swappy"
                  "sst/opencode"
                ];
              }
            ];
          }
        ];
      }
    ];
  };
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      configMaps."glance" = {
        metadata = {
          namespace = namespace;
        };
        data."glance.yml" = kubenix.lib.toYamlStr glanceConfig;
      };
    };
  };
}
