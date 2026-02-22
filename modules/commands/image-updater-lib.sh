#!/usr/bin/env bash
# Shared library for image-updater commands

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect REPO_ROOT - look for modules/kubenix relative to CWD
_find_repo_root() {
  if [[ -d "$PWD/modules/kubenix" ]]; then
    echo "$PWD"
    return 0
  fi
  if [[ -d "$PWD/../modules/kubenix" ]]; then
    (cd "$PWD/.." && pwd)
    return 0
  fi
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/modules/kubenix" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "Error: Cannot find homelab repo root (looked for modules/kubenix from $PWD)" >&2
  return 1
}

# Initialize paths (call from main function)
_init_paths() {
  REPO_ROOT=$(_find_repo_root) || return 1
  KUBENIX_DIR="$REPO_ROOT/modules/kubenix"
  export REPO_ROOT KUBENIX_DIR
}

# Parse an image reference into components: registry|repository|tag|digest
parse_image_ref() {
  local ref="$1"
  local registry="" repository="" tag="" digest=""
  
  [[ "$ref" =~ @sha256: ]] && { digest="${ref#*@}"; ref="${ref%%@*}"; }
  
  if [[ "$ref" =~ : ]]; then
    if ! [[ "$ref" =~ ^([^:]+\.[a-zA-Z]+):[0-9]+/ ]]; then
      tag="${ref##*:}"
      ref="${ref%%:*}"
    fi
  fi
  
  if [[ "$ref" =~ ^([^/]+\.[^/]+)/(.+)$ ]]; then
    registry="${BASH_REMATCH[1]}"
    repository="${BASH_REMATCH[2]}"
  elif [[ "$ref" =~ ^([^/]+)/(.+)$ ]]; then
    registry="docker.io"
    repository="$ref"
  else
    registry="docker.io"
    repository="library/$ref"
  fi
  
  [ -z "$tag" ] && tag="latest"
  echo "$registry|$repository|$tag|$digest"
}

# Extract all images from kubenix files
extract_images() {
  find "$KUBENIX_DIR" -name "*.nix" ! -name "_*.nix" ! -name "default.nix" 2>/dev/null | while read -r file; do
    [ -z "$file" ] && continue
    local rel_file="${file#$REPO_ROOT/}"
    
    # Pattern 1: image = { registry = "..."; repository = "..."; tag = "..."; }
    grep -n "repository[[:space:]]*=" "$file" 2>/dev/null | while IFS=: read -r line_num line_content; do
      if [[ "$line_content" =~ repository[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        local repository="${BASH_REMATCH[1]}"
        local context
        context=$(sed -n "$((line_num-5)),$((line_num+5))p" "$file" 2>/dev/null)
        local tag="" registry=""
        
        [[ "$context" =~ tag[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]] && tag="${BASH_REMATCH[1]}"
        [[ "$context" =~ registry[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]] && registry="${BASH_REMATCH[1]}"
        [ -z "$tag" ] && continue
        
        local image_ref="${registry:+$registry/}$repository:$tag"
        [ -z "$registry" ] && [[ ! "$repository" =~ ^[^/]+\.[^/]+/ ]] && image_ref="docker.io/$repository:$tag"
        
        printf '{"file":"%s","line":%d,"image":"%s","repository":"%s","tag":"%s"}\n' "$rel_file" "$line_num" "$image_ref" "$repository" "$tag"
      fi
    done
    
    # Pattern 2: Simple image strings
    grep -nE 'image[[:space:]]*=[[:space:]]*"[^"]+"' "$file" 2>/dev/null | while IFS=: read -r line_num line_content; do
      if [[ "$line_content" =~ image[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        local image_ref="${BASH_REMATCH[1]}"
        [[ "$image_ref" =~ \$ ]] && continue
        [[ "$image_ref" =~ ^\{ ]] && continue
        [[ "$image_ref" == *"secretsFor"* ]] && continue
        [[ ! "$image_ref" =~ / ]] && continue
        
        local parsed
        parsed=$(parse_image_ref "$image_ref")
        printf '{"file":"%s","line":%d,"image":"%s","repository":"%s","tag":"%s"}\n' \
          "$rel_file" "$line_num" "$image_ref" "$(echo "$parsed" | cut -d'|' -f2)" "$(echo "$parsed" | cut -d'|' -f3)"
      fi
    done
  done | sort -u
}

# Version comparison: returns newer, older, equal, unknown
cmp_versions() {
  local ver_a ver_b
  ver_a=$(echo "$1" | sed -E 's/[^0-9.]//g' | head -c 50)
  ver_b=$(echo "$2" | sed -E 's/[^0-9.]//g' | head -c 50)
  [ -z "$ver_a" ] || [ -z "$ver_b" ] && { echo "unknown"; return; }
  
  if [ "$ver_a" = "$ver_b" ]; then echo "equal"
  elif [ "$(printf '%s\n%s\n' "$ver_a" "$ver_b" | sort -V | head -1)" = "$ver_a" ]; then echo "older"
  else echo "newer"
  fi
}

# Filter to semantic versions only (vN.N.N or N.N.N)
filter_semver_tags() {
  echo "$1" | while IFS= read -r tag; do
    [ -n "$tag" ] && echo "$tag" | grep -qE '^(v?[0-9]+\.[0-9]+(\.[0-9]+)?)$' && echo "$tag"
  done
}

# Find latest semantic version
find_latest_semver() {
  local semver_tags
  semver_tags=$(filter_semver_tags "$1")
  [ -n "$semver_tags" ] && echo "$semver_tags" | sort -V | tail -1
}

# Get available tags from registry
get_available_tags() {
  skopeo list-tags "docker://$1/$2" 2>/dev/null | jq -r '.Tags[]' 2>/dev/null | head -n "${3:-20}" || echo ""
}

# Get digest for a specific tag
get_digest() {
  skopeo inspect "docker://$1/$2:$3" 2>/dev/null | jq -r '.Digest // empty' 2>/dev/null || echo ""
}
