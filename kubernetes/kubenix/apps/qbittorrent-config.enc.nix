{ homelab, kubenix, ... }:

let
  qbtConf = ''
    [AutoRun]
    enabled=false
    program=

    [BitTorrent]
    Session\AddTorrentStopped=false
    Session\AsyncIOThreadsCount=10
    Session\DiskCacheSize=-1
    Session\DiskIOReadMode=DisableOSCache
    Session\DiskIOType=SimplePreadPwrite
    Session\DiskIOWriteMode=EnableOSCache
    Session\DiskQueueSize=4194304
    Session\FilePoolSize=40
    Session\HashingThreadsCount=2
    Session\Port=62657
    Session\QueueingSystemEnabled=true
    Session\ResumeDataStorageType=SQLite
    Session\SSL\Port=4364
    Session\ShareLimitAction=Stop
    Session\UseOSCache=true
    Session\UseRandomPort=false

    [LegalNotice]
    Accepted=true

    [Meta]
    MigrationVersion=8

    [Network]
    Cookies=@Invalid()
    PortForwardingEnabled=false
    Proxy\HostnameLookupEnabled=false
    Proxy\Profiles\BitTorrent=true
    Proxy\Profiles\Misc=true
    Proxy\Profiles\RSS=true

    [Preferences]
    Connection\PortRangeMin=6881
    Connection\UPnP=false
    General\Locale=en
    General\UseRandomPort=false
    WebUI\Address=*
    WebUI\CSRFProtection=false
    WebUI\HostHeaderValidation=false
    WebUI\LocalHostAuth=false
    WebUI\Password_PBKDF2='PBKDF2$sha512$100000$lhlkLd134xQEpKC0KxmAFw==$qerzYLduO7zOydTrbfmK8EIJqVEEDHMDi/dOSOZjvc+7qjpHsKr3oXk1qD1m9OpmLnoSv/fWQnx8piPUolrKSA=='
    WebUI\Port=8080
    WebUI\ServerDomains=*
    WebUI\UseUPnP=false
  '';
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      configMaps."qbittorrent-config" = {
        metadata = {
          name = "qbittorrent-config";
          namespace = namespace;
        };
        data."qBittorrent.conf" = qbtConf;
      };
    };
  };
}
