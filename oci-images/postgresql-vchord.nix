{ pkgs ? import <nixpkgs> { }
,
}:
let
  inherit (pkgs) dockerTools;
  postgresql = pkgs.postgresql_17;
  pgvector = postgresql.passthru.pkgs.pgvector;

  # Download VectorChord .deb from GitHub releases and extract extension files
  vectorchordDeb = pkgs.fetchurl {
    url = "https://github.com/tensorchord/VectorChord/releases/download/0.5.3/postgresql-17-vchord_0.5.3-1_amd64.deb";
    sha256 = "sha256-0nkQuq+G3lKvGeJanWGY3+zx2+UIZAdbCpOGzcfeLJs=";
  };

  # Extract .deb package (ar archive containing data.tar.xz)
  vectorchord =
    pkgs.runCommand "vectorchord-extracted"
      {
        nativeBuildInputs = [
          pkgs.binutils-unwrapped
          pkgs.xz
          pkgs.gnutar
        ];
      }
      ''
        mkdir -p $out/lib $out/share/postgresql/extension

        # Extract .deb (it's an ar archive)
        mkdir -p /tmp/deb-extract
        cd /tmp/deb-extract
        ar x ${vectorchordDeb}

        # Extract data.tar.* (could be .xz, .gz, or .zst)
        if [ -f data.tar.xz ]; then
          tar xf data.tar.xz
        elif [ -f data.tar.gz ]; then
          tar xf data.tar.gz
        elif [ -f data.tar.zst ]; then
          ${pkgs.zstd}/bin/zstd -d data.tar.zst | tar xf -
        fi

        # Copy extension files from the deb package
        # The deb installs to /usr/lib/postgresql/17/lib/ and /usr/share/postgresql/17/extension/
        find . -name "vchord.so" -exec cp {} $out/lib/ \;
        find . -name "vchord*.control" -exec cp {} $out/share/postgresql/extension/ \;
        find . -name "vchord--*.sql" -exec cp {} $out/share/postgresql/extension/ \;

        # Verify
        ls -la $out/lib/ $out/share/postgresql/extension/
      '';

  # Merge PostgreSQL with extensions into a single rootfs layout
  postgresqlWithExtensions = pkgs.runCommand "postgresql-with-extensions" { } ''
    mkdir -p $out/bin $out/lib $out/share/postgresql/extension

    # Copy PostgreSQL binaries
    cp -rL ${postgresql}/bin/* $out/bin/ 2>/dev/null || true

    # Copy PostgreSQL libraries
    cp -rL ${postgresql}/lib/* $out/lib/ 2>/dev/null || true

    # Copy PostgreSQL extension files
    cp -rL ${postgresql}/share/postgresql/extension/* $out/share/postgresql/extension/ 2>/dev/null || true

    # Copy pgvector extension files
    cp -rL ${pgvector}/lib/* $out/lib/ 2>/dev/null || true
    cp -rL ${pgvector}/share/postgresql/extension/* $out/share/postgresql/extension/ 2>/dev/null || true

    # Copy vectorchord extension files
    cp -rL ${vectorchord}/lib/* $out/lib/ 2>/dev/null || true
    cp -rL ${vectorchord}/share/postgresql/extension/* $out/share/postgresql/extension/ 2>/dev/null || true
  '';
in
dockerTools.buildImage {
  name = "ghcr.io/josevictorferreira/postgresql-vchord";
  tag = "17.6-pgvector0.8.2-vchord0.5.3";

  copyToRoot = pkgs.buildEnv {
    name = "rootfs";
    paths = [
      postgresqlWithExtensions
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert
      pkgs.gnugrep
      pkgs.gawk
      pkgs.gnutar
      pkgs.gzip
      pkgs.less
      pkgs.procps
      pkgs.findutils
      pkgs.which
      pkgs.tzdata
    ];
    pathsToLink = [
      "/bin"
      "/lib"
      "/share"
      "/etc"
    ];
  };

  extraCommands = ''
    # Ensure tmp directories exist and are world-writable
    mkdir -p ./tmp ./var/tmp
    chmod 1777 ./tmp ./var/tmp

    # Create symlinks for common paths
    mkdir -p ./usr/bin ./usr/lib
    ln -sf /bin ./usr/bin/postgresql 2>/dev/null || true
    ln -sf /lib ./usr/lib/postgresql 2>/dev/null || true

    # Ensure /usr/bin/env exists for shebangs
    ln -sf /bin/env ./usr/bin/env 2>/dev/null || true

    # Create /bin/sh symlink
    ln -sf /bin/bash ./bin/sh 2>/dev/null || true

    # Set up timezone
    mkdir -p ./usr/share
    ln -sf /share/zoneinfo ./usr/share/zoneinfo 2>/dev/null || true
    ln -sf /share/zoneinfo/America/Sao_Paulo ./etc/localtime 2>/dev/null || true
  '';

  config = {
    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "PATH=/bin"
      "HOME=/tmp"
      "TZ=America/Sao_Paulo"
    ];
    WorkingDir = "/tmp";
    Cmd = [ "/bin/bash" ];
    ExposedPorts = {
      "5432/tcp" = { };
    };
  };
}
