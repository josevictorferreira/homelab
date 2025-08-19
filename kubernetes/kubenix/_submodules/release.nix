{ lib, kubenix, homelab, ... }: with lib;

{
  submodules.imports = [{
    module = { config, ... }:
      let cfg = config.submodule.args; in
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

          persistence = mkOption {
            description = "attrset of persistent volumes";
            default = { };
            type = types.attrsOf
              (types.submodule
                ({ config, ... }: {
                  options = {
                    enabled = mkOption {
                      type = types.bool;
                      default = true;
                    };
                    size = mkOption {
                      type = types.str;
                      default = "1Gi";
                    };
                    accessMode = mkOption {
                      type = types.str;
                      default = "ReadWriteOnce";
                    };
                    storageClass = mkOption {
                      type = types.str;
                      default = "longhorn-static";
                    };
                    mountPath = mkOption {
                      type = types.str;
                      default = "/${config._module.args.name}";
                    };
                    existingClaim = mkOption {
                      type = types.str;
                      default = "";
                    };
                    type = mkOption {
                      type = types.str;
                      default = "";
                    };
                    hostPath = mkOption {
                      type = types.str;
                      default = "";
                    };

                    name = mkOption {
                      type = types.str;
                      default = "";
                    };
                    readOnly = mkOption {
                      type = types.bool;
                      default = false;
                    };
                    subPath = mkOption {
                      type = types.str;
                      default = "";
                    };
                  };
                }));
          };

          config =
            mkOption
              {
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
            values =
              lib.mkMerge [
                {
                  inherit (cfg) persistence;
                  controllers.main.containers.main = {
                    image = cfg.image;
                    ports = [
                      {
                        name = "http";
                        containerPort = cfg.port;
                        protocol = "TCP";
                      }
                    ];
                  };
                  service.main.ports.http.port = cfg.port;
                  ingress.main = {
                    enabled = cfg.subdomain != "";
                    className = "cilium";
                    hosts = [{
                      host = "${cfg.subdomain}.${homelab.cluster.domain}";
                      paths = [{ path = "/"; }];
                    }];
                    tls = [{
                      secretName = "wildcard-tls";
                      hosts = [ "${cfg.subdomain}.${homelab.cluster.domain}" ];
                    }];
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
  }];
}
