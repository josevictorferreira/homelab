{ lib, kubenix, k8sLib, homelab, ... }:

let
  app = "uptimekuma";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    helm.releases.${app} = {
      chart = k8sLib.helm.fetch {
        repo = "https://helm.irsigler.cloud/";
        chart = "uptime-kuma";
        version = "2.22.0";
        sha256 = "sha256-qFG0Iq2IBwkqG6t2Z47GDU3fjftzy3xI7ALNJjctNQk=";
      };
      includeCRDs = true;
      noHooks = true;
      namespace = namespace;

      values = {
        image = {
          repository = "louislam/uptime-kuma";
          pullPolicy = "IfNotPresent";
          tag = "1.23.16-debian";
        };

        volume = {
          storageClassName = "ceph-rbd";
        };

        ingress = {
          enabled = true;
          className = "cilium";
          annotations = k8sLib.serviceIpFor app;
          hosts = [
            {
              host = k8sLib.domainFor "uptimekuma";
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                }
              ];
            }
          ];
          tls = [
            {
              hosts = [ (k8sLib.domainFor "uptimekuma") ];
              secretName = "wildcard-tls";
            }
          ];
        };
      };
    };
  };
}
