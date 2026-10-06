# Shared pieces of the CNPG Cluster spec, used by both the rehearsal cluster
# (Phase 4) and the final cluster (Phase 5). Not a kubenix module.
{
  image = "ghcr.io/josevictorferreira/postgresql-cnpg:18.6-vchord1.1.1-postgis3@sha256:5b3c66d10a39ff0c4a70f4908fc1e8c1c4d4f2a03f517cb5d7dec39b44eacea2";

  storage = {
    size = "40Gi";
    storageClass = "rook-ceph-block";
  };

  walStorage = {
    size = "8Gi";
    storageClass = "rook-ceph-block";
  };

  resources = {
    requests = {
      cpu = "250m";
      memory = "1Gi";
    };
    limits = {
      cpu = "1";
      memory = "3Gi";
    };
  };

  # Ported from postgresql-18 extendedConfiguration. Keys CNPG manages itself
  # (logging_collector, wal_level, wal_keep_size, archive_*) are omitted.
  postgresql = {
    shared_preload_libraries = [ "vchord.so" ];
    parameters = {
      search_path = "\"$user\", public, vectors";
      max_wal_size = "2GB";
      min_wal_size = "512MB";
      shared_buffers = "768MB";
      wal_buffers = "32MB";
      wal_compression = "on";
      checkpoint_timeout = "30min";
      checkpoint_completion_target = "0.9";
      effective_cache_size = "2304MB";
      work_mem = "16MB";
      maintenance_work_mem = "512MB";
      synchronous_commit = "off";
      autovacuum_max_workers = "5";
      # 2026-09-16: all apps connect as the superuser, so the default 100
      # slots were exhausted (even the local socket) within hours of cutover.
      max_connections = "300";
      # Same client-hygiene settings the old instance had (added 2026-09-15
      # after leaked idle sessions filled max_connections).
      tcp_keepalives_idle = "60";
      tcp_keepalives_interval = "10";
      tcp_keepalives_count = "3";
      idle_session_timeout = "2h";
      autovacuum_naptime = "10s";
      autovacuum_vacuum_cost_delay = "10ms";
      autovacuum_vacuum_cost_limit = "2000";
      log_min_duration_statement = "2000";
      # 2026-10-06: slow statements were logged with their bind parameters in
      # full (default -1 = unlimited). A 60 MB bytea UPDATE became a 62 MB hex
      # log line, built in the backend and re-parsed by the CNPG instance
      # manager in the same container: repeated OOM kills at the 3Gi limit.
      log_parameter_max_length = "1024";
      log_parameter_max_length_on_error = "1024";
      # Autovacuum otherwise inherits maintenance_work_mem (512MB) per worker:
      # 5 workers could claim 2.5GB on top of shared_buffers under a 3Gi limit.
      autovacuum_work_mem = "128MB";
      log_checkpoints = "on";
    };
  };

  # Logical import of every database and role from the running Bitnami instance.
  # Only valid at first creation; CNPG ignores bootstrap afterwards.
  importFromPostgresql18 = {
    bootstrap.initdb = {
      dataChecksums = true;
      import = {
        type = "monolith";
        databases = [ "*" ];
        roles = [ "*" ];
        source.externalCluster = "postgresql-18";
        pgDumpExtraOptions = [ "--jobs=2" ];
        pgRestoreExtraOptions = [ "--jobs=2" ];
      };
    };
    externalClusters = [
      {
        name = "postgresql-18";
        connectionParameters = {
          host = "postgresql-18-hl.apps.svc.cluster.local";
          user = "postgres";
          dbname = "postgres";
          sslmode = "disable";
        };
        password = {
          name = "postgresql-superuser";
          key = "password";
        };
      }
    ];
  };
}
