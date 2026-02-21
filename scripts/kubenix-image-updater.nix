{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:

let
  # Required tools
  runtimeDeps = with pkgs; [
    nix
    skopeo
    jq
    curl
    gawk
    gnugrep
    findutils
  ];

  # Helper script to extract images from nix files
  extractImagesScript = pkgs.writeScriptBin "extract-kubenix-images" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    KUBENIX_DIR="modules/kubenix"

    echo '{"images":['
    first=1

    # Find all .nix files except those starting with _ or default.nix
    find "$KUBENIX_DIR" -name "*.nix" ! -name "_*.nix" ! -name "default.nix" | while read -r file; do
      # Extract image patterns from the file
      ${pkgs.gawk}/bin/awk -v file="$file" '
        # Pattern: image = { ... } with registry/repository/tag
        /image\s*=\s*\{/ {
          in_image = 1
          image_data = ""
          brace_count = 1
          next
        }
        
        in_image {
          image_data = image_data $0 "\n"
          
          # Count braces
          for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") brace_count++
            if (c == "}") brace_count--
          }
          
          if (brace_count == 0) {
            # Extract components
            registry = ""
            repository = ""
            tag = ""
            
            # Match registry
            if (match(image_data, /registry\s*=\s*"([^"]+)"/, m)) {
              registry = m[1]
            }
            
            # Match repository  
            if (match(image_data, /repository\s*=\s*"([^"]+)"/, m)) {
              repository = m[1]
            }
            
            # Match tag
            if (match(image_data, /tag\s*=\s*"([^"]+)"/, m)) {
              tag = m[1]
            }
            
            if (repository != "" && tag != "") {
              # Full image reference
              if (registry != "") {
                full_image = registry "/" repository ":" tag
              } else {
                full_image = repository ":" tag
              }
              
              # Clean up the tag (remove sha256 part for comparison)
              clean_tag = tag
              if (match(tag, /^([^@]+)@/, m)) {
                clean_tag = m[1]
              }
              
              gsub(/"/, "\\\"", full_image)
              gsub(/"/, "\\\"", clean_tag)
              gsub(/\\/, "\\\\", full_image)
              
              printf "{\"file\":\"%s\",\"image\":\"%s\",\"tag\":\"%s\"}\n", file, full_image, clean_tag
            }
            
            in_image = 0
          }
        }
        
        # Pattern: image = "docker.io/library/busybox:1.37" (simple string)
        /image\s*=\s*"[^"]+"[^;]*;/ && !in_image {
          if (match($0, /image\s*=\s*"([^"]+)"/, m)) {
            img = m[1]
            # Skip if it looks like a variable reference or secret
            if (img !~ /\$/ && img !~ /\{/ && img ~ /:/) {
              gsub(/"/, "\\\"", img)
              printf "{\"file\":\"%s\",\"image\":\"%s\",\"tag\":\"\"}\n", file, img
            }
          }
        }
        
        # Pattern: image.repository = "..."; image.tag = "...";
        /image\.repository\s*=\s*"[^"]+"/ {
          if (match($0, /repository\s*=\s*"([^"]+)"/, m)) {
            repo[m[1]] = 1
            current_repo = m[1]
          }
        }
        
        /image\.tag\s*=\s*"[^"]+"/ {
          if (match($0, /tag\s*=\s*"([^"]+)"/, m)) {
            tag_val = m[1]
            # Try to find matching repository from previous lines
            # Simplified: just report it and let parent context handle it
          }
        }
      ' "$file" 2>/dev/null || true
    done | while read -r line; do
      if [ "$first" -eq 1 ]; then
        first=0
        echo -n "$line"
      else
        echo -n ",$line"
      fi
    done

    echo ']}'
  '';

  # Script to check registry for available tags and digests
  checkRegistryScript = pkgs.writeScriptBin "check-image-updates" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Parse image reference
    parse_image_ref() {
      local ref="$1"
      local registry=""
      local repository=""
      local tag=""
      local digest=""
      
      # Check if it has a digest
      if [[ "$ref" =~ @sha256: ]]; then
        digest="''${ref#*@}"
        ref="''${ref%%@*}"
      fi
      
      # Extract tag
      if [[ "$ref" =~ : ]]; then
        tag="''${ref##*:}"
        ref="''${ref%%:*}"
      fi
      
      # Determine registry and repository
      if [[ "$ref" =~ ^([^/]+\.[^/]+)/(.+)$ ]]; then
        registry="''${BASH_REMATCH[1]}"
        repository="''${BASH_REMATCH[2]}"
      elif [[ "$ref" =~ ^([^/]+)/(.+)$ ]]; then
        # Could be docker.io or just org/repo
        if [[ "$ref" =~ ^(docker\.io|registry-1\.docker\.io)/ ]]; then
          registry="docker.io"
        else
          registry="docker.io"
        fi
        repository="$ref"
      else
        registry="docker.io"
        repository="library/$ref"
      fi
      
      echo "$registry|$repository|$tag|$digest"
    }

    # Get latest tags from registry
    get_latest_tags() {
      local registry="$1"
      local repository="$2"
      local current_tag="$3"
      
      # Map registry to skopeo format
      local transport="docker://"
      local full_ref=""
      
      case "$registry" in
        docker.io|registry-1.docker.io)
          full_ref="''${transport}docker.io/$repository"
          ;;
        ghcr.io)
          full_ref="''${transport}ghcr.io/$repository"
          ;;
        gcr.io)
          full_ref="''${transport}gcr.io/$repository"
          ;;
        quay.io)
          full_ref="''${transport}quay.io/$repository"
          ;;
        registry.k8s.io)
          full_ref="''${transport}registry.k8s.io/$repository"
          ;;
        *)
          full_ref="''${transport}$registry/$repository"
          ;;
      esac
      
      # List tags
      ${pkgs.skopeo}/bin/skopeo list-tags "$full_ref" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.Tags[]' 2>/dev/null | head -20 || echo ""
    }

    # Get digest for a specific tag
    get_digest() {
      local registry="$1"
      local repository="$2"
      local tag="$3"
      
      local transport="docker://"
      local full_ref=""
      
      case "$registry" in
        docker.io|registry-1.docker.io)
          full_ref="''${transport}docker.io/$repository:$tag"
          ;;
        ghcr.io)
          full_ref="''${transport}ghcr.io/$repository:$tag"
          ;;
        gcr.io)
          full_ref="''${transport}gcr.io/$repository:$tag"
          ;;
        quay.io)
          full_ref="''${transport}quay.io/$repository:$tag"
          ;;
        registry.k8s.io)
          full_ref="''${transport}registry.k8s.io/$repository:$tag"
          ;;
        *)
          full_ref="''${transport}$registry/$repository:$tag"
          ;;
      esac
      
      ${pkgs.skopeo}/bin/skopeo inspect "$full_ref" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.Digest' 2>/dev/null || echo ""
    }

    # Main logic
    if [ $# -lt 1 ]; then
      echo "Usage: check-image-updates <image-ref> [current-tag]"
      exit 1
    fi

    image_ref="$1"
    current_tag="''${2:-}"

    parsed=$(parse_image_ref "$image_ref")
    IFS='|' read -r registry repository tag digest <<< "$parsed"

    # Use provided tag or parsed tag
    [ -n "$current_tag" ] && tag="$current_tag"
    [ -z "$tag" ] && tag="latest"

    echo "{"
    echo "  \"registry\": \"$registry\","
    echo "  \"repository\": \"$repository\","
    echo "  \"current_tag\": \"$tag\","
    echo "  \"current_digest\": \"$digest\","

    # Get current digest if not already have it
    if [ -z "$digest" ] && [ -n "$tag" ]; then
      current_digest=$(get_digest "$registry" "$repository" "$tag")
      echo "  \"resolved_digest\": \"$current_digest\","
    fi

    # Get available tags
    echo "  \"available_tags\": ["
    tags=$(get_latest_tags "$registry" "$repository" "$tag")
    first=1
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      # Get digest for this tag
      d=$(get_digest "$registry" "$repository" "$t" 2>/dev/null || echo "")
      if [ "$first" -eq 1 ]; then
        first=0
        echo -n "    {\"tag\": \"$t\", \"digest\": \"$d\"}"
      else
        echo -n ",
    {\"tag\": \"$t\", \"digest\": \"$d\"}"
      fi
    done <<< "$tags"
    echo ""
    echo "  ]"
    echo "}"
  '';

  # Main script that combines everything
  imageUpdaterScript = pkgs.writeScriptBin "kubenix-image-updater" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR"

    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color

    show_help() {
      echo "Kubenix Image Updater"
      echo ""
      echo "Usage: kubenix-image-updater [command] [options]"
      echo ""
      echo "Commands:"
      echo "  scan              Scan all kubenix files and list images"
      echo "  check <image>     Check a specific image for updates"
      echo "  update            Scan and check all images for updates (slow)"
      echo "  outdated          Show only images with available updates"
      echo ""
      echo "Options:"
      echo "  --json            Output in JSON format"
      echo "  --with-hash       Include image hashes (slower)"
      echo "  --help            Show this help message"
      echo ""
    }

    scan_images() {
      local format="''${1:-text}"
      local with_hash="''${2:-false}"
      
      echo "Scanning modules/kubenix for container images..." >&2
      
      # Use grep and sed to extract image references
      results=$(find modules/kubenix -name "*.nix" ! -name "_*.nix" ! -name "default.nix" -exec grep -H "image" {} \; | \
        ${pkgs.gawk}/bin/awk -f ${./extract-images.awk} 2>/dev/null || echo "[]")
      
      if [ "$format" = "json" ]; then
        echo "$results"
      else
        # Format as table
        echo "$results" | ${pkgs.jq}/bin/jq -r '.[] | "\(.file): \(.image)"' 2>/dev/null | \
        while IFS=: read -r file image; do
          printf "''${BLUE}%-50s''${NC} %s\n" "$file" "$image"
        done
      fi
    }

    check_image() {
      local image_ref="$1"
      local with_hash="''${2:-false}"
      
      echo "Checking: $image_ref" >&2
      ${checkRegistryScript}/bin/check-image-updates "$image_ref"
    }

    check_all_updates() {
      local with_hash="''${1:-false}"
      
      echo "Scanning for images..." >&2
      images=$(scan_images json)
      
      echo "Found $(echo "$images" | ${pkgs.jq}/bin/jq 'length') images" >&2
      echo "" >&2
      
      # Process each image
      echo "$images" | ${pkgs.jq}/bin/jq -c '.[]' | while read -r img_data; do
        file=$(echo "$img_data" | ${pkgs.jq}/bin/jq -r '.file')
        image=$(echo "$img_data" | ${pkgs.jq}/bin/jq -r '.image')
        
        printf "''${YELLOW}Checking''${NC} %s\n" "$image"
        
        # Get update info
        update_info=$(${checkRegistryScript}/bin/check-image-updates "$image" 2>/dev/null)
        
        if [ -n "$update_info" ]; then
          current_tag=$(echo "$update_info" | ${pkgs.jq}/bin/jq -r '.current_tag')
          current_digest=$(echo "$update_info" | ${pkgs.jq}/bin/jq -r '.current_digest // .resolved_digest')
          
          # Show latest 5 tags that might be newer
          echo "$update_info" | ${pkgs.jq}/bin/jq -r --arg current "$current_tag" '
            .available_tags | map(select(.tag != $current)) | .[0:5] | 
            .[] | "  → \(.tag)\(.digest | if . then \"@\" + .[0:19] + \"...\" else \"\" end)"
          '
        fi
        
        echo ""
      done
    }

    # Main command dispatch
    case "''${1:-help}" in
      scan)
        format="text"
        with_hash=false
        [ "''${2:-}" = "--json" ] && format="json"
        [ "''${2:-}" = "--with-hash" ] && with_hash=true
        scan_images "$format" "$with_hash"
        ;;
      check)
        if [ -z "''${2:-}" ]; then
          echo "Error: Image reference required"
          exit 1
        fi
        with_hash=false
        [ "''${3:-}" = "--with-hash" ] && with_hash=true
        check_image "$2" "$with_hash"
        ;;
      update)
        with_hash=false
        [ "''${2:-}" = "--with-hash" ] && with_hash=true
        check_all_updates "$with_hash"
        ;;
      outdated)
        echo "Showing outdated images..."
        check_all_updates | grep -A5 "Checking"
        ;;
      help|--help|-h)
        show_help
        ;;
      *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
    esac
  '';

in
pkgs.symlinkJoin {
  name = "kubenix-image-updater";
  paths = [
    imageUpdaterScript
    extractImagesScript
    checkRegistryScript
  ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/kubenix-image-updater \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';
}
