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
      blocky = "10.10.10.100";
      postgresql = "10.10.10.101";
      redis = "10.10.10.102";
      linkwarden = "10.10.10.103";
      ceph = "10.10.10.105";
      objectstore = "10.10.10.106";
      searxng = "10.10.10.107";
      openwebui = "10.10.10.111";
      ntfy = "10.10.10.114";
      sftpgo = "10.10.10.115";
      sftpgoapi = "10.10.10.116";
      qbittorrent = "10.10.10.119";
      prowlarr = "10.10.10.120";
      uptimekuma = "10.10.10.122";
      libebooker = "10.10.10.123";
      glance = "10.10.10.127";
      rabbitmq = "10.10.10.139";
      nfs = "10.10.10.150";
      grafana = "10.10.10.190";
    };
  };

  namespaces = {
    monitoring = "monitoring";
    certificate = "cert-manager";
    applications = "apps";
    storage = "rook-ceph";
  };
}
