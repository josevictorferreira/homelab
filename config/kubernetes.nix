{ ... }:

{
  vipAddress = "10.10.10.250";

  version = "1.32";

  loadBalancer = {
    address = "10.10.10.110";
    range = {
      start = "10.10.10.100";
      stop = "10.10.10.199";
    };
    services = {
      linkwarden = "10.10.10.103";
      glance = "10.10.10.127";
      libebooker = "10.10.10.123";
      pihole = "10.10.10.100";
      objectstore = "10.10.10.106";
      ceph = "10.10.10.105";
      homelab-nfs = "10.10.10.150";
      grafana = "10.10.10.190";
      prowlarr = "10.10.10.120";
    };
  };

  namespaces = {
    monitoring = "monitoring";
    certificate = "cert-manager";
    applications = "apps";
    storage = "rook-ceph";
  };
}
