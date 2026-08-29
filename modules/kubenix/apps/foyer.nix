{ homelab, kubenix, ... }:

let
  app = "foyer";
  namespace = homelab.kubernetes.namespaces.applications;
  port = 8080;
  pullSecrets = [ { name = "ghcr-registry-secret"; } ];
in
{
  submodules.instances.${app} = {
    submodule = "release";
    args = {
      inherit namespace port;
      image = {
        repository = "ghcr.io/josevictorferreira/foyer";
        tag = "latest";
        pullPolicy = "Always";
      };
      # Foyer uses separate persistent paths for its SQLite state and module
      # cache; the release's default /data volume is retained but unused.
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
      config = {
        filename = "foyer.yml";
        mountPath = "/app/config";
        data = {
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
                      headers.Authorization = "Bearer ${kubenix.lib.secretsFor "readeck_api_token"}";
                      template = ''
                        <ul class="list bookmarks">{% for bookmark in data.response.body.bookmarks|default([]) %}<li><a href="{{ "{{" }} bookmark.url {{ "}}" }}">{{ "{{" }} bookmark.title|truncate(50) {{ "}}" }}</a><div class="meta">{{ "{{" }} bookmark.site_name|default("") {{ "}}" }}</div></li>{% endfor %}</ul>
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
                          class = "green";
                          items = [
                            {
                              name = "Home Assistant";
                              url = "https://home.josevictor.me";
                              icon = "home";
                              same_tab = false;
                            }
                            {
                              name = "BookOrbit";
                              url = "https://bookorbit.josevictor.me";
                              icon = "book";
                              same_tab = false;
                            }
                            {
                              name = "Readeck";
                              url = "https://readeck.josevictor.me";
                              icon = "read";
                              same_tab = false;
                            }
                            {
                              name = "SearXNG";
                              url = "https://searxng.josevictor.me";
                              icon = "search";
                              same_tab = false;
                            }
                            {
                              name = "Oratoria";
                              url = "https://oratoria.josevictor.me";
                              icon = "presentation";
                              same_tab = false;
                            }
                          ];
                        }
                        {
                          class = "purple";
                          items = [
                            {
                              name = "Hermes";
                              url = "https://hermes.josevictor.me";
                              icon = "agent";
                              same_tab = false;
                            }
                            {
                              name = "Hindsight";
                              url = "https://hindsight.josevictor.me";
                              icon = "brain";
                              same_tab = false;
                            }
                            {
                              name = "Valoris";
                              url = "https://valoris.josevictor.me";
                              icon = "chart";
                              same_tab = false;
                            }
                            {
                              name = "Wealtho";
                              url = "https://wealtho.josevictor.me";
                              icon = "wallet";
                              same_tab = false;
                            }
                            {
                              name = "Poise";
                              url = "https://poise.josevictor.me";
                              icon = "hanger";
                              same_tab = false;
                            }
                          ];
                        }
                        {
                          class = "red";
                          items = [
                            {
                              name = "Grafana";
                              url = "https://grafana.josevictor.me";
                              icon = "grafana";
                              same_tab = false;
                            }
                            {
                              name = "Ceph";
                              url = "https://ceph.josevictor.me";
                              icon = "ceph";
                              same_tab = false;
                            }
                            {
                              name = "Keycloak";
                              url = "https://identity.josevictor.me";
                              icon = "keycloak";
                              same_tab = false;
                            }
                            {
                              name = "SFTPGo";
                              url = "https://sftpgo.josevictor.me";
                              icon = "sftpgo";
                              same_tab = false;
                            }
                            {
                              name = "Immich";
                              url = "https://immich.josevictor.me";
                              icon = "immich";
                              same_tab = false;
                            }
                          ];
                        }
                      ];
                    }
                    {
                      type = "group";
                      widgets = [
                        {
                          type = "hackernews";
                          title = "Hacker News";
                        }
                        {
                          type = "lobsters";
                          title = "Lobsters";
                        }
                        {
                          type = "reddit";
                          title = "r/selfhosted";
                          subreddit = "selfhosted";
                          show_thumbnails = true;
                        }
                        {
                          type = "reddit";
                          title = "r/LocalLLaMA";
                          subreddit = "LocalLLaMA";
                          show_thumbnails = true;
                        }
                        {
                          type = "reddit";
                          title = "r/functionalprint";
                          subreddit = "functionalprint";
                          show_thumbnails = true;
                        }
                        {
                          type = "reddit";
                          title = "r/StableDiffusion";
                          subreddit = "StableDiffusion";
                          show_thumbnails = true;
                        }
                      ];
                    }
                    {
                      type = "videos";
                      title = "Videos";
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
      };
      values = {
        defaultPodOptions.imagePullSecrets = pullSecrets;
        controllers.main.containers.main.probes = {
          startup = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/healthz";
                inherit port;
              };
              initialDelaySeconds = 5;
              periodSeconds = 5;
              failureThreshold = 30;
            };
          };
          liveness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/healthz";
                inherit port;
              };
              periodSeconds = 30;
              timeoutSeconds = 5;
            };
          };
          readiness = {
            enabled = true;
            custom = true;
            spec = {
              httpGet = {
                path = "/readyz";
                inherit port;
              };
              periodSeconds = 10;
              timeoutSeconds = 5;
            };
          };
        };
        persistence.data = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/data";
              readOnly = false;
            }
          ];
        };
        persistence.cache = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/cache";
              readOnly = false;
            }
          ];
        };
      };
    };
  };
}
