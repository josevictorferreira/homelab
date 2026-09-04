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
    # Palette taken from foyer/poc.html (see foyer/.agents/specs/theming/plan.md §6).
    # HSL triples; foyer injects default-dark/default-light presets for the picker.
    theme = {
      background_color = "223 26 5";
      primary_color = "78 87 70";
      positive_color = "147 71 63";
      negative_color = "353 100 74";
      custom_css_file = "/app/config/custom.css";
    };
    modules.allow_hosts = [ "readeck.${namespace}.svc.cluster.local" ];
    pages = [
      {
        name = "Home";
        slug = "home";
        # Fixed-viewport dashboard reproducing foyer/poc.html; see
        # foyer/.agents/specs/board-layout/plan.md for the layout contract.
        layout = "board";
        masthead = [
          {
            type = "clock";
            hide_header = true;
          }
          {
            type = "markets";
            style = "ticker";
            hide_header = true;
            markets = [
              { name = "Bitcoin"; symbol = "BTC-USD"; icon = "₿"; color = "#f7931a"; }
              { name = "Dollar / Real"; symbol = "USDBRL=X"; icon = "R$"; color = "#2e9e5b"; }
              { name = "Kaspa"; symbol = "KAS-USD"; icon = "K"; color = "#49c8b0"; }
            ];
          }
        ];
        rail = [
          {
            type = "bookmarks";
            style = "tiles";
            hide_header = true;
            groups = [
              {
                title = "Daily";
                links = [
                  { title = "Home Assistant"; url = "https://home.josevictor.me"; icon = "sh:home-assistant"; color = "#41bdf5"; }
                  { title = "BookOrbit"; url = "https://bookorbit.josevictor.me"; icon = "mdi:book-open-variant"; color = "#b57cf5"; }
                  { title = "Readeck"; url = "https://readeck.josevictor.me"; icon = "sh:readeck"; color = "#ff7a3d"; }
                  { title = "SearXNG"; url = "https://searxng.josevictor.me"; icon = "sh:searxng"; color = "#3d7cf5"; }
                  { title = "Oratoria"; url = "https://oratoria.josevictor.me"; icon = "mdi:presentation"; color = "#ec5b9a"; }
                ];
              }
              {
                title = "Intel";
                links = [
                  { title = "Hermes"; url = "https://hermes.josevictor.me"; icon = "mdi:robot"; color = "#8fd13f"; }
                  { title = "Hindsight"; url = "https://hindsight.josevictor.me"; icon = "mdi:brain"; color = "#19b3a3"; }
                  { title = "Valoris"; url = "https://valoris.josevictor.me"; icon = "mdi:chart-line"; color = "#e0a81c"; }
                  { title = "Wealtho"; url = "https://wealtho.josevictor.me"; icon = "mdi:wallet"; color = "#2fb86a"; }
                  { title = "Poise"; url = "https://poise.josevictor.me"; icon = "mdi:hanger"; color = "#f06292"; }
                ];
              }
              {
                title = "Infra";
                links = [
                  { title = "Grafana"; url = "https://grafana.josevictor.me"; icon = "sh:grafana"; color = "#f46800"; }
                  { title = "Ceph"; url = "https://ceph.josevictor.me"; icon = "sh:ceph"; color = "#e9453d"; }
                  { title = "Keycloak"; url = "https://identity.josevictor.me"; icon = "sh:keycloak"; color = "#4d9de0"; }
                  { title = "SFTPGo"; url = "https://sftpgo.josevictor.me"; icon = "sh:sftpgo"; color = "#2ea3d9"; }
                  { title = "Immich"; url = "https://immich.josevictor.me"; icon = "sh:immich"; color = "#8e6cf7"; }
                ];
              }
            ];
          }
        ];
        columns = [
          {
            width = "288px";
            widgets = [
              {
                type = "calendar";
                title = "Calendar";
                style = "board";
                first_day_of_week = "monday";
              }
              {
                type = "weather";
                title = "Weather";
                style = "rows";
                grow = true;
                location = kubenix.lib.secretsFor "weather_location";
              }
            ];
          }
          {
            width = "1.45fr";
            widgets = [
              {
                type = "custom-api";
                title = "Reading queue";
                grow = true;
                cache = "1h";
                url = "http://readeck.${namespace}.svc.cluster.local:8000/api/bookmarks?limit=6&sort=-created";
                method = "GET";
                body_format = "json";
                headers.Authorization = "Bearer ${kubenix.lib.secretsFor "readeck_api_token"}";
                template = ''
                  {% set bookmarks = data.response.body|default([]) %}
                  <div class="panel-meta">{{ bookmarks|length }} saved <a href="https://readeck.josevictor.me" target="_blank" rel="noreferrer" aria-label="Open Readeck">↗</a></div>
                  <div class="read-cards">
                  {% for bookmark in bookmarks %}
                    {% set thumb = "" %}
                    {% if bookmark.resources and bookmark.resources.thumbnail %}{% set thumb = bookmark.resources.thumbnail.src|default("")|replace("http://readeck.apps.svc.cluster.local:8000", "https://readeck.josevictor.me") %}{% endif %}
                    {% set domain = (bookmark.url|default(""))|regex_replace("^https?://(www\\.)?", "")|regex_replace("/.*$", "") %}
                    {% set hue = (loop.index0 * 47) % 360 %}
                    {% set done = bookmark.is_archived|default(false) or (bookmark.read_progress|default(0)) >= 100 %}
                    <a class="read-card{% if done %} done{% endif %}" href="{{ bookmark.url }}" target="_blank" rel="noreferrer">
                      <div class="read-thumb" style="{% if thumb %}--g: url('{{ thumb }}'){% else %}--g: linear-gradient(145deg, hsl({{ hue }}, 45%, 38%), hsl({{ (hue + 30) % 360 }}, 45%, 14%)){% endif %}">{% if not thumb %}<b>{{ (bookmark.site_name|default(domain))|truncate(12) }}</b>{% endif %}<span class="read-age">{{ bookmark.created|default("")|relative_time|replace(" ago", "") }}</span></div>
                      <div class="read-body">
                        <div class="read-title">{{ bookmark.title|default(bookmark.url) }}</div>
                        <div class="read-meta"><span class="read-fav" style="--c: hsl({{ hue }}, 60%, 55%)"></span><span class="read-dom">{{ domain }}</span>{% if done %} · read{% endif %}</div>
                        {% if bookmark.labels %}<div class="read-tags">{% for label in bookmark.labels %}<span class="read-tag{% if label in ['ai', 'agentic ai'] %} hl{% endif %}">{{ label }}</span>{% endfor %}</div>{% endif %}
                      </div>
                    </a>
                  {% else %}
                    <span class="muted">No bookmarks available.</span>
                  {% endfor %}
                  </div>
                '';
              }
              {
                type = "videos";
                title = "New uploads";
                style = "grid";
                limit = 4;
                cache = "24h";
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
            width = "1fr";
            widgets = [
              {
                type = "group";
                title = "Pulse";
                layout = "tabs";
                grow = true;
                widgets = [
                  {
                    type = "hackernews";
                    title = "Hacker News";
                    style = "scoreboard";
                    cache = "2h";
                    limit = 15;
                  }
                  {
                    type = "lobsters";
                    title = "Lobsters";
                    style = "scoreboard";
                    cache = "2h";
                    limit = 15;
                  }
                  {
                    type = "reddit";
                    title = "r/selfhosted";
                    style = "scoreboard";
                    cache = "3h";
                    subreddit = "selfhosted";
                  }
                  {
                    type = "reddit";
                    title = "r/LocalLLaMA";
                    style = "scoreboard";
                    cache = "3h";
                    subreddit = "LocalLLaMA";
                  }
                  {
                    type = "reddit";
                    title = "r/functionalprint";
                    style = "scoreboard";
                    cache = "3h";
                    subreddit = "functionalprint";
                  }
                  {
                    type = "reddit";
                    title = "r/StableDiffusion";
                    style = "scoreboard";
                    cache = "3h";
                    subreddit = "StableDiffusion";
                  }
                ];
              }
            ];
          }
          {
            width = "0.92fr";
            widgets = [
              {
                type = "github-activity";
                title = "Your commits";
                style = "commits";
                limit = 4;
                author = "josevictorferreira";
                token = kubenix.lib.secretsFor "github_token";
              }
              {
                type = "releases";
                title = "Releases";
                style = "dots";
                grow = true;
                token = kubenix.lib.secretsFor "github_token";
                groups = [
                  { name = "cluster"; color = "#7dd3fc"; }
                  { name = "homelab"; color = "#8fd13f"; }
                  { name = "ai"; color = "#d97757"; }
                  { name = "desktop"; color = "#c4b5fd"; }
                ];
                repositories =
                  let
                    grouped = group: repos: map (repo: { inherit repo group; }) repos;
                  in
                  grouped "cluster" [
                    "rook/rook"
                    "cilium/cilium"
                    "prometheus/prometheus"
                    "cert-manager/cert-manager"
                    "fluxcd/flux2"
                    "k3s-io/k3s"
                    "kong/kong"
                    "keycloak/keycloak"
                    "hall/kubenix"
                    "imgproxy/imgproxy"
                  ]
                  ++ grouped "homelab" [
                    "glanceapp/glance"
                    "0xERR0R/blocky"
                    "n8n-io/n8n"
                    "grafana/grafana"
                    "linkwarden/linkwarden"
                    "drakkan/sftpgo"
                    "binwiederhier/ntfy"
                    "louislam/uptime-kuma"
                    "prowlarr/prowlarr"
                    "immich-app/immich"
                    "rishikanthc/scriberr"
                  ]
                  ++ grouped "ai" [
                    "open-webui/open-webui"
                    "comfyanonymous/ComfyUI"
                    "openclaw/openclaw"
                    "nousresearch/hermes-agent"
                    "vectorize-io/hindsight"
                    "anthropics/claude-code"
                    "sst/opencode"
                    "code-yeongyu/oh-my-opencode"
                    "Opencode-DCP/opencode-dynamic-context-pruning"
                    "NoeFabris/opencode-antigravity-auth"
                  ]
                  ++ grouped "desktop" [
                    "ruby/ruby"
                    "rails/rails"
                    "NixOS/nixpkgs"
                    "NixOS/nix"
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
                  ];
              }
            ];
          }
        ];
      }
    ];
  };
  # The two soft radial glows behind the board from foyer/poc.html. Radius,
  # panel color and fonts come from foyer's board layout CSS.
  customCss = ''
    body.board {
      background:
        radial-gradient(900px 600px at -5% -10%, hsla(78, 87%, 70%, 0.07), transparent 60%),
        radial-gradient(1000px 700px at 105% 110%, hsla(199, 95%, 74%, 0.07), transparent 60%),
        var(--color-background);
      background-attachment: fixed;
    }
  '';
in
{
  kubernetes.resources.configMaps.${app} = {
    metadata = {
      inherit namespace;
    };
    data."foyer.yml" = kubenix.lib.toYamlStr foyerConfig;
    data."custom.css" = customCss;
  };
}
