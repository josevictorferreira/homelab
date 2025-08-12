{ pkgs, ... }:

let
  src = pkgs.fetchFromGithub
    {
      owner = "josevictorferreira";
      repo = "libebooker";
      rev = "v0.1.0";
      sha256 = "sha256:6df86a7e8868d1eda21f35205134b1962c422957e42a0c44d4717c8e8f741b1a";
    };
  chartPath = "${src}/.helm/libebooker";
in
{
  kubernetes = {
    helm.releases."libebooker" = {
      chart = chartPath;
      namespace = "apps";
      noHooks = true;
      values = {
        image = {
          repository = "ghcr.io/josevictorferreira/libebooker";
          tag = "latest";
          pullPolicy = "IfNotPresent";
        };

        strategy = {
          type = "RollingUpdate";
          maxSurge = 1;
          maxUnavailable = 1;
          minReadySeconds = 10;
        };

        app = {
          label = "libebooker";
          command = [ "bundle" "exec" "rackup" ];
          replicaCount = 1;

          service = {
            port = 9292;
            type = "LoadBalancer";
            loadBalancerIP = "10.10.10.123";
            annotations = {
              "io.cilium/lb-ipam-ips" = "10.10.10.123";
            };
          };

          env = {
            port = "9292";
            address = "0.0.0.0";
          };

          resources = {
            requests = {
              memory = "512Mi";
              cpu = "30m";
            };
            limits = {
              memory = "512Mi";
            };
          };

          healthcheck_path = "/health";
        };
      };
    };
  };
}
