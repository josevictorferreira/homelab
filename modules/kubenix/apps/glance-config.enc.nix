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

  weatherSevenDayTemplate = ''
    {{/* THESE VALUES CAN BE CHANGED BY ADDING AN ENTRY TO THE OPTIONS SECTION */}}
      {{ $temp_unit := .Options.StringOr "temp_unit" "celsius" }}
      {{ $weekend_color := .Options.StringOr "weekend_color" "var(--color-separator)" }}
      {{ $overlay_color := .Options.StringOr "overlay_color" "hsl(var(--bghs), var(--bgl), 50%)" }}
      {{/* the following variables define the coloring of the sunny/cloudy/etc. weather icons*/}}
        {{ $color_clear := .Options.StringOr "color_clear" "var(--color-text-highlight)" }}
        {{ $color_partly := .Options.StringOr "color_partly" "var(--color-text-highlight)"}}
        {{ $color_cloud := .Options.StringOr "color_cloud" "var(--color-text-highlight)"}}
        {{ $color_smog := .Options.StringOr "color_smog" "var(--color-text-highlight)"}}
        {{ $color_drizzle := .Options.StringOr "color_drizzle" "var(--color-text-highlight)"}}
        {{ $color_rain := .Options.StringOr "color_rain" "var(--color-text-highlight)"}}
        {{ $color_freezing_rain := .Options.StringOr "color_freezing_rain" "var(--color-text-highlight)"}}
        {{ $color_snow := .Options.StringOr "color_snow" "var(--color-text-highlight)F"}}
        {{ $color_thunderstorm := .Options.StringOr "color_thunderstorm" "var(--color-text-highlight)"}}
        {{ $color_other := .Options.StringOr "color_other" "var(--color-text-highlight)"}}
      {{/* the following variables define the temperature gradient coloring for the daily rectangles */}}
      {{ $color_red := .Options.StringOr "color_red" "var(--color-negative)" }}  
      {{ $color_yellow := .Options.StringOr "color_yellow" "var(--color-text-subdue)" }}
      {{ $color_blue := .Options.StringOr "color_blue" "var(--color-positive)" }}
      {{ $color_white := .Options.StringOr "color_white" "var(--color-text-highlight)" }}
      {{ $temp_red := .Options.FloatOr "temp_red" 27 }}
      {{ $temp_yellow := .Options.FloatOr "temp_yellow" 20 }}
      {{ $temp_blue := .Options.FloatOr "temp_blue" 10.0 }}
      {{ $temp_white := .Options.FloatOr "temp_white" 0 }}
      {{ if eq $temp_unit "fahrenheit" }}
        {{ $temp_red = .Options.FloatOr "temp_red" 80.0 }}
        {{ $temp_yellow = .Options.FloatOr "temp_yellow" 70.0 }}
        {{ $temp_blue = .Options.FloatOr "temp_blue" 50.0 }}
        {{ $temp_white = .Options.FloatOr "temp_white" 30.0 }}
      {{end}}

    {{/* Request 1: get latitude and longitude for user's city */}}
    {{ $location_string := replaceAll " " "%20" (.Options.StringOr "location" "") }}
    {{ $url1 := printf "https://geocoding-api.open-meteo.com/v1/search?name=%s&count=20&language=en&format=json" $location_string }}
    {{ $req1 := newRequest $url1 | getResponse }}
    {{ $latitude := $req1.JSON.String "results.0.latitude" }}
    {{ $longitude := $req1.JSON.String "results.0.longitude" }}

    {{/* Request 2: get daily weather forecast based on latitude and longitude */}}
    {{ $url2 := printf "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&temperature_unit=%s&daily=temperature_2m_max,temperature_2m_min,weathercode&timezone=America/New_York" $latitude $longitude $temp_unit}}    
    {{ $req2 := newRequest $url2 | getResponse }}

    <div style="display: flex; justify-content: center; align-items: center; flex-direction: column;">

      {{/* Show abbreivated day of week */}}
      {{ $dates := $req2.JSON.Array "daily.time" }}
      <div style="position: relative; width: 100%; height: 25px;">  
        {{ range $index, $date := $dates }}

          {{/* prepare to print M Tu W Th F Sa Su */}}
          {{ $dateString := .String "" }}
          {{ $parsedDate := $dateString | parseTime "DateOnly" }}
          {{ $dayOfWeek := $parsedDate.Format "Monday" | trimSuffix "day" | trimSuffix "on" | trimSuffix "es" | trimSuffix "edn" | 
              trimSuffix "urs" | trimSuffix "ri" | trimSuffix "tur" | trimSuffix "n" }}  
          
          {{/* highlight weekends (Sa Su) */}}
          {{ $day_color := "" }}
          {{ if eq $dayOfWeek "Sa" "Su" }}
            {{ $day_color = $weekend_color }}
          {{ end }}

          <div style="text-align: center; width: 10%; height: 25px; line-height: 25px; margin: 0 10% 0 3%; left: {{ mul $index 14 }}%; position: absolute; background-color: {{ $day_color | safeCSS }} ">
            <p class="size-h4 color-paragraph">{{ $dayOfWeek }}</p> 
          </div>
        {{ end }}
      </div>

      {{/* Show numeric day of month */}}
      <div style="position: relative; width: 100%; height: 25px;">     
        {{ range $index, $date := $dates }}
          {{ $dateString := .String "" }}
          {{ $trimmedDate := replaceMatches "[0-9]+-[0-9]+-" "" $dateString }}
          <div style="text-align: center; width: 10%; height: 25px; line-height: 25px; margin: 0 10% 0 3%; left: {{ mul $index 14 }}%; position: absolute;">
            <p class="size-h4 color-paragraph">{{ $trimmedDate }}</p> 
          </div>
        {{ end }}
      </div>

      {{/* Show weather conditions using fontawesome icons */}}
      <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
      {{ $codes := $req2.JSON.Array "daily.weathercode" }}

      <div style="position: relative; width: 100%; height: 30px;">     
        {{ range $index, $thiscode := $codes }}
          {{ $code := .Int "" }}

          <div style="text-align: center; width: 10%; height: 25px; line-height: 25px; margin: 0 10% 0 3%; left: {{ mul $index 14 }}% ; position: absolute;">
          {{ $wtype := "" }} 
          {{ $wicon := "" }} 
          {{ $wcolor := "" }} 
          {{ if eq $code 0 }}
            {{ $wtype = "Clear" }}
            {{ $wicon = "fas fa-sun" }}
            {{ $wcolor = $color_clear }}
          {{ else if eq $code 1 2 }}
            {{ $wtype = "Part Clear" }}
            {{ $wicon = "fas fa-cloud-sun" }}
            {{ $wcolor = $color_partly }} 
          {{ else if eq $code 3 }}
            {{ $wtype = "Cloudy" }}
            {{ $wicon = "fas fa-cloud" }}
            {{ $wcolor = $color_cloud }}
          {{ else if eq $code 45 48 }}
            {{ $wtype = "Fog" }}
            {{ $wicon = "fas fa-smog" }}
            {{ $wcolor = $color_smog }}
          {{ else if eq $code 51 53 55 56 57 }}
            {{ $wtype = "Drizzle" }}
            {{ $wicon = "fas fa-cloud-rain" }}
            {{ $wcolor = $color_drizzle }}
          {{ else if eq $code 61 63 65 80 81 82 }}
            {{ $wtype = "Rain" }}
            {{ $wicon = "fas fa-cloud-showers-heavy" }}
            {{ $wcolor = $color_rain }}
          {{ else if eq $code 66 67 }}
            {{ $wtype = "Freezing Rain" }}
            {{ $wicon = "fas fa-snowflake" }}
            {{ $wcolor = $color_freezing_rain }}
          {{ else if eq $code 71 73 75 77 85 86 }}
            {{ $wtype = "Snow" }}
            {{ $wicon = "fas fa-snowman" }}
            {{ $wcolor = $color_snow }}
          {{ else if eq $code 95 96 99 }}
            {{ $wtype = "Thunderstorm" }}
            {{ $wicon = "fas fa-bolt" }}
            {{ $wcolor = $color_thunderstorm }}
          {{ else }}
            {{ $wtype = "Other" }}
            {{ $wicon = "fa-solid fa-question" }}
            {{ $wcolor = $color_other }}
          {{ end }}
          <i class={{ $wicon }} style="font-size: 20px; color: {{ $wcolor | safeCSS }};", title = {{$wtype }}></i>
          </div>
        {{ end }}
      </div>
    </div>

    {{/* ===== show daily min and max temperatures ===== */}}
    {{ $maxTemps := $req2.JSON.Array "daily.temperature_2m_max" }}
    {{ $minTemps := $req2.JSON.Array "daily.temperature_2m_min" }} 

    {{/* get overall max and min temp over week's range */}}
    {{/* to determine vertical scale */}}
    <div style="display: flex; justify-content: flex-start; align-items: center;">

      {{ $max_max := 0 }}
      {{ range $maxTemps }}
          {{ if gt (.Int "") $max_max }}
            {{ $max_max = (.Int "") }}
          {{ end }}
      {{ end }}
      {{ $min_min := 999 }}
      {{ range $minTemps }}
          {{ if lt (.Int "") $min_min }}
            {{ $min_min = (.Int "") }}
          {{ end }}
      {{ end }}
      
      {{/* add a small buffer */}}
      {{ $max_max = add $max_max 1 }}
      {{ $min_min = sub $min_min 1 }}

      {{/* outer div to contain the temp chart */}}
      <div style="position: relative; width: 100%; height: 75px;">
        {{/* get relative % heights for each daily max and min */}}
        {{ $temp_range := sub $max_max $min_min }}

        {{ range $index, $thisHigh := $maxTemps }}
            {{ $thisLow := index $minTemps $index }}
            {{ $thisHigh = $thisHigh.Float "" }}
            {{ $thisLow = $thisLow.Float "" }}

            {{ $thisHighPct := sub 1 (div (sub $max_max $thisHigh) $temp_range) }}
            {{ $thisLowPct := div (sub $thisLow $min_min) $temp_range }}

            {{/* define color gradient per. values between $temp_red and $temp_yellow are shown as a color gradient from $color_red to $color_yellow */}}
            {{/* for colors partially in range, can represent as negative percent */}}
            {{ $thisTempRange := sub $thisHigh $thisLow }}
            {{ $red_pos := mul 100 (div (sub $thisHigh $temp_red) $thisTempRange) | toInt }}
            {{ $yel_pos := mul 100 (div (sub $thisHigh $temp_yellow) $thisTempRange) | toInt }}
            {{ $blu_pos := mul 100 (div (sub $thisHigh $temp_blue) $thisTempRange) | toInt }}
            {{ $whi_pos := mul 100 (div (sub $thisHigh $temp_white) $thisTempRange) | toInt }}
            {{ $gradient_string := printf "%s %d%%, %s %d%%, %s %d%%, %s %d%%" $color_red $red_pos $color_yellow $yel_pos $color_blue $blu_pos $color_white $whi_pos }}

            {{/* output daily div */}}
            <div style="left: {{ mul $index 14 | add 3 }}%; bottom: {{ mul $thisLowPct 100 | toInt }}%; 
              height: {{ mul (sub $thisHighPct $thisLowPct) 100 | toInt }}%; position: absolute;
              background:linear-gradient({{ $gradient_string | safeCSS }}); width: 10%; text-align: center; border-radius: 10px;">

              {{/* Based on rectangle height & position, print high and low temperatures either inside or outside the rectangle. */}}
              {{ $top_pos := -2 }}
              {{ $bot_pos := -2 }}
              {{ $pos_thresh := 0.20 }}
              {{ if lt (div $thisTempRange $temp_range) $pos_thresh }} 
                {{ $top_pos = -17 }}
                {{ $bot_pos = -19 }}
              {{ else if and (lt (div $thisTempRange $temp_range) (mul $pos_thresh 2)) (lt (sub 1 $thisHighPct) $thisLowPct) }}
                {{ $bot_pos = -19 }}
              {{ else if and (lt (div $thisTempRange $temp_range) (mul $pos_thresh 2)) (gt (sub 1 $thisHighPct) $thisLowPct) }}
                {{ $top_pos = -17 }}
              {{ end }}
                <div style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; background-color: {{ $overlay_color | safeCSS }}; z-index: 1;  border-radius: 10px;">
                  <p style='color: #F0F0F0; position: absolute; top: {{ $top_pos }}px; left: 0px; right: 0px'>{{ $thisHigh | toInt }}</p>
                  <p style='color: #F0F0F0; position: absolute; bottom: {{ $bot_pos }}px; left: 0px; right:0px'>{{ $thisLow | toInt }}</p>
                </div>
              </div>
        {{ end }}

      </div>
    </div>
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
                    subreddit = "LocalLLaMA";
                    "show-thumbnails" = true;
                  }
                  {
                    type = "reddit";
                    subreddit = "StableDiffusion";
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
                type = "custom-api";
                title = "Weather Forecast";
                body-type = "string";
                cache = "1h";
                options = {
                  location = kubenix.lib.secretsFor "weather_location";
                };
                template = weatherSevenDayTemplate;
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
                  "comfyanonymous/ComfyUI"
                  "imgproxy/imgproxy"
                  "openclaw/openclaw"
                  # Work Apps
                  "kong/kong"
                  "keycloak/keycloak"
                  "ruby/ruby"
                  "rails/rails"
                  # Daily Usage
                  "anthropics/claude-code"
                  "musistudio/claude-code-router"
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
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      configMaps."glance" = {
        metadata = {
          inherit namespace;
        };
        data."glance.yml" = kubenix.lib.toYamlStr glanceConfig;
      };
    };
  };
}
