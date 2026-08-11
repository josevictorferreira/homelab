{ homelab, kubenix, ... }:
let
  readeckTemplate = ''
    <ul class="list list-gap-10 collapsible-container" data-collapse-after="7">
      {{ range .JSON.Array "" }}
        <li>
          {{ $title := .String "title" }}
          {{ if gt (len $title) 50 }}
            {{ $title = (slice $title 0 50) | printf "%s..." }}
          {{ end }}
          {{ $thumb := .String "resources.thumbnail.src" }}
          {{ $hasThumb := gt (len $thumb) 0 }}
          <div style="display: flex; gap: 8px; align-items: flex-start;">
            {{ if $hasThumb }}
              {{ $thumbUrl := replaceAll "http://readeck.apps.svc.cluster.local:8000" "https://readeck.josevictor.me" $thumb }}
              <img src="{{ $thumbUrl }}" style="width: 48px; height: 48px; object-fit: cover; border-radius: 6px; flex-shrink: 0;" loading="lazy">
            {{ end }}
            <div style="flex: 1; min-width: 0;">
              <a class="size-title-dynamic color-primary-if-not-visited"
                 href="{{ .String "url" }}"
                 target="_self"
                 rel="noopener noreferrer">{{ $title }}</a>
              <ul class="list-horizontal-text" style="margin-top: 2px;">
                <li>{{ .String "site_name" }}</li>
                {{ $labels := .Array "labels" }}
                {{ range $index, $label := $labels }}
                  {{ $hue := mul (mod $index 12) 30 }}
                  <li style="background-color: hsl({{ $hue }}, 50%, 20%); color: hsl({{ $hue }}, 60%, 70%); padding: 1px 6px; border-radius: 4px; font-size: 11px; line-height: 1.4;">{{ $s := printf "%s" . }}{{ replaceAll "{" "" (replaceAll "}" "" $s) }}</li>
                {{ end }}
              </ul>
            </div>
          </div>
        </li>
      {{ end }}
    </ul>
  '';

  kimiCodeTemplate = ''
    {{ $level := .JSON.String "user.membership.level" }}
    {{ $levelLabel := replaceAll "LEVEL_" "" $level }}
    {{ $levelColor := "var(--color-positive)" }}
    {{ if eq $level "LEVEL_BASIC" }}
      {{ $levelColor = "var(--color-text-subdue)" }}
    {{ else if eq $level "LEVEL_INTERMEDIATE" }}
      {{ $levelColor = "var(--color-primary)" }}
    {{ else if eq $level "LEVEL_ADVANCED" }}
      {{ $levelColor = "var(--color-positive)" }}
    {{ end }}

    {{ $weeklyUsed := .JSON.Float "usage.used" }}
    {{ $weeklyLimit := .JSON.Float "usage.limit" }}
    {{ $weeklyPct := 0.0 }}
    {{ if gt $weeklyLimit 0.0 }}
      {{ $weeklyPct = mul (div $weeklyUsed $weeklyLimit) 100.0 }}
    {{ end }}

    {{ $windowRemaining := .JSON.Float "limits.0.detail.remaining" }}
    {{ $windowLimit := .JSON.Float "limits.0.detail.limit" }}
    {{ $windowDur := .JSON.Int "limits.0.window.duration" }}

    {{ $totalRemaining := .JSON.Float "totalQuota.remaining" }}
    {{ $totalLimit := .JSON.Float "totalQuota.limit" }}

    {{ $parallel := .JSON.Int "parallel.limit" }}

    {{ $resetRaw := .JSON.String "usage.resetTime" }}
    {{ $resetTime := $resetRaw | parseTime "2006-01-02T15:04:05Z07:00" }}

    <div style="display: flex; flex-direction: column; gap: 10px;">
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="background-color: {{ $levelColor | safeCSS }}; color: var(--color-text-highlight); padding: 2px 10px; border-radius: 4px; font-size: 12px; font-weight: 600;">{{ $levelLabel }}</span>
      </div>

      <div style="display: flex; flex-direction: column; gap: 4px;">
        <div style="display: flex; justify-content: space-between; font-size: 11px;">
          <span class="color-paragraph">Weekly</span>
          <span>{{ $weeklyUsed | toInt }}/{{ $weeklyLimit | toInt }}</span>
        </div>
        <div style="background-color: var(--color-separator); border-radius: 4px; height: 8px; overflow: hidden;">
          <div style="background-color: var(--color-primary); height: 100%; width: {{ $weeklyPct | toInt }}%; border-radius: 4px; transition: width 0.3s;"></div>
        </div>
      </div>

      <div style="display: flex; flex-direction: column; gap: 4px;">
        <div style="display: flex; justify-content: space-between; font-size: 11px;">
          <span class="color-paragraph">{{ $windowDur }}m window</span>
          <span>{{ $windowRemaining | toInt }}/{{ $windowLimit | toInt }}</span>
        </div>
        <div style="background-color: var(--color-separator); border-radius: 4px; height: 8px; overflow: hidden;">
          <div style="background-color: var(--color-positive); height: 100%; width: {{ mul (div $windowRemaining $windowLimit) 100.0 | toInt }}%; border-radius: 4px; transition: width 0.3s;"></div>
        </div>
      </div>

      <div style="display: flex; flex-direction: column; gap: 4px;">
        <div style="display: flex; justify-content: space-between; font-size: 11px;">
          <span class="color-paragraph">Total quota</span>
          <span>{{ $totalRemaining | toInt }}/{{ $totalLimit | toInt }}</span>
        </div>
        <div style="background-color: var(--color-separator); border-radius: 4px; height: 8px; overflow: hidden;">
          <div style="background-color: var(--color-text-subdue); height: 100%; width: {{ mul (div $totalRemaining $totalLimit) 100.0 | toInt }}%; border-radius: 4px; transition: width 0.3s;"></div>
        </div>
      </div>

      <ul class="list-horizontal-text" style="font-size: 11px;">
        <li>Resets {{ $resetTime.Format "Mon Jan 2" }}</li>
        <li>Parallel: {{ $parallel }}</li>
      </ul>
    </div>
  '';

  zaiCodeTemplate = ''
    {{ $total := .JSON.Float "data.total_quota" }}
    {{ $used := .JSON.Float "data.used_quota" }}
    {{ $remaining := .JSON.Float "data.remaining_quota" }}
    {{ $pctUsed := 0.0 }}
    {{ if gt $total 0.0 }}
      {{ $pctUsed = mul (div $used $total) 100.0 }}
    {{ end }}
    {{ $plan := .JSON.String "data.plan" }}
    {{ $expires := .JSON.String "data.expire_date" }}

    <div style="display: flex; flex-direction: column; gap: 10px;">
      <div style="display: flex; align-items: center; gap: 8px;">
        {{ $planLabel := "Z-AI" }}
        {{ if $plan }}
          {{ $planLabel = $plan }}
        {{ end }}
        <span style="background-color: var(--color-primary); color: var(--color-text-highlight); padding: 2px 10px; border-radius: 4px; font-size: 12px; font-weight: 600;">{{ $planLabel }}</span>
      </div>

      <div style="display: flex; flex-direction: column; gap: 4px;">
        <div style="display: flex; justify-content: space-between; font-size: 11px;">
          <span class="color-paragraph">Credits Used</span>
          <span>{{ $used | toInt }}/{{ $total | toInt }}</span>
        </div>
        <div style="background-color: var(--color-separator); border-radius: 4px; height: 8px; overflow: hidden;">
          <div style="background-color: var(--color-primary); height: 100%; width: {{ $pctUsed | toInt }}%; border-radius: 4px; transition: width 0.3s;"></div>
        </div>
      </div>

      <div style="display: flex; flex-direction: column; gap: 4px;">
        <div style="display: flex; justify-content: space-between; font-size: 11px;">
          <span class="color-paragraph">Remaining</span>
          <span>{{ $remaining | toInt }}</span>
        </div>
        <div style="background-color: var(--color-separator); border-radius: 4px; height: 8px; overflow: hidden;">
          <div style="background-color: var(--color-positive); height: 100%; width: {{ sub 100.0 $pctUsed | toInt }}%; border-radius: 4px; transition: width 0.3s;"></div>
        </div>
      </div>

      {{ if $expires }}
      <ul class="list-horizontal-text" style="font-size: 11px;">
        <li>Expires: {{ $expires }}</li>
      </ul>
      {{ end }}
    </div>
  '';

  openrouterTemplate = ''
    {{ $totalCredits := .JSON.Float "data.total_credits" }}
    {{ $totalUsage := .JSON.Float "data.total_usage" }}
    {{ $remaining := sub $totalCredits $totalUsage }}
    {{ $pctUsed := 0.0 }}
    {{ if gt $totalCredits 0.0 }}
      {{ $pctUsed = mul (div $totalUsage $totalCredits) 100.0 }}
    {{ end }}

    <div style="display: flex; flex-direction: column; gap: 10px;">
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="background-color: var(--color-primary); color: var(--color-text-highlight); padding: 2px 10px; border-radius: 4px; font-size: 12px; font-weight: 600;">OpenRouter</span>
      </div>

      <div style="display: flex; flex-direction: column; gap: 4px;">
        <div style="display: flex; justify-content: space-between; font-size: 11px;">
          <span class="color-paragraph">Credits Used</span>
          <span>''${{ printf "%.2f" $totalUsage }}/''${{ printf "%.2f" $totalCredits }}</span>
        </div>
        <div style="background-color: var(--color-separator); border-radius: 4px; height: 8px; overflow: hidden;">
          <div style="background-color: var(--color-primary); height: 100%; width: {{ $pctUsed | toInt }}%; border-radius: 4px; transition: width 0.3s;"></div>
        </div>
      </div>

      <div style="display: flex; flex-direction: column; gap: 4px;">
        <div style="display: flex; justify-content: space-between; font-size: 11px;">
          <span class="color-paragraph">Remaining</span>
          <span>''${{ printf "%.2f" $remaining }}</span>
        </div>
        <div style="background-color: var(--color-separator); border-radius: 4px; height: 8px; overflow: hidden;">
          <div style="background-color: var(--color-positive); height: 100%; width: {{ sub 100.0 $pctUsed | toInt }}%; border-radius: 4px; transition: width 0.3s;"></div>
        </div>
      </div>

      <ul class="list-horizontal-text" style="font-size: 11px;">
        <li>''${{ printf "%.2f" $totalCredits }} total</li>
      </ul>
    </div>
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

  githubIcon = ''
    <svg viewBox="0 0 24 24" fill="currentColor" style="width: 13px; height: 13px; margin-left: 6px; vertical-align: -1px; flex-shrink: 0;"><path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>'';

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
                url = "http://readeck.${namespace}.svc.cluster.local:8000/api/bookmarks?limit=15";
                headers = {
                  Authorization = "Bearer ${kubenix.lib.secretsFor "readeck_api_token"}";
                };
                template = readeckTemplate;
              }
            ];
          }
          {
            size = "full";
            widgets = [
              # Links to every service currently running with 1+ replicas and a
              # public ingress. Deliberately "bookmarks" and not "monitor":
              # 12 of these 20 answer / with a non-200 (Keycloak 302s, blocky
              # 503s, velox and homelab-bridge have no root route), so a
              # monitor widget would render most of the homelab as down.
              {
                type = "bookmarks";
                title = "Homelab";
                groups = [
                  {
                    title = "Apps";
                    color = "24 97 58";
                    "same-tab" = false;
                    links = [
                      {
                        title = "Home Assistant";
                        url = "https://home.josevictor.me";
                        icon = "sh:home-assistant";
                      }
                      {
                        title = "Calibre-Web";
                        url = "https://calibre.josevictor.me";
                        icon = "sh:calibre-web";
                      }
                      {
                        title = "Readeck";
                        url = "https://readeck.josevictor.me";
                        icon = "sh:readeck";
                      }
                      {
                        title = "SearXNG";
                        url = "https://searxng.josevictor.me";
                        icon = "sh:searxng";
                      }
                      {
                        title = "Matrix";
                        url = "https://matrix.josevictor.me";
                        # base "matrix" icon is #040404 and vanishes on the
                        # dark theme; -light is the inverted variant
                        icon = "sh:matrix-light";
                      }
                      {
                        title = "SFTPGo";
                        url = "https://sftpgo.josevictor.me";
                        icon = "sh:sftpgo";
                      }
                      {
                        title = "Oratoria";
                        url = "https://oratoria.josevictor.me";
                        icon = "mdi:presentation";
                      }
                      {
                        title = "Dramaturge";
                        url = "https://dramaturge.josevictor.me";
                        icon = "mdi:drama-masks";
                      }
                    ];
                  }
                  {
                    title = "AI";
                    color = "280 60 60";
                    "same-tab" = false;
                    links = [
                      {
                        title = "Hermes";
                        url = "https://hermes.josevictor.me";
                        icon = "sh:hermes-agent";
                      }
                      {
                        title = "OmniRoute";
                        url = "https://omniroute.josevictor.me";
                        icon = "sh:omniroute";
                      }
                      {
                        title = "Hindsight";
                        url = "https://hindsight.josevictor.me";
                        icon = "mdi:brain";
                      }
                      {
                        title = "Velox";
                        url = "https://velox.josevictor.me";
                        icon = "mdi:lightning-bolt";
                      }
                    ];
                  }
                  {
                    title = "Finance";
                    color = "150 60 55";
                    "same-tab" = false;
                    links = [
                      {
                        title = "Valoris";
                        url = "https://valoris.josevictor.me";
                        icon = "mdi:chart-line";
                      }
                      {
                        title = "Wealtho";
                        url = "https://wealtho.josevictor.me";
                        icon = "mdi:wallet";
                      }
                      {
                        title = "Personal Finances";
                        url = "https://personal-finances.josevictor.me";
                        icon = "mdi:cash-multiple";
                      }
                    ];
                  }
                  {
                    title = "Infra";
                    color = "209 88 54";
                    "same-tab" = false;
                    links = [
                      {
                        title = "Grafana";
                        url = "https://grafana.josevictor.me";
                        icon = "sh:grafana";
                      }
                      {
                        title = "Ceph";
                        url = "https://ceph.josevictor.me";
                        icon = "sh:ceph";
                      }
                      {
                        title = "Keycloak";
                        url = "https://identity.josevictor.me";
                        icon = "sh:keycloak";
                      }
                      {
                        title = "Blocky";
                        url = "https://blocky.josevictor.me";
                        icon = "sh:blocky";
                      }
                      {
                        title = "Homelab Bridge";
                        url = "https://homelab-bridge.josevictor.me";
                        icon = "mdi:transit-connection-variant";
                      }
                    ];
                  }
                ];
              }
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
                    subreddit = "functionalprint";
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
                type = "custom-api";
                title = "Recent GitHub Repositories";
                cache = "1h";
                timeout = "60s";
                method = "GET";
                url = "https://api.github.com/search/commits?q=author:josevictorferreira&sort=author-date&order=desc&per_page=100";
                headers = {
                  Accept = "application/vnd.github+json";
                  Authorization = "Bearer ${kubenix.lib.secretsFor "github_token"}";
                };
                template = ''
                  {{ range $index, $commit := unique "repository.full_name" (.JSON.Array "items") }}
                    {{ if lt $index 10 }}
                      <div class="flex items-center gap-10">
                        <a class="size-title-dynamic color-primary-if-not-visited" href="{{ $commit.String "repository.html_url" }}" target="_blank" rel="noreferrer">{{ $commit.String "repository.full_name" }}${githubIcon}</a>
                        <div class="flex-1"></div>
                        <div class="color-subdue text-compact" {{ $commit.String "commit.author.date" | parseTime "rfc3339" | toRelativeTime }}></div>
                      </div>
                    {{ end }}
                  {{ end }}
                '';
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
                token = kubenix.lib.secretsFor "github_token";
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
                  "nousresearch/hermes-agent"
                  "Martian-Engineering/lossless-claw"
                  "decolua/9router"
                  "vectorize-io/hindsight"
                  "diegosouzapw/OmniRoute"
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
      {
        name = "Agents";
        columns = [
          {
            size = "full";
            widgets = [
              {
                type = "custom-api";
                title = "Kimi Code";
                cache = "30m";
                timeout = "30s";
                method = "GET";
                url = "https://api.kimi.com/coding/v1/usages";
                headers = {
                  Authorization = "Bearer ${kubenix.lib.secretsFor "moonshot_api_key"}";
                };
                template = kimiCodeTemplate;
              }
              {
                type = "custom-api";
                title = "Z-AI (GLM)";
                cache = "30m";
                timeout = "30s";
                method = "GET";
                url = "https://open.bigmodel.cn/api/paas/v4/user/quota";
                headers = {
                  Authorization = "Bearer ${kubenix.lib.secretsFor "alibaba_coding_plan_api_key"}";
                };
                template = zaiCodeTemplate;
              }
              {
                type = "custom-api";
                title = "OpenRouter";
                cache = "30m";
                timeout = "30s";
                method = "GET";
                url = "https://openrouter.ai/api/v1/credits";
                headers = {
                  Authorization = "Bearer ${kubenix.lib.secretsFor "openrouter_api_key_openclaw"}";
                };
                template = openrouterTemplate;
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
