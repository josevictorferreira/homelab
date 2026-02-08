# Nix-based CLI commands for homelab management
# Provides typed, reproducible commands with proper dependencies
{ pkgs, lib }:

let
  manifestsDir = ".k8s";
  lockFile = "manifests.lock";

  # Check if vals is available in pkgs
  valsPkg = pkgs.vals or null;

  mkCommand =
    name: description: deps: script:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = deps;
      text = script;
      meta = { inherit description; };
    };

  # Individual manifest stages
  gmanifests =
    mkCommand "gmanifests" "Generate k8s manifests from kubenix"
      [ pkgs.coreutils pkgs.findutils pkgs.nix ]
      ''
        set -euo pipefail
        HOMELAB_REPO_PATH="$PWD" nix build .#gen-manifests --impure --show-trace
        find ${manifestsDir} -mindepth 1 -maxdepth 1 -type d \
          ! \( -name 'flux-system' \) -exec rm -rf {} +
        cp -rf result/* ${manifestsDir}
        rm -rf result
        find ${manifestsDir} -type f -exec chmod 0644 {} +
        find ${manifestsDir} -type d -exec chmod 0755 {} +
      '';

  vmanifests =
    mkCommand "vmanifests" "Inject secrets using vals"
      (
        [
          pkgs.coreutils
          pkgs.findutils
          pkgs.yq
        ]
        ++ lib.optional (valsPkg != null) valsPkg
      )
      ''
        set -euo pipefail

        vals_eval() {
          if command -v vals >/dev/null 2>&1; then
            vals eval -f "$1"
          else
            nix run nixpkgs#vals -- eval -f "$1"
          fi
        }

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
      '';

  umanifests =
    mkCommand "umanifests" "Restore unchanged encrypted files from git"
      [ pkgs.coreutils pkgs.findutils pkgs.gawk pkgs.git ]
      ''
        set -euo pipefail
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

        mv "''${tmp}" "''${LOCK_FILE}"
      '';

  emanifests =
    mkCommand "emanifests" "Encrypt manifests with sops"
      [ pkgs.coreutils pkgs.findutils pkgs.sops pkgs.yq ]
      ''
        set -euo pipefail
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
      '';

  # Combined manifests command with rollback protection
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
        set -euo pipefail

        # Rollback mechanism: backup .k8s state before modifications
        BACKUP_DIR="$(mktemp -d)"
        ROLLBACK_NEEDED=false

        cleanup() {
          local exit_code=$?
          if [ "$ROLLBACK_NEEDED" = true ] && [ $exit_code -ne 0 ]; then
            echo ""
            echo "ERROR: Pipeline failed. Rolling back .k8s to previous state..."
            rm -rf ${manifestsDir}/*
            cp -rf "$BACKUP_DIR"/* ${manifestsDir}/ 2>/dev/null || true
            echo "Rollback complete. .k8s folder restored to pre-run state."
          fi
          rm -rf "$BACKUP_DIR"
        }
        trap cleanup EXIT

        # Backup current .k8s state
        if [ -d "${manifestsDir}" ]; then
          cp -rf ${manifestsDir}/* "$BACKUP_DIR"/ 2>/dev/null || true
          ROLLBACK_NEEDED=true
        fi

        vals_eval() {
          if command -v vals >/dev/null 2>&1; then
            vals eval -f "$1"
          else
            nix run nixpkgs#vals -- eval -f "$1"
          fi
        }

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

in
{
  inherit
    gmanifests
    vmanifests
    umanifests
    emanifests
    manifests
    ;
}
