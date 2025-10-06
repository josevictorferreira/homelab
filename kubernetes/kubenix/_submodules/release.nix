{ lib, kubenix, ... }:
with lib;

let
  getFileType = filename:
              if (hasSuffix ".yaml" filename || hasSuffix ".yml" filename) then "yaml"
              else if (hasSuffix ".json" filename) then "json"
              else throw "Unsupported config file extension in '${filename}'. Use .yaml, .yml, or .json.";
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

            subdomain = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "hostname subdomain";
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

            persistence = mkOption {
              description = "attrset of persistent volumes";
              default = {
                enabled = false;
                type = "persistentVolumeClaim";
                storageClass = "rook-ceph-block";
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
              type = types.nullOr (types.submodule {
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
              });
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
                    image = cfg.image;
                    ports = [
                      {
                        name = "http";
                        containerPort = cfg.port;
                        protocol = "TCP";
                      }
                    ];
                  }
                  // optionalAttrs (cfg.secretName != null) {
                    envFrom = [ { secretRef.name = cfg.secretName; } ];
                  }
                  // optionalAttrs (cfg.resources != null) {
                    resources = cfg.resources;
                  }
                  // optionalAttrs (cfg.command != null) {
                    command = cfg.command;
                  };
                  service.main = {
                    type = "LoadBalancer";
                    annotations = kubenix.lib.serviceAnnotationFor config._module.args.name;
                    ports = {
                      http = {
                        enabled = true;
                        port = cfg.port;
                      };
                    };
                  };
                  ingress.main = {
                    enabled = cfg.subdomain != null;
                    className = "cilium";
                    hosts = [
                      {
                        host = kubenix.lib.domainFor cfg.subdomain;
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
                        secretName = "wildcard-tls";
                        hosts = [ (kubenix.lib.domainFor cfg.subdomain) ];
                      }
                    ];
                  };
                }
                (mkIf (cfg.config != null) {
                  persistence.config = {
                    enabled = true;
                    type = "configMap";
                    name = "${config._module.args.name}-config";
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
                cfg.values
              ];
            };
          };
        };
    }
  ];
}
