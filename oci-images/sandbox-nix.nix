{ pkgs, lib }:

let
  baseImage = pkgs.dockerTools.pullImage {
    imageName = "docker.io/nixos/nix";
    imageDigest = "sha256:c03c1081ba8fb98528dee2a677dee6f42bdddb6b90e1c14c67aba8c1e31ed4bb";
    sha256 = "sha256-ekinN9wDMCgwT3fR3mrpuyEkCIjz/7CHxqzqTNf1/eM=";
  };

  # Tools to overlay on top of the nixos/nix base image.
  toolPkgs = with pkgs; [
    openssh
    git
    cacert
    glibcLocales
    gnutar
    gzip
    xz
    curl
    shadow
    hostname
  ];

  toolsEnv = pkgs.buildEnv {
    name = "sandbox-nix-tools-env";
    paths = toolPkgs;
    pathsToLink = [ "/bin" ];
  };

  toolsRoot = pkgs.runCommand "sandbox-nix-tools-root" { } ''
    mkdir -p $out/usr/bin
    for f in ${toolsEnv}/bin/*; do
      [ -e "$f" ] || continue
      name=$(basename "$f")
      [ -e "$out/usr/bin/$name" ] && continue
      ln -s "$f" "$out/usr/bin/$name"
    done
  '';

  # SSH host keys are generated at runtime so they persist across restarts on
  # the /nix PVC.  We only pre-bake the sshd configuration; a locked-down
  # authorized_keys file is injected via a Kubernetes Secret.
  sshdConfig = pkgs.writeText "sshd_config" ''
    Port 22
    AddressFamily any
    ListenAddress 0.0.0.0
    ListenAddress ::

    PermitRootLogin no
    PasswordAuthentication no
    PubkeyAuthentication yes
    AuthenticationMethods publickey
    AllowUsers hermes-agent

    HostKey /etc/ssh/ssh_host_ed25519_key
    HostKey /etc/ssh/ssh_host_rsa_key

    UsePAM no
    PidFile /run/sshd.pid
    SetEnv PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin

    # Lock the worker down to a single non-root user and workspace.
    Match User hermes-agent
      AuthorizedKeysFile /etc/ssh/authorized_keys
  '';

  entrypoint = pkgs.writeScript "entrypoint.sh" ''
    #!${pkgs.runtimeShell}
    set -euo pipefail

    # The base image PATH only points at the nix profiles, which are empty on
    # the mounted /nix PVC.  Our overlaid tools live in /usr/bin, so make sure
    # they resolve for bare command names below (groupadd, useradd, hostname).
    export PATH=/usr/bin:''${PATH:-}

    # Generate host keys if they don't exist yet so restarts are stable.
    mkdir -p /etc/ssh
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
      ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -C "sandbox-nix@$(hostname)"
    fi
    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
      ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" -C "sandbox-nix@$(hostname)"
    fi

    # The base nixos/nix image symlinks /etc/{group,passwd} into a read-only
    # nix store path, so groupadd/useradd cannot modify them (ELOOP / read-only).
    # Replace them with real writable copies before creating the user.
    for f in group passwd shadow gshadow; do
      if [ -L /etc/$f ] || [ ! -f /etc/$f ]; then
        tmp="$(cat /etc/$f 2>/dev/null || true)"
        rm -f /etc/$f
        printf '%s\n' "$tmp" > /etc/$f
        chmod 644 /etc/$f
      fi
    done
    chmod 600 /etc/shadow /etc/gshadow 2>/dev/null || true

    # Create the hermes-agent user if it doesn't exist.  Use a fixed UID/GID so
    # permissions on the CephFS workspace are predictable across restarts.
    if ! id hermes-agent >/dev/null 2>&1; then
      groupadd -g 10000 hermes-agent
      useradd -u 10000 -g hermes-agent -d /workspace -s ${pkgs.bash}/bin/bash -m hermes-agent
    fi
    # useradd creates a locked shadow entry (`!`), and OpenSSH rejects locked
    # accounts before checking public keys.  Keep password login disabled in
    # sshd_config, but mark the account as non-password-authenticatable (`*`) so
    # public-key auth can proceed.
    if grep -q '^hermes-agent:!' /etc/shadow; then
      tmp="$(mktemp)"
      while IFS= read -r line; do
        case "$line" in
          hermes-agent:!*) printf 'hermes-agent:*%s\n' "''${line#hermes-agent:!}" ;;
          *) printf '%s\n' "$line" ;;
        esac
      done < /etc/shadow > "$tmp"
      cat "$tmp" > /etc/shadow
      rm -f "$tmp"
      chmod 600 /etc/shadow
    fi

    # sshd requires a privilege-separation user 'sshd' and its empty chroot dir.
    if ! id sshd >/dev/null 2>&1; then
      useradd -u 74 -r -s /usr/bin/nologin -d /var/empty -M sshd 2>/dev/null || \
        useradd -r -s /usr/bin/nologin -d /var/empty -M sshd
    fi
    mkdir -p /var/empty
    chmod 755 /var/empty

    # Ensure workspace is writable by the hermes-agent user.  The CephFS mount is
    # group-managed via GID 2002; the worker also needs to traverse it.
    chown -R 10000:2002 /workspace 2>/dev/null || true

    # Start sshd in the foreground so the pod stays alive.
    exec /usr/bin/sshd -D -f /etc/ssh/sshd_config
  '';

in
pkgs.dockerTools.buildImage {
  name = "localhost/sandbox-nix";
  tag = "0.1.0";
  fromImage = baseImage;
  copyToRoot = [
    toolsRoot
    (pkgs.runCommand "sandbox-nix-etc" { } ''
      mkdir -p $out/etc/ssh
      cp ${sshdConfig} $out/etc/ssh/sshd_config
      cp ${entrypoint} $out/entrypoint.sh
    '')
  ];
  config = {
    Entrypoint = [ "/entrypoint.sh" ];
    User = "0";
  };
}
