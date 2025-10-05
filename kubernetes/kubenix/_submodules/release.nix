{ lib, kubenix, ... }:
with lib;

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
              default = "default";
              type = types.str;
              description = "target namespace";
            };

            image = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "image to use for the release";
            };

            subdomain = mkOption {
              type = types.str;
              default = "";
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
              type = types.str;
              default = "";
              description = "secret name for application credentials and configs";
            };

            resources = mkOption {
              type = types.attrsOf (types.attrsOf types.str);
              default = { };
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
              type = types.attrs;
              default = { };
              description = "yaml in configmap";
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
                  controllers.main.replicas = cfg.replicas;
                  persistence.main = cfg.persistence;
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
                  // optionalAttrs (cfg.secretName != "") {
                    envFrom = [ { secretRef.name = cfg.secretName; } ];
                  }
                  // optionalAttrs (cfg.resources != { }) {
                    resources = cfg.resources;
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
                    enabled = cfg.subdomain != "";
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
                (mkIf (cfg.config != { }) {
                  persistence.config = {
                    enabled = true;
                    type = "configMap";
                    name = "${name}-config";
                    readOnly = true;
                  };
                  configMaps.config = {
                    enabled = true;
                    data."config.yml" = lib.generators.toYAML { } cfg.config;
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
