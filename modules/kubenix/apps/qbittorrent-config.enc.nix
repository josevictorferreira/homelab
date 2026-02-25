{ lib, homelab, kubenix, ... }:

let
  categories = [ "books" "games" "movies" "nsfw" "other" "sports" "tv" ];
  qbtConf = ''
    [Application]
    FileLogger\Age=1
    FileLogger\AgeType=1
    FileLogger\Backup=true
    FileLogger\DeleteOld=true
    FileLogger\Enabled=true
    FileLogger\MaxSizeBytes=66560
    FileLogger\Path=/config/qBittorrent/logs

    [AutoRun]
    enabled=false
    program=

    [BitTorrent]
    Session\AddExtensionToIncompleteFiles=true
    Session\AddTorrentStopped=false
    Session\AddTorrentToTopOfQueue=false
    Session\AlternativeGlobalUPSpeedLimit=10000
    Session\AnonymousModeEnabled=true
    Session\AsyncIOThreadsCount=10
    Session\DefaultSavePath=/downloads/complete
    Session\DisableAutoTMMByDefault=false
    Session\DisableAutoTMMTriggers\CategorySavePathChanged=false
    Session\DisableAutoTMMTriggers\DefaultSavePathChanged=false
    Session\DiskCacheSize=-1
    Session\DiskIOReadMode=DisableOSCache
    Session\DiskIOType=SimplePreadPwrite
    Session\DiskIOWriteMode=EnableOSCache
    Session\DiskQueueSize=4194304
    Session\ExcludedFileNames=
    Session\FilePoolSize=40
    Session\FinishedTorrentExportDirectory=/downloads/backup
    Session\HashingThreadsCount=2
    Session\Interface=tun0
    Session\InterfaceName=tun0
    Session\LSDEnabled=false
    Session\MaxActiveCheckingTorrents=3
    Session\MaxActiveDownloads=5
    Session\MaxActiveTorrents=15
    Session\MaxActiveUploads=10
    Session\MaxConnections=-1
    Session\MaxConnectionsPerTorrent=-1
    Session\MaxUploads=-1
    Session\MaxUploadsPerTorrent=-1
    Session\Port=62657
    Session\QueueingSystemEnabled=true
    Session\ReannounceWhenAddressChanged=true
    Session\ResumeDataStorageType=SQLite
    Session\SSL\Port=30429
    Session\ShareLimitAction=Stop
    Session\Tags=${lib.concatStringsSep ", " categories}
    Session\TempPath=/downloads/temp
    Session\TempPathEnabled=true
    Session\TorrentExportDirectory=/downloads/backup
    Session\UseCategoryPathsInManualMode=true
    Session\UseOSCache=true
    Session\UseRandomPort=false

    [Core]
    AutoDeleteAddedTorrentFile=Never

    [LegalNotice]
    Accepted=true

    [Meta]
    MigrationVersion=8

    [Network]
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
    MailNotification\req_auth=true
    WebUI\Address=*
    WebUI\AlternativeUIEnabled=true
    WebUI\AuthSubnetWhitelist=@Invalid()
    WebUI\CSRFProtection=false
    WebUI\HostHeaderValidation=false
    WebUI\LocalHostAuth=false
    WebUI\Password_PBKDF2="${kubenix.lib.secretsFor "qbt_password_hash"}"
    WebUI\Port=8080
    WebUI\RootFolder=/config/webui/vuetorrent
    WebUI\ServerDomains=*
    WebUI\UseUPnP=false
    WebUI\Username=josevictor

    [RSS]
    AutoDownloader\DownloadRepacks=true
    AutoDownloader\SmartEpisodeFilter=s(\\d+)e(\\d+), (\\d+)x(\\d+), "(\\d{4}[.\\-]\\d{1,2}[.\\-]\\d{1,2})", "(\\d{1,2}[.\\-]\\d{1,2}[.\\-]\\d{4})"
  '';
  watchedDownloadsConf = {
    "/downloads/monitor" = {
      "add_torrent_params" = {
        "category" = "";
        "download_limit" = -1;
        "download_path" = "";
        "inactive_seeding_time_limit" = -2;
        "operating_mode" = "AutoManaged";
        "ratio_limit" = -2;
        "save_path" = "";
        "seeding_time_limit" = -2;
        "share_limit_action" = "Default";
        "skip_checking" = false;
        "ssl_certificate" = "";
        "ssl_dh_params" = "";
        "ssl_private_key" = "";
        "tags" = [
        ];
        "upload_limit" = -1;
      };
      "recursive" = false;
    };
  };
  categoriesConf = {
    books = {
      "color" = "#ff9900";
      "save_path" = "/downloads/books";
      "sort" = 0;
    };
    games = {
      "color" = "#ff33cc";
      "save_path" = "/downloads/games";
      "sort" = 1;
    };
    movies = {
      "color" = "#33ccff";
      "save_path" = "/downloads/movies";
      "sort" = 2;
    };
    nsfw = {
      "color" = "#ff0066";
      "save_path" = "/downloads/nsfw";
      "sort" = 3;
    };
    other = {
      "color" = "#cccccc";
      "save_path" = "/downloads/other";
      "sort" = 9;
    };
    sports = {
      "color" = "#66ff66";
      "save_path" = "/downloads/sports";
      "sort" = 5;
    };
    tv = {
      "color" = "#ffff66";
      "save_path" = "/downloads/tv";
      "sort" = 6;
    };
  };

  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      configMaps."qbittorrent-config" = {
        metadata = {
          name = "qbittorrent-config";
          inherit namespace;
        };
        data = {
          "qBittorrent.conf" = qbtConf;
          "watched_folders.json" = builtins.toJSON watchedDownloadsConf;
          "categories.json" = builtins.toJSON categoriesConf;
        };
      };
    };
  };
}
