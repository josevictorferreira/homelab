{ homelab, kubenix, ... }:

let
  app = "foyer";
  namespace = homelab.kubernetes.namespaces.applications;
  port = 8080;
  foyerConfig = {
    server = {
      host = "0.0.0.0";
      inherit port;
    };
    theme.name = "glance-home";
    modules.allow_hosts = [ "readeck.${namespace}.svc.cluster.local" ];
    pages = [
      {
        name = "Home";
        slug = "home";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "calendar";
                title = "Calendar";
                first_day_of_week = "monday";
              }
              {
                type = "custom-api";
                title = "Bookmarks";
                cache = "1h";
                url = "http://readeck.${namespace}.svc.cluster.local:8000/api/bookmarks?limit=15";
                method = "GET";
                body_format = "json";
                headers.Authorization = "Bearer ${kubenix.lib.secretsFor "readeck_api_token"}";
                template = ''
                  {% set bookmarks = data.response.body|default([]) %}
                  {% if bookmarks|length > 7 %}<input class="collapse-toggle" type="checkbox" id="collapse-{{ widget.id }}">{% endif %}
                  <ul class="list list-gap-10">
                  {% for bookmark in bookmarks %}
                    <li{% if loop.index > 7 %} class="collapsed"{% endif %}>
                      <div class="flex gap-10">
                        {% set thumb = "" %}
                        {% if bookmark.resources and bookmark.resources.thumbnail %}{% set thumb = bookmark.resources.thumbnail.src|default("")|replace("http://readeck.apps.svc.cluster.local:8000", "https://readeck.josevictor.me") %}{% endif %}
                        {% if thumb %}<img class="forum-post-list-thumbnail thumbnail" src="{{ thumb }}" alt="" loading="lazy">{% endif %}
                        <div class="grow min-width-0">
                          <a href="{{ bookmark.url }}" class="size-title-dynamic color-primary-if-not-visited">{{ bookmark.title|default(bookmark.url)|truncate(50) }}</a>
                          <ul class="list-horizontal-text">
                            <li>{{ bookmark.created|default("")|relative_time }}</li>
                            {% if bookmark.site_name %}<li class="shrink-0">{{ bookmark.site_name }}</li>{% endif %}
                            {% for label in bookmark.labels|default([]) %}
                              <li class="shrink-0" style="background-color: hsl({{ (loop.index0 * 30) % 360 }}, 50%, 20%); color: hsl({{ (loop.index0 * 30) % 360 }}, 60%, 70%); padding: 1px 6px; border-radius: 4px;">{{ label }}</li>
                            {% endfor %}
                          </ul>
                        </div>
                      </div>
                    </li>
                  {% else %}
                    <li class="muted">No bookmarks available.</li>
                  {% endfor %}
                  </ul>
                  {% if bookmarks|length > 7 %}<label class="collapse-label" for="collapse-{{ widget.id }}"><span class="more">Show more</span><span class="less">Show less</span><span class="chevron">⌄</span></label>{% endif %}
                '';
              }
            ];
          }
          {
            size = "full";
            widgets = [
              {
                type = "bookmarks";
                title = "Homelab";
                groups = [
                  {
                    color = "24 97 58";
                    same_tab = false;
                    links = [
                      { title = "Home Assistant"; url = "https://home.josevictor.me"; icon = "sh:home-assistant"; }
                      { title = "BookOrbit"; url = "https://bookorbit.josevictor.me"; icon = "mdi:book-open-variant"; }
                      { title = "Readeck"; url = "https://readeck.josevictor.me"; icon = "sh:readeck"; }
                      { title = "SearXNG"; url = "https://searxng.josevictor.me"; icon = "sh:searxng"; }
                      { title = "Oratoria"; url = "https://oratoria.josevictor.me"; icon = "mdi:presentation"; }
                    ];
                  }
                  {
                    color = "280 60 60";
                    same_tab = false;
                    links = [
                      { title = "Hermes"; url = "https://hermes.josevictor.me"; icon = "mdi:robot"; }
                      { title = "Hindsight"; url = "https://hindsight.josevictor.me"; icon = "mdi:brain"; }
                      { title = "Valoris"; url = "https://valoris.josevictor.me"; icon = "mdi:chart-line"; }
                      { title = "Wealtho"; url = "https://wealtho.josevictor.me"; icon = "mdi:wallet"; }
                      { title = "Poise"; url = "https://poise.josevictor.me"; icon = "mdi:hanger"; }
                    ];
                  }
                  {
                    color = "209 88 54";
                    same_tab = false;
                    links = [
                      { title = "Grafana"; url = "https://grafana.josevictor.me"; icon = "sh:grafana"; }
                      { title = "Ceph"; url = "https://ceph.josevictor.me"; icon = "sh:ceph"; }
                      { title = "Keycloak"; url = "https://identity.josevictor.me"; icon = "sh:keycloak"; }
                      { title = "SFTPGo"; url = "https://sftpgo.josevictor.me"; icon = "sh:sftpgo"; }
                      { title = "Immich"; url = "https://immich.josevictor.me"; icon = "sh:immich"; }
                    ];
                  }
                ];
              }
              {
                type = "group";
                layout = "tabs";
                widgets = [
                  {
                    type = "hackernews";
                    title = "Hacker News";
                    limit = 15;
                    collapse_after = 5;
                  }
                  {
                    type = "lobsters";
                    title = "Lobsters";
                    limit = 15;
                    collapse_after = 5;
                  }
                  {
                    type = "reddit";
                    title = "r/selfhosted";
                    subreddit = "selfhosted";
                    show_thumbnails = true;
                    collapse_after = 5;
                  }
                  {
                    type = "reddit";
                    title = "r/LocalLLaMA";
                    subreddit = "LocalLLaMA";
                    show_thumbnails = true;
                    collapse_after = 5;
                  }
                  {
                    type = "reddit";
                    title = "r/functionalprint";
                    subreddit = "functionalprint";
                    show_thumbnails = true;
                    collapse_after = 5;
                  }
                  {
                    type = "reddit";
                    title = "r/StableDiffusion";
                    subreddit = "StableDiffusion";
                    show_thumbnails = true;
                    collapse_after = 5;
                  }
                ];
              }
              {
                type = "videos";
                title = "Videos";
                style = "horizontal-cards";
                limit = 25;
                channels = [
                  "UCOuGATIAbd2DvzJmUgXn2IQ"
                  "UCHnyfMqiRRG1u-2MsSQLbXA"
                  "UCR-DXc1voovS8nhAvccRZhg"
                  "UCpMcsdZf2KkAnfmxiq2MfMQ"
                  "UC9PIn6-XuRKZ5HmYeu46AIw"
                  "UCqnYRbOnwVAWU6plY904eAg"
                  "UC_zBdZ0_H_jn41FDRG7q4Tw"
                ];
              }
            ];
          }
          {
            size = "small";
            widgets = [
              {
                type = "weather";
                title = "Weather Forecast";
                location = kubenix.lib.secretsFor "weather_location";
              }
              {
                type = "github-activity";
                title = "Recent GitHub Repositories";
                author = "josevictorferreira";
                token = kubenix.lib.secretsFor "github_token";
              }
              {
                type = "markets";
                title = "Markets";
                markets = [
                  { name = "Bitcoin"; symbol = "BTC-USD"; }
                  { name = "Kaspa"; symbol = "KAS-USD"; }
                  { name = "Brazilian Real"; symbol = "USDBRL=X"; }
                ];
              }
              {
                type = "releases";
                title = "Releases";
                token = kubenix.lib.secretsFor "github_token";
                repositories = [
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
                  "immich-app/immich"
                  "rishikanthc/scriberr"
                  "comfyanonymous/ComfyUI"
                  "imgproxy/imgproxy"
                  "openclaw/openclaw"
                  "nousresearch/hermes-agent"
                  "vectorize-io/hindsight"
                  "kong/kong"
                  "keycloak/keycloak"
                  "ruby/ruby"
                  "rails/rails"
                  "anthropics/claude-code"
                  "NixOS/nixpkgs"
                  "NixOS/nix"
                  "hall/kubenix"
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
                  "code-yeongyu/oh-my-opencode"
                  "Opencode-DCP/opencode-dynamic-context-pruning"
                  "NoeFabris/opencode-antigravity-auth"
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
  kubernetes.resources.configMaps.${app} = {
    metadata = {
      inherit namespace;
    };
    data."foyer.yml" = kubenix.lib.toYamlStr foyerConfig;
  };
}
