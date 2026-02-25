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
      immich = "10.10.10.108";
      scriberr = "10.10.10.109";
      openwebui = "10.10.10.111";
      n8n = "10.10.10.112";
      alarm-server = "10.10.10.113";
      ntfy = "10.10.10.114";
      sftpgo = "10.10.10.115";
      sftpgoapi = "10.10.10.116";
      whisperwebui = "10.10.10.117";
      youtube-transcriber = "10.10.10.118";
      qbittorrent = "10.10.10.119";
      prowlarr = "10.10.10.120";
      docling = "10.10.10.121";
      uptimekuma = "10.10.10.122";
      libebooker = "10.10.10.123";
      mcpo = "10.10.10.126";
      glance = "10.10.10.127";
      ollama = "10.10.10.128";
      llama-cpp = "10.10.10.129";
      openrouter-proxy = "10.10.10.130";
      valoris-backend = "10.10.10.131";
      valoris-worker = "10.10.10.132";
      postgresql-18 = "10.10.10.133";
      valoris = "10.10.10.134";
      imgproxy = "10.10.10.135";
      qui = "10.10.10.136";
      matrix = "10.10.10.138";
      rabbitmq = "10.10.10.139";
      openclaw = "10.10.10.140";
      openclaw-nix = "10.10.10.141";
      nfs = "10.10.10.150";
      grafana = "10.10.10.190";
    };
  };

  databases = {
    postgres = [
      "linkwarden"
      "openwebui"
      "n8n"
      "immich"
      "valoris_production"
      "valoris_production_queue"
      "keycloak"
      "synapse"
      "mautrix_slack"
      "mautrix_discord"
      "mautrix_whatsapp"
    ];
  };

  namespaces = {
    monitoring = "monitoring";
    certificate = "cert-manager";
    applications = "apps";
    storage = "rook-ceph";
    backup = "backup";
  };
}
