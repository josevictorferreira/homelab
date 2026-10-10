#!/usr/bin/env bash
# Print both digest levels for a container image tag and (optionally) tell
# you which one an existing pin matches.
#
# The homelab pins digests per app, and the convention is NOT uniform:
# some apps pin the multi-arch index digest, others the linux/amd64 child.
# Always match the app's existing convention when upgrading.
#
# Usage:
#   image-digests.sh registry/repo:tag
#   image-digests.sh registry/repo:tag --check sha256:<existing-pin>
#
# Requires: podman, jq
set -euo pipefail

[[ $# -ge 1 ]] || { grep '^#' "$0" | cut -c3-; exit 1; }
REF=$1; shift || true
CHECK=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) CHECK=${2:?--check needs sha256:...}; shift 2 ;;
    *) { echo "unknown arg: $1" >&2; exit 1; } ;;
  esac
done

JSON=$(podman manifest inspect "$REF") || { echo "error: cannot inspect $REF" >&2; exit 1; }

if ! jq -e '.manifests' >/dev/null 2>&1 <<< "$JSON"; then
  echo "single-arch image (no manifest list) — only one digest exists:"
  echo "  digest: $(podman inspect "$REF" --format '{{json .RepoDigests}}' 2>/dev/null | jq -r '.[0]')" 2>/dev/null || true
  exit 0
fi

AMD64=$(jq -r '.manifests[] | select(.platform.architecture=="amd64" and .platform.os=="linux") | .digest' <<< "$JSON")
ARCHES=$(jq -r '[.manifests[].platform.architecture] | join(",")' <<< "$JSON")

echo "ref:     $REF  (arches: $ARCHES)"
echo "amd64:   sha256-digest of the linux/amd64 child manifest"
echo "$AMD64" | sed 's/^/         /'

if [[ -n "$CHECK" ]]; then
  CLEAN=${CHECK#sha256:}
  if [[ "$AMD64" == *"$CLEAN"* ]]; then
    echo "match:   your pin IS the amd64 child digest"
  else
    echo "match:   your pin is NOT the amd64 child → it is the multi-arch index digest"
  fi
fi
