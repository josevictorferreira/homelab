{ lib, kubenix, ... }:
with lib;

let
  getFileType =
    filename:
    if (hasSuffix ".yaml" filename || hasSuffix ".yml" filename) then
      "yaml"
    else if (hasSuffix ".json" filename) then
      "json"
    else
      throw "Unsupported config file extension in '${filename}'. Use .yaml, .yml, or .json.";

  # An `until` loop never exits non-zero, so the pod blocks in Init instead of
  # crashing. That keeps it out of CrashLoopBackOff entirely and lets it start
  # the moment the dependency is actually reachable.
  waitForContainer = {
    postgres = {
      # Public official image on purpose: these apps carry no imagePullSecrets,
      # so the private ghcr postgres image would ImagePullBackOff here.
      image = {
        repository = "docker.io/library/postgres";
        tag = "18-alpine";
      };
      command = [
        "sh"
        "-c"
        ''
          until pg_isready -h postgresql-18 -p 5432 -U postgres; do
            echo "waiting for postgresql-18..."
            sleep 3
          done
        ''
      ];
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "100m";
          memory = "64Mi";
        };
      };
    };
    redis = {
      image = {
        repository = "docker.io/library/redis";
        tag = "8-alpine";
      };
      command = [
        "sh"
        "-c"
        ''
          # NOAUTH means the server is up and serving (auth is enabled, and we
          # deliberately hold no credentials here); LOADING means it is still
          # reading the dataset, so keep waiting on that one.
          until redis-cli -h redis-master -p 6379 ping 2>&1 | grep -qE "PONG|NOAUTH"; do
            echo "waiting for redis-master..."
            sleep 3
          done
        ''
      ];
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "100m";
          memory = "64Mi";
        };
      };
    };
  };
in

{
  submodules.imports = [
    {
      module =
        { config, ... }:
        let
          cfg = config.submodule.args;
        in
        {
          imports = with kubenix.modules; [
            helm
            k8s
            submodule
          ];

          options.submodule.args = {
            enable = mkEnableOption "a simple and generic helm release template";

            namespace = mkOption {
              default = homelab.kubernetes.namespaces.applications;
              type = types.str;
              description = "target namespace";
            };

            image = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "image to use for the release";
            };

            port = mkOption {
              type = types.int;
              default = 80;
              description = "container port";
            };

            replicas = mkOption {
              type = types.int;
              default = 1;
              description = "number of replicas";
            };

            secretName = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "secret name for application credentials and configs";
            };

            command = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = "command to start the container";
            };

            resources = mkOption {
              type = types.nullOr (types.attrsOf (types.attrsOf types.str));
              default = null;
              description = "resources limits to be applied in the release";
            };

            priorityClassName = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "priority class name for the pods";
            };

            waitFor = mkOption {
              type = types.listOf (types.enum [
                "postgres"
                "redis"
              ]);
              default = [ ];
              description = ''
                Backing services to block on before the main container starts.
                Adds an init container that polls until the dependency answers,
                so a cold boot waits quietly instead of crash-looping into
                exponential backoff (which caps at 5min and stacks per app).
              '';
            };

            persistence = mkOption {
              description = "attrset of persistent volumes";
              default = {
                enabled = false;
                type = "persistentVolumeClaim";
                storageClass = kubenix.lib.defaultStorageClass;
                size = "1Gi";
                accessMode = "ReadWriteOnce";
                globalMounts = [
                  {
                    path = "/data";
                    readOnly = false;
                  }
                ];
              };
              type = types.attrs;
            };

            config = mkOption {
              description = "A structured way to define a config map and mount it.";
              default = null;
              type = types.nullOr (
                types.submodule {
                  options = {
                    filename = mkOption {
                      type = types.str;
                      default = "config.yml";
                      description = "The filename";
                    };
                    mountPath = mkOption {
                      type = types.str;
                      default = "/config";
                      description = "The path inside the container where the config file will be mounted.";
                    };
                    data = mkOption {
                      type = types.nullOr types.attrs;
                      default = null;
                      description = "The attrset containing the actual configuration data.";
                    };
                  };
                }
              );
            };

            values = mkOption {
              type = types.attrs;
              default = { };
              description = "freeform release values";
            };
          };

          config = {
            submodule = {
              name = "release";
              passthru.kubernetes.objects = config.kubernetes.objects;
            };

            kubernetes.helm.releases.${config._module.args.name} = {
              inherit (cfg) namespace;
              chart = kubenix.lib.helm.fetch {
                repo = "https://bjw-s-labs.github.io/helm-charts/";
                chart = "app-template";
                version = "4.2.0";
                sha256 = "sha256-JhHJmGrvpmdHfADfM4M4mby64cSH6HO6VpKmeQfngJA=";
              };
              values = lib.mkMerge [
                {
                  persistence.main = cfg.persistence;
                  controllers.main.replicas = cfg.replicas;
                  controllers.main.containers.main = {
                    inherit (cfg) image;
                    ports = [
                      {
                        name = "http";
                        containerPort = cfg.port;
                        protocol = "TCP";
                      }
                    ];
                  }
                  // optionalAttrs (cfg.secretName != null) {
                    envFrom = [{ secretRef.name = cfg.secretName; }];
                  }
                  // optionalAttrs (cfg.resources != null) {
                    inherit (cfg) resources;
                  }
                  // optionalAttrs (cfg.command != null) {
                    inherit (cfg) command;
                  };
                  service.main = {
                    type = "LoadBalancer";
                    annotations = kubenix.lib.serviceAnnotationFor config._module.args.name;
                    ports = {
                      http = {
                        enabled = true;
                        inherit (cfg) port;
                      };
                    };
                  };
                  ingress.main = {
                    enabled = true;
                    className = kubenix.lib.defaultIngressClass;
                    hosts = [
                      {
                        host = kubenix.lib.domainFor config._module.args.name;
                        paths = [
                          {
                            path = "/";
                            service.name = "${config._module.args.name}";
                            service.port = cfg.port;
                          }
                        ];
                      }
                    ];
                    tls = [
                      {
                        secretName = kubenix.lib.defaultTLSSecret;
                        hosts = [ (kubenix.lib.domainFor config._module.args.name) ];
                      }
                    ];
                  };
                }
                (mkIf (cfg.config != null) {
                  persistence.config = {
                    enabled = true;
                    type = "configMap";
                    name = "${config._module.args.name}";
                    globalMounts = [
                      {
                        path = "${strings.removeSuffix "/" cfg.config.mountPath}/${strings.removePrefix "/" cfg.config.filename}";
                        readOnly = true;
                        subPath = cfg.config.filename;
                      }
                    ];
                    items = [
                      {
                        key = cfg.config.filename;
                        path = cfg.config.filename;
                      }
                    ];
                  };
                  configMaps.config = {
                    enabled = cfg.config.data != null;
                    data.${cfg.config.filename} =
                      if (getFileType cfg.config.filename) == "yaml" then
                        kubenix.lib.toYamlStr cfg.config.data
                      else
                        builtins.toJSON cfg.config.data;
                  };
                })
                (mkIf (cfg.priorityClassName != null) {
                  controllers.main.pod.priorityClassName = cfg.priorityClassName;
                })
                (mkIf (cfg.waitFor != [ ]) {
                  controllers.main.initContainers = builtins.listToAttrs (
                    map (dep: {
                      name = "wait-for-${dep}";
                      value = waitForContainer.${dep};
                    }) cfg.waitFor
                  );
                })
                cfg.values
              ];
            };
          };
        };
    }
  ];
}
