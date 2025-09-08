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
      nfs = "10.10.10.150";
      grafana = "10.10.10.190";
      prowlarr = "10.10.10.120";
      qbittorrent = "10.10.10.119";
      postgresql = "10.10.10.101";
      openwebui = "10.10.10.111";
      redis = "10.10.10.102";
      ntfy = "10.10.10.114";
      uptimekuma = "10.10.10.122";
      rabbitmq = "10.10.10.139";
      sftpgo = "10.10.10.115";
      sftpgoapi = "10.10.10.115";
      searxng = "10.10.10.107";
    };
  };

  namespaces = {
    monitoring = "monitoring";
    certificate = "cert-manager";
    applications = "apps";
    storage = "rook-ceph";
  };
}
