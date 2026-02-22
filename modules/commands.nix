# Nix-based CLI commands for homelab management
# All logic lives here; Makefile just calls `nix run .#<command>`
{
  pkgs,
  lib,
  deploy-rs-pkg ? null,
}:

let
  manifestsDir = ".k8s";
  lockFile = "manifests.lock";

  # Configuration
  controlPlaneIp = "10.10.10.200";
  clusterIp = "10.10.10.250";
  port = "6443";
  username = "josevictor";
  remoteKubeconfig = "/etc/rancher/k3s/k3s.yaml";
  clusterName = "ze-homelab";

  # Docker configuration
  dockerImageName = "docling-serve-rocm";
  dockerTag = "latest";
  githubUser = "josevictorferreira";
  dockerRegistry = "ghcr.io";
  dockerFullImage = "${dockerRegistry}/${githubUser}/${dockerImageName}:${dockerTag}";

  valsPkg = pkgs.vals or null;

  mkCommand =
    name: description: deps: script:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = deps;
      text = script;
      meta = { inherit description; };
    };

  # ============================================================================
  # Flake/Nix commands
  # ============================================================================

  lgroups = mkCommand "lgroups" "List available node groups" [ pkgs.nix ] ''
    nix eval --raw .#nodeGroupsList --read-only --quiet | tr ' ' '\n'
  '';

  check = mkCommand "check" "Check if the flake is valid" [ pkgs.nix pkgs.git ] ''
    git config core.hooksPath .githooks 2>/dev/null || true
    # NOTE: `--all-systems` will fail without remote builders for other systems.
    # Opt-in via ALL_SYSTEMS=1.
    if [ "''${ALL_SYSTEMS:-}" = "1" ]; then
      nix flake check --show-trace --all-systems --impure
    else
      nix flake check --show-trace --impure
    fi
  '';

  lint = mkCommand "lint" "Check nix formatting" [ pkgs.nix ] ''
    echo "Running nix formatter check..."
    if nix fmt -- --check .; then
      echo "All files are properly formatted."
    else
      echo "Some files need formatting. Run 'make format' to fix."
      exit 1
    fi
  '';

  format = mkCommand "format" "Format nix files" [ pkgs.nix ] ''
    echo "Formatting nix files..."
    nix fmt .
    echo "Formatting complete."
  '';

  # ============================================================================
  # Deploy commands
  # ============================================================================

  run_ddeploy =
    mkCommand "run-ddeploy" "Dry deploy host (interactive)" [ pkgs.nix pkgs.fzf deploy-rs-pkg ]
      ''
        AVAILABLE_NODES="$(nix eval --raw .#nodesList --read-only --quiet)"
        SEL="$(printf '%s\n' "$AVAILABLE_NODES" | tr -d '\r' | fzf --prompt='host> ' --height=40% --border --preview 'printf "%s\n" {}')"
        echo "Deploying host: $SEL"
        deploy \
          --debug-logs \
          --dry-activate \
          ".#$SEL" \
          -- \
          --impure \
          --show-trace
      '';

  run_deploy =
    mkCommand "run-deploy" "Deploy host (interactive)" [ pkgs.nix pkgs.fzf deploy-rs-pkg ]
      ''
        AVAILABLE_NODES="$(nix eval --raw .#nodesList --read-only --quiet)"
        SEL="$(printf '%s\n' "$AVAILABLE_NODES" | tr -d '\r' | fzf --prompt='host> ' --height=40% --border --preview 'printf "%s\n" {}')"
        echo "Deploying host: $SEL"
        deploy \
          --debug-logs \
          --auto-rollback true \
          ".#$SEL" \
          -- \
          --impure \
          --show-trace
      '';

  run_gdeploy =
    mkCommand "run-gdeploy" "Deploy hosts by group (interactive)" [ pkgs.nix pkgs.fzf deploy-rs-pkg ]
      ''
        AVAILABLE_GROUPS="$(nix eval --raw .#nodeGroupsList --read-only --quiet)"
        SEL="$(printf '%s\n' "$AVAILABLE_GROUPS" | tr -d '\r' | fzf --prompt='group> ' --height=40% --border --preview 'printf "%s\n" {}')"
        echo "Deploying group: $SEL"
        targets="$(nix eval --raw ".#deployGroups.$SEL")"
        echo "Targets: $targets"
        if [ "''${ALL_SYSTEMS:-}" = "1" ]; then
          nix flake check --show-trace --all-systems --impure
        else
          nix flake check --show-trace --impure
        fi
        eval "deploy --skip-checks --auto-rollback true $targets"
      '';

  # ============================================================================
  # Secrets
  # ============================================================================

  secrets =
    mkCommand "secrets" "Edit secrets files (interactive)" [ pkgs.findutils pkgs.fzf pkgs.sops ]
      ''
        SEL="$(find secrets -type f | fzf --prompt='secret> ' --height=40% --border --preview 'command -v bat >/dev/null 2>&1 && bat --style=plain --color=always {} || head -n 200 {}')"
        if [ -z "$SEL" ]; then
          echo "No file selected."
          exit 1
        fi
        echo "Opening with sops: $SEL"
        sops "$SEL"
      '';

  # ============================================================================
  # Manifests (full pipeline with git rollback)
  # ============================================================================

  manifests =
    mkCommand "manifests" "Full manifest pipeline with rollback on failure"
      (
        [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.git
          pkgs.nix
          pkgs.sops
          pkgs.yq
        ]
        ++ lib.optional (valsPkg != null) valsPkg
      )
      ''
        git config core.hooksPath .githooks 2>/dev/null || true

        # Rollback mechanism: use git checkout on failure
        ROLLBACK_NEEDED=false

        cleanup() {
          local exit_code=$?
          if [ "$ROLLBACK_NEEDED" = true ] && [ $exit_code -ne 0 ]; then
            echo ""
            echo "ERROR: Pipeline failed. Rolling back .k8s to previous state..."
            # Remove untracked .tmp files created during vals eval
            find ${manifestsDir} -type f -name '*.yaml.tmp' -delete 2>/dev/null || true
            find ${manifestsDir} -type f -name '*.yml.tmp' -delete 2>/dev/null || true
            git checkout ${manifestsDir}
            echo "Rollback complete. .k8s folder restored to git state."
          fi
        }
        trap cleanup EXIT

        vals_eval() {
          if command -v vals >/dev/null 2>&1; then
            vals eval -f "$1"
          else
            nix run nixpkgs#vals -- eval -f "$1"
          fi
        }

        ROLLBACK_NEEDED=true

        # Check if secrets file changed - if so, force regeneration
        secretsFile="secrets/k8s-secrets.enc.yaml"
        if [ -f "''${secretsFile}" ]; then
          currentSecretsSum="$(sha256sum "''${secretsFile}" | cut -d' ' -f1)"
          storedSecretsSum="$(awk -v p="__secrets_checksum__" 'BEGIN{FS="\t"} $1==p {print $2}' "${lockFile}" 2>/dev/null || true)"
          if [ "''${currentSecretsSum}" != "''${storedSecretsSum}" ]; then
            echo "Secrets file changed - forcing regeneration of all manifests"
            # Remove generated yaml files to force fresh generation
            find ${manifestsDir} -mindepth 2 -type f \
              \( -name '*.enc.yaml' -o -name '*.enc.yml' \) \
              -not -path '${manifestsDir}/flux-system/*' -delete 2>/dev/null || true
          fi
        fi

        echo "[1/4] gmanifests"
        HOMELAB_REPO_PATH="$PWD" nix build .#gen-manifests --impure --show-trace
        find ${manifestsDir} -mindepth 1 -maxdepth 1 -type d \
          ! \( -name 'flux-system' \) -exec rm -rf {} +
        cp -rf result/* ${manifestsDir}
        rm -rf result
        find ${manifestsDir} -type f -exec chmod 0644 {} +
        find ${manifestsDir} -type d -exec chmod 0755 {} +

        echo "[2/4] vmanifests"
        find ${manifestsDir} -mindepth 2 -type f \
          \( -name '*.enc.yaml' -o -name '*.enc.yml' \) \
          -not -path '${manifestsDir}/flux-system/*' -print0 \
          | while IFS= read -r -d "" f; do
            if yq -e 'select(has("sops") and (.sops.mac // "" != ""))' "''${f}" >/dev/null 2>&1; then
              echo "Skipping (already encrypted): ''${f}"
            else
              echo "Replacing ''${f}"
              vals_eval "''${f}" > "''${f}.tmp"
              if [ -s "''${f}.tmp" ]; then
                mv "''${f}.tmp" "''${f}"
                echo "Replaced ''${f}"
              else
                echo "No replacements made in ''${f}"
                rm -f "''${f}.tmp"
              fi
            fi
          done

        echo "[3/4] umanifests"
        LOCK_FILE="${lockFile}"
        touch "''${LOCK_FILE}"
        tmp="''${LOCK_FILE}.tmp"
        : > "''${tmp}"

        find ${manifestsDir} -mindepth 2 -type f \
          \( -name '*.enc.yaml' -o -name '*.enc.yml' \) \
          -not -path '${manifestsDir}/flux-system/*' -print0 \
          | while IFS= read -r -d "" f; do
            new_sum="$(sha256sum "''${f}" | cut -d' ' -f1)"
            old_sum="$(awk -v p="''${f}" 'BEGIN{FS="\t"} $1==p {print $2}' "''${LOCK_FILE}" || true)"

            if [ "''${new_sum}" = "''${old_sum}" ]; then
              if git ls-files --error-unmatch "''${f}" >/dev/null 2>&1; then
                git checkout -- "''${f}"
                echo "Restored unchanged (keeping encrypted from git): ''${f}"
              else
                echo "Unchanged (untracked, left plain): ''${f}"
              fi
            else
              echo "Changed: ''${f}"
            fi

            printf '%s\t%s\n' "''${f}" "''${new_sum}" >> "''${tmp}"
          done

        # Store secrets file checksum in lockfile for change detection
        if [ -f "''${secretsFile}" ]; then
          printf '%s\t%s\n' "__secrets_checksum__" "''${currentSecretsSum}" >> "''${tmp}"
        fi

        mv "''${tmp}" "''${LOCK_FILE}"

        echo "[4/4] emanifests"
        find ${manifestsDir} -mindepth 2 -type f \
          \( -name '*.enc.yaml' -o -name '*.enc.yml' \) \
          -not -path '${manifestsDir}/flux-system/*' -print0 \
          | while IFS= read -r -d "" f; do
            if yq -e 'select(has("sops") and (.sops.mac // "" != ""))' "''${f}" >/dev/null 2>&1; then
              echo "Skipping (already encrypted): ''${f}"
            else
              echo "Encrypting ''${f}"
              sops --encrypt --in-place "''${f}"
            fi
          done

        # Success - disable rollback
        ROLLBACK_NEEDED=false
        echo "Done."
      '';

  # ============================================================================
  # Kubernetes
  # ============================================================================

  kubesync =
    mkCommand "kubesync" "Sync kubeconfig from cluster"
      [
        pkgs.coreutils
        pkgs.openssh
        pkgs.kubectl
      ]
      ''
        LOCAL_KUBECONFIG="$HOME/.kube/config"

        kubectl config delete-user "${username}" >/dev/null 2>&1 || true
        kubectl config delete-cluster "${clusterName}" >/dev/null 2>&1 || true
        kubectl config delete-context "${clusterName}" >/dev/null 2>&1 || true

        tmpdir="$(mktemp -d)"
        tmpkc="$tmpdir/k3s.yaml"

        ssh -4 ${username}@${controlPlaneIp} "sudo cat ${remoteKubeconfig}" > "$tmpkc"

        oldctx="$(KUBECONFIG="$tmpkc" kubectl config current-context)"
        oldcluster="$(KUBECONFIG="$tmpkc" kubectl config view --raw=true -o jsonpath="{.contexts[?(@.name==\"$oldctx\")].context.cluster}")"
        olduser="$(KUBECONFIG="$tmpkc" kubectl config view --raw=true -o jsonpath="{.contexts[?(@.name==\"$oldctx\")].context.user}")"

        ca_b64="$(KUBECONFIG="$tmpkc" kubectl config view --raw=true -o jsonpath="{.clusters[?(@.name==\"$oldcluster\")].cluster.certificate-authority-data}")"
        clientcrt_b64="$(KUBECONFIG="$tmpkc" kubectl config view --raw=true -o jsonpath="{.users[?(@.name==\"$olduser\")].user.client-certificate-data}")"
        clientkey_b64="$(KUBECONFIG="$tmpkc" kubectl config view --raw=true -o jsonpath="{.users[?(@.name==\"$olduser\")].user.client-key-data}")"

        echo "$ca_b64" | base64 -d >"$tmpdir/ca.crt"
        echo "$clientcrt_b64" | base64 -d >"$tmpdir/client.crt"
        echo "$clientkey_b64" | base64 -d >"$tmpdir/client.key"

        mkdir -p "$(dirname "$LOCAL_KUBECONFIG")"
        [ -f "$LOCAL_KUBECONFIG" ] && cp "$LOCAL_KUBECONFIG" "$LOCAL_KUBECONFIG.bak" || true

        KUBECONFIG="$LOCAL_KUBECONFIG" kubectl config set-cluster "${clusterName}" --embed-certs=true --server="https://${clusterIp}:${port}" --certificate-authority="$tmpdir/ca.crt"
        KUBECONFIG="$LOCAL_KUBECONFIG" kubectl config set-credentials "${username}" --embed-certs=true --client-certificate="$tmpdir/client.crt" --client-key="$tmpdir/client.key"
        KUBECONFIG="$LOCAL_KUBECONFIG" kubectl config set-context "${clusterName}" --cluster="${clusterName}" --user="${username}"
        KUBECONFIG="$LOCAL_KUBECONFIG" kubectl config use-context "${clusterName}" >/dev/null

        chmod 600 "$LOCAL_KUBECONFIG"
        rm -rf "$tmpdir"

        echo "OK: cluster/user/context written -> $LOCAL_KUBECONFIG"
      '';

  reconcile = mkCommand "reconcile" "Reconcile flux with main branch" [ pkgs.fluxcd ] ''
    flux reconcile kustomization flux-system -n flux-system --with-source
  '';

  events = mkCommand "events" "Watch flux events" [ pkgs.fluxcd ] ''
    flux events --watch
  '';

  # ============================================================================
  # USB ISO
  # ============================================================================

  wusbiso =
    mkCommand "wusbiso" "Build and write recovery ISO to USB"
      [
        pkgs.coreutils
        pkgs.nix
        pkgs.gptfdisk
        pkgs.util-linux
      ]
      ''
        if [ -d result/iso ]; then
          echo "Recovery ISO already built. Skipping build."
        else
          echo "Building recovery ISO..."
          nix build .#nixosConfigurations.recovery-iso.config.system.build.isoImage
        fi

        ISO="$(readlink -f result/iso/recovery-iso-*.iso)"
        DEV="$(readlink -f /dev/disk/by-id/usb-* 2>/dev/null || true)"

        echo "Recovery ISO: $ISO"

        if [ -z "$DEV" ]; then
          echo "No USB drive found. Please connect a USB drive and try again."
          exit 1
        fi

        sudo sgdisk --zap-all "$DEV"
        sudo wipefs -a "$DEV"
        sudo blkdiscard -f "$DEV" || true
        sudo dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync
        sync

        echo "Recovery ISO written to $DEV"
        sudo eject "$DEV" 2>/dev/null || true
        echo "Done. You can now boot from the USB drive."
      '';

  # ============================================================================
  # Docker
  # ============================================================================

  docker-build = mkCommand "docker-build" "Build Docker image" [ pkgs.nix pkgs.docker ] ''
    echo "Building Docker image ${dockerImageName}:${dockerTag}..."
    nix-build oci-images/${dockerImageName}.nix && docker load < result
    echo "Tagging image as ${dockerFullImage}..."
    docker tag localhost/${dockerImageName}:${dockerTag} ${dockerFullImage}
    echo "Image built and tagged successfully: ${dockerFullImage}"
  '';

  docker-login =
    mkCommand "docker-login" "Login to GitHub Container Registry" [ pkgs.docker pkgs.gh ]
      ''
        if [ -n "''${GITHUB_TOKEN:-}" ]; then
          echo "Logging in using GITHUB_TOKEN..."
          echo "$GITHUB_TOKEN" | docker login ${dockerRegistry} -u ${githubUser} --password-stdin
          echo "Successfully authenticated with GITHUB_TOKEN"
        elif command -v gh >/dev/null 2>&1; then
          echo "Logging in using GitHub CLI..."
          GH_TOKEN="$(gh auth token)"
          if [ -n "$GH_TOKEN" ]; then
            echo "$GH_TOKEN" | docker login ${dockerRegistry} -u ${githubUser} --password-stdin
            echo "Successfully authenticated with GitHub CLI"
          else
            echo "GitHub CLI not authenticated. Please run: gh auth login"
            exit 1
          fi
        else
          echo "Error: Neither GitHub CLI nor GITHUB_TOKEN is available"
          echo "Please install GitHub CLI or set GITHUB_TOKEN environment variable"
          exit 1
        fi
      '';

  docker-init-repo =
    mkCommand "docker-init-repo" "Initialize GitHub Container Registry repo" [ pkgs.gh ]
      ''
        echo "Checking if repository exists..."
        if gh api /user/packages/container/${dockerImageName} >/dev/null 2>&1; then
          echo "Repository already exists"
        else
          echo "Creating repository using GitHub CLI..."
          if gh api --method POST \
              -H "Accept: application/vnd.github.v3+json" \
              /user/packages \
              -f name='${dockerImageName}' \
              -f package_type='container' \
              -f visibility='public'; then
            echo "Repository created successfully"
          else
            echo "Will try to create repository on first push instead"
          fi
        fi
      '';

  docker-push =
    mkCommand "docker-push" "Build and push Docker image to GHCR" [ pkgs.nix pkgs.docker pkgs.gh ]
      ''
                # Build
                echo "Building Docker image ${dockerImageName}:${dockerTag}..."
        nix-build oci-images/${dockerImageName}.nix && docker load < result
                echo "Tagging image as ${dockerFullImage}..."
                docker tag localhost/${dockerImageName}:${dockerTag} ${dockerFullImage}
                echo "Image built and tagged successfully: ${dockerFullImage}"

                # Login
                if [ -n "''${GITHUB_TOKEN:-}" ]; then
                  echo "Logging in using GITHUB_TOKEN..."
                  echo "$GITHUB_TOKEN" | docker login ${dockerRegistry} -u ${githubUser} --password-stdin
                elif command -v gh >/dev/null 2>&1; then
                  echo "Logging in using GitHub CLI..."
                  GH_TOKEN="$(gh auth token)"
                  if [ -n "$GH_TOKEN" ]; then
                    echo "$GH_TOKEN" | docker login ${dockerRegistry} -u ${githubUser} --password-stdin
                  else
                    echo "GitHub CLI not authenticated. Please run: gh auth login"
                    exit 1
                  fi
                else
                  echo "Error: Neither GitHub CLI nor GITHUB_TOKEN is available"
                  exit 1
                fi

                # Init repo
                echo "Checking if repository exists..."
                if ! gh api /user/packages/container/${dockerImageName} >/dev/null 2>&1; then
                  gh api --method POST \
                    -H "Accept: application/vnd.github.v3+json" \
                    /user/packages \
                    -f name='${dockerImageName}' \
                    -f package_type='container' \
                    -f visibility='public' || true
                fi

                # Push
                echo "Pushing image to ${dockerFullImage}..."
                docker push ${dockerFullImage}
                echo "Image pushed successfully to ${dockerFullImage}"
                echo "Image is now public at: https://${dockerRegistry}/${githubUser}/${dockerImageName}"
      '';

  # ============================================================================
  # Postgres backup/restore
  # ============================================================================

  backup-postgres = mkCommand "backup-postgres" "Backup all postgresql data" [ pkgs.postgresql ] ''
    mkdir -p /tmp/backup
    pg_dumpall -h 10.10.10.101 -U postgres -f /tmp/backup/full_backup.sql
    echo "Backup saved to /tmp/backup/full_backup.sql"
  '';

  restore-postgres = mkCommand "restore-postgres" "Restore postgresql backup" [ pkgs.postgresql ] ''
    psql -h 10.10.10.133 -U postgres -f /tmp/backup/full_backup.sql
    echo "Restore complete"
  '';

  # ============================================================================
  # Image Updater (imported from modules/commands/image-updater.nix)
  # ============================================================================

  imageCommands = import ./commands/image-updater.nix { inherit pkgs lib; };
  inherit (imageCommands) image-scan image-outdated image-updater;

  # ============================================================================
  # OpenClaw Container Image
  # ============================================================================

  # OpenClaw image configuration
  openclawImageName = "openclaw-nix";
  openclawRegistry = "ghcr.io";

  push-openclaw =
    mkCommand "push-openclaw" "Build and push openclaw-nix image to GHCR"
      [ pkgs.nix pkgs.podman pkgs.gh pkgs.coreutils ]
      ''
        set -e

        IMAGE_NAME="${openclawImageName}"
        REGISTRY="${openclawRegistry}"
        GITHUB_USER="${githubUser}"
        LOCAL_TAG="localhost/''${IMAGE_NAME}:dev"
        FULL_TAG="''${REGISTRY}/''${GITHUB_USER}/''${IMAGE_NAME}:latest"

        # Build
        echo "[1/4] Building ''${IMAGE_NAME}..."
        nix build .#''${IMAGE_NAME}-image --show-trace

        # Load into podman
        echo "[2/4] Loading image into podman..."
        ./result | podman load
        rm -f result

        # Tag for registry
        echo "[3/3] Tagging as ''${FULL_TAG}..."
        podman tag "''${LOCAL_TAG}" "''${FULL_TAG}"

        # Login
        echo "[4/4] Logging in to ''${REGISTRY}..."
        if [ -n "''${GITHUB_TOKEN:-}" ]; then
          echo "$GITHUB_TOKEN" | podman login "''${REGISTRY}" -u "''${GITHUB_USER}" --password-stdin
        elif command -v gh >/dev/null 2>&1; then
          GH_TOKEN="$(gh auth token)"
          if [ -n "$GH_TOKEN" ]; then
            echo "$GH_TOKEN" | podman login "''${REGISTRY}" -u "''${GITHUB_USER}" --password-stdin
          else
            echo "GitHub CLI not authenticated. Run: gh auth login"
            exit 1
          fi
        else
          echo "Error: Neither gh CLI nor GITHUB_TOKEN available"
          exit 1
        fi

        # Push
        echo "Pushing to ''${FULL_TAG}..."
        podman push "''${FULL_TAG}"

        echo ""
        echo "✓ Image pushed: ''${FULL_TAG}"
        echo "  View at: https://''${REGISTRY}/''${GITHUB_USER}/''${IMAGE_NAME}"
      '';

  ghcr-size =
    mkCommand "ghcr-size" "Check GHCR image compressed size without downloading"
      [ pkgs.skopeo pkgs.python3 pkgs.coreutils ]
      ''
                set -e

                IMAGE="''${1:?Usage: ghcr-size <user/package:tag>}"
                REGISTRY="ghcr.io"

                # Add ghcr.io prefix if not already a full URL
                case "$IMAGE" in
                  ghcr.io/*) REF="docker://''${IMAGE}" ;;
                  *) REF="docker://''${REGISTRY}/''${IMAGE}" ;;
                esac

                echo "Inspecting ''${REF}..."
                skopeo inspect --raw "''${REF}" | python3 -c '
        import json, sys
        m = json.load(sys.stdin)

        # Handle manifest list (multi-arch) — pick first manifest and inspect it
        if m.get("mediaType", "") in ("application/vnd.oci.image.index.v1+json", "application/vnd.docker.distribution.manifest.list.v2+json"):
            manifests = m.get("manifests", [])
            print(f"Multi-arch image with {len(manifests)} platform(s):")
            for mf in manifests:
                p = mf.get("platform", {})
                arch = p.get("architecture", "?")
                os_name = p.get("os", "?")
                size = mf.get("size", 0)
                print(f"  {os_name}/{arch} - {size} bytes (manifest)")
            print()
            print("Tip: specify platform with skopeo --override-os/--override-arch")
            sys.exit(0)

        layers = m.get("layers", [])
        config = m.get("config", {})
        config_size = config.get("size", 0) if config else 0
        total = sum(l.get("size", 0) for l in layers) + config_size

        if total >= 1024**3:
            human = f"{total / 1024**3:.2f} GB"
        elif total >= 1024**2:
            human = f"{total / 1024**2:.1f} MB"
        else:
            human = f"{total / 1024:.1f} KB"

        print(f"Compressed size: {human} ({total:,} bytes)")
        print(f"Layers: {len(layers)}")
        '
      '';

in
{
  inherit
    lgroups
    check
    lint
    format
    run_ddeploy
    run_deploy
    run_gdeploy
    secrets
    manifests
    kubesync
    reconcile
    events
    wusbiso
    docker-build
    docker-login
    docker-init-repo
    docker-push
    backup-postgres
    restore-postgres
    image-scan
    image-outdated
    image-updater
    push-openclaw
    ghcr-size
    ;
}
