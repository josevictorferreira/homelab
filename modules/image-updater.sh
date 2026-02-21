#!/usr/bin/env bash
#
# Kubenix Image Updater - Scans all kubenix files for container images and checks for updates
#
# Usage: ./kubenix-image-updater [command] [options]
#
# Commands:
#   scan              List all images found in kubenix files
#   check <image>     Check a specific image for updates
#   check-all         Check all images for updates (slow - queries registries)
#   outdated          Show only images with available updates
#
# Options:
#   --json            Output in JSON format
#   --with-digest     Include current image digest when checking
#

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBENIX_DIR="$REPO_ROOT/modules/kubenix"

# Check for required tools
check_dependencies() {
    local missing=()
    
    command -v skopeo >/dev/null 2>&1 || missing+=("skopeo")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v grep >/dev/null 2>&1 || missing+=("grep")
    command -v awk >/dev/null 2>&1 || missing+=("awk")
    command -v find >/dev/null 2>&1 || missing+=("find")
    command -v sed >/dev/null 2>&1 || missing+=("sed")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required tools: ${missing[*]}${NC}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

# Parse an image reference into components
# Returns: registry|repository|tag|digest
parse_image_ref() {
    local ref="$1"
    local registry=""
    local repository=""
    local tag=""
    local digest=""
    
    # Check if it has a digest
    if [[ "$ref" =~ @sha256: ]]; then
        digest="${ref#*@}"
        ref="${ref%%@*}"
    fi
    
    # Extract tag
    if [[ "$ref" =~ : ]]; then
        # Make sure it's not a port number
        if [[ "$ref" =~ ^([^:]+\.[a-zA-Z]+):[0-9]+/ ]]; then
            # Registry with port, keep going
            :
        else
            tag="${ref##*:}"
            ref="${ref%%:*}"
        fi
    fi
    
    # Determine registry and repository
    if [[ "$ref" =~ ^([^/]+\.[^/]+)/(.+)$ ]]; then
        # Has explicit registry (e.g., ghcr.io, gcr.io)
        registry="${BASH_REMATCH[1]}"
        repository="${BASH_REMATCH[2]}"
    elif [[ "$ref" =~ ^([^/]+)/(.+)$ ]]; then
        # org/repo format - default to docker.io
        registry="docker.io"
        repository="$ref"
    else
        # Just a name - library image
        registry="docker.io"
        repository="library/$ref"
    fi
    
    # Default tag
    [ -z "$tag" ] && tag="latest"
    
    echo "$registry|$repository|$tag|$digest"
}

# Build full image reference from components
build_image_ref() {
    local registry="$1"
    local repository="$2"
    local tag="$3"
    local digest="$4"
    
    local ref="$registry/$repository:$tag"
    [ -n "$digest" ] && ref="$ref@$digest"
    
    echo "$ref"
}

# Extract all images from kubenix files
# Outputs JSON array of image objects
extract_images() {
    local output_format="${1:-json}"
    
    find "$KUBENIX_DIR" -name "*.nix" ! -name "_*.nix" ! -name "default.nix" | while read -r file; do
        local rel_file="${file#$REPO_ROOT/}"
        
        # Pattern 1: image = { registry = "..."; repository = "..."; tag = "..."; }
        # Also matches: image.repository = "..."; image.tag = "...";
        grep -n "repository\s*=" "$file" 2>/dev/null | while IFS=: read -r line_num line_content; do
            # Extract repository value
            if [[ "$line_content" =~ repository\s*=\s*\"([^\"]+)\" ]]; then
                local repository="${BASH_REMATCH[1]}"
                
                # Try to find matching tag in nearby lines
                local context_start=$((line_num - 5))
                [ $context_start -lt 1 ] && context_start=1
                local context_end=$((line_num + 5))
                
                local context=$(sed -n "${context_start},${context_end}p" "$file" 2>/dev/null)
                local tag=""
                local registry=""
                
                # Extract tag
                if [[ "$context" =~ tag\s*=\s*\"([^\"]+)\" ]]; then
                    tag="${BASH_REMATCH[1]}"
                fi
                
                # Extract registry if present
                if [[ "$context" =~ registry\s*=\s*\"([^\"]+)\" ]]; then
                    registry="${BASH_REMATCH[1]}"
                fi
                
                # Skip if no tag found
                [ -z "$tag" ] && continue
                
                # Build full image reference
                local image_ref=""
                if [ -n "$registry" ]; then
                    image_ref="$registry/$repository:$tag"
                else
                    # Check if repository already has registry
                    if [[ "$repository" =~ ^[^/]+\.[^/]+/ ]]; then
                        image_ref="$repository:$tag"
                    else
                        image_ref="docker.io/$repository:$tag"
                    fi
                fi
                
                # Output JSON object
                printf '{"file":"%s","line":%d,"image":"%s","repository":"%s","tag":"%s"}\n' \
                    "$rel_file" "$line_num" "$image_ref" "$repository" "$tag"
            fi
        done
        
        # Pattern 2: Simple image strings (e.g., image = "docker.io/library/busybox:1.37";)
        grep -nE 'image\s*=\s*"[^"]+"' "$file" 2>/dev/null | while IFS=: read -r line_num line_content; do
            if [[ "$line_content" =~ image\s*=\s*\"([^\"]+)\" ]]; then
                local image_ref="${BASH_REMATCH[1]}"
                
                # Skip variable references and secrets
                [[ "$image_ref" =~ \$ ]] && continue
                [[ "$image_ref" =~ ^\{ ]] && continue
                [[ "$image_ref" == *"secretsFor"* ]] && continue
                
                # Must have at least one / (namespace/repo or registry/repo)
                [[ ! "$image_ref" =~ / ]] && continue
                
                # Skip if we already captured this via Pattern 1
                # (Pattern 1 outputs first, so we'll dedupe later)
                
                # Parse to get repository and tag
                local parsed=$(parse_image_ref "$image_ref")
                local repository=$(echo "$parsed" | cut -d'|' -f2)
                local tag=$(echo "$parsed" | cut -d'|' -f3)
                
                printf '{"file":"%s","line":%d,"image":"%s","repository":"%s","tag":"%s"}\n' \
                    "$rel_file" "$line_num" "$image_ref" "$repository" "$tag"
            fi
        done
    done | sort -u
}

# Get available tags from registry
get_available_tags() {
    local registry="$1"
    local repository="$2"
    local limit="${3:-20}"
    
    local transport="docker://"
    local full_ref=""
    
    case "$registry" in
        docker.io)
            full_ref="${transport}docker.io/$repository"
            ;;
        ghcr.io)
            full_ref="${transport}ghcr.io/$repository"
            ;;
        gcr.io)
            full_ref="${transport}gcr.io/$repository"
            ;;
        quay.io)
            full_ref="${transport}quay.io/$repository"
            ;;
        registry.k8s.io)
            full_ref="${transport}registry.k8s.io/$repository"
            ;;
        *)
            full_ref="${transport}$registry/$repository"
            ;;
    esac
    
    skopeo list-tags "$full_ref" 2>/dev/null | jq -r '.Tags[]' 2>/dev/null | head -n "$limit" || echo ""
}

# Get digest for a specific tag
get_digest() {
    local registry="$1"
    local repository="$2"
    local tag="$3"
    
    local transport="docker://"
    local full_ref=""
    
    case "$registry" in
        docker.io)
            full_ref="${transport}docker.io/$repository:$tag"
            ;;
        ghcr.io)
            full_ref="${transport}ghcr.io/$repository:$tag"
            ;;
        gcr.io)
            full_ref="${transport}gcr.io/$repository:$tag"
            ;;
        quay.io)
            full_ref="${transport}quay.io/$repository:$tag"
            ;;
        registry.k8s.io)
            full_ref="${transport}registry.k8s.io/$repository:$tag"
            ;;
        *)
            full_ref="${transport}$registry/$repository:$tag"
            ;;
    esac
    
    skopeo inspect "$full_ref" 2>/dev/null | jq -r '.Digest // empty' 2>/dev/null || echo ""
}

# Check if tag A is newer than tag B (semantic versioning)
# Returns: newer, older, unknown
cmp_versions() {
    local tag_a="$1"
    local tag_b="$2"
    
    # Extract version numbers
    local ver_a=$(echo "$tag_a" | sed -E 's/[^0-9.]//g' | head -c 50)
    local ver_b=$(echo "$tag_b" | sed -E 's/[^0-9.]//g' | head -c 50)
    
    [ -z "$ver_a" ] && echo "unknown" && return
    [ -z "$ver_b" ] && echo "unknown" && return
    
    # Compare using sort -V
    local sorted=$(printf '%s\n%s\n' "$ver_a" "$ver_b" | sort -V)
    local first=$(echo "$sorted" | head -1)
    
    if [ "$ver_a" = "$ver_b" ]; then
        echo "equal"
    elif [ "$first" = "$ver_a" ]; then
        echo "newer"
    else
        echo "older"
    fi
}

# Scan and display all images
scan_images() {
    local format="${1:-text}"
    
    echo -e "${BLUE}Scanning kubenix files for container images...${NC}" >&2
    
    local images=$(extract_images "$format")
    local count=$(echo "$images" | wc -l)
    
    echo -e "${GREEN}Found $count unique image references${NC}" >&2
    echo "" >&2
    
    if [ "$format" = "json" ]; then
        # Wrap in array
        echo "$images" | jq -s '.'
    else
        # Format as table
        echo -e "${CYAN}FILE${NC}                                              ${CYAN}IMAGE${NC}"
        echo "--------------------------------------------------------------------------------"
        echo "$images" | while read -r obj; do
            local file=$(echo "$obj" | jq -r '.file')
            local image=$(echo "$obj" | jq -r '.image')
            printf "%-50s %s\n" "$file" "$image"
        done
    fi
}

# Check a specific image for updates
check_single_image() {
    local image_ref="$1"
    local show_digest="${2:-false}"
    
    echo -e "${YELLOW}Checking:${NC} $image_ref" >&2
    
    local parsed=$(parse_image_ref "$image_ref")
    local registry=$(echo "$parsed" | cut -d'|' -f1)
    local repository=$(echo "$parsed" | cut -d'|' -f2)
    local current_tag=$(echo "$parsed" | cut -d'|' -f3)
    local current_digest=$(echo "$parsed" | cut -d'|' -f4)
    
    echo -e "  Registry:   $registry" >&2
    echo -e "  Repository: $repository" >&2
    echo -e "  Current:    ${CYAN}$current_tag${NC}" >&2
    
    if [ "$show_digest" = "true" ]; then
        if [ -z "$current_digest" ]; then
            current_digest=$(get_digest "$registry" "$repository" "$current_tag")
        fi
        if [ -n "$current_digest" ]; then
            echo -e "  Digest:     ${GREEN}$current_digest${NC}" >&2
        fi
    fi
    
    echo "" >&2
    echo -e "${BLUE}Available tags:${NC}" >&2
    
    local tags=$(get_available_tags "$registry" "$repository" 10)
    
    if [ -z "$tags" ]; then
        echo -e "  ${RED}Failed to fetch tags from registry${NC}" >&2
        return 1
    fi
    
    local found_newer=false
    
    while IFS= read -r tag; do
        [ -z "$tag" ] && continue
        
        local marker="  "
        if [ "$tag" = "$current_tag" ]; then
            marker="${GREEN}* ${NC}"
        fi
        
        local cmp=$(cmp_versions "$tag" "$current_tag")
        if [ "$cmp" = "newer" ]; then
            marker="${YELLOW}> ${NC}"
            found_newer=true
        fi
        
        local digest_str=""
        if [ "$show_digest" = "true" ]; then
            local d=$(get_digest "$registry" "$repository" "$tag")
            if [ -n "$d" ]; then
                digest_str=" @ ${d:0:16}..."
            fi
        fi
        
        printf "  %b%s%b%s\n" "$marker" "$tag" "$NC" "$digest_str" >&2
    done <<< "$tags"
    
    echo "" >&2
    
    if [ "$found_newer" = "true" ]; then
        echo -e "${YELLOW}Update available!${NC}" >&2
    else
        echo -e "${GREEN}Up to date${NC}" >&2
    fi
}

# Check all images for updates
check_all_images() {
    local show_digest="${1:-false}"
    
    echo -e "${BLUE}Scanning for images...${NC}" >&2
    local images=$(extract_images "json")
    local count=$(echo "$images" | wc -l)
    
    echo -e "${GREEN}Found $count images to check${NC}" >&2
    echo "" >&2
    
    local idx=0
    echo "$images" | while read -r obj; do
        idx=$((idx + 1))
        local file=$(echo "$obj" | jq -r '.file')
        local image=$(echo "$obj" | jq -r '.image')
        local line=$(echo "$obj" | jq -r '.line')
        
        echo -e "${BLUE}[$idx/$count]${NC} $file:$line" >&2
        check_single_image "$image" "$show_digest"
        echo "" >&2
        echo "================================================================================" >&2
        echo "" >&2
    done
}

# Show outdated images only
show_outdated() {
    echo -e "${BLUE}Checking for outdated images...${NC}" >&2
    local images=$(extract_images "json")
    
    local outdated_count=0
    
    echo "$images" | while read -r obj; do
        local file=$(echo "$obj" | jq -r '.file')
        local image=$(echo "$obj" | jq -r '.image')
        local tag=$(echo "$obj" | jq -r '.tag')
        
        local parsed=$(parse_image_ref "$image")
        local registry=$(echo "$parsed" | cut -d'|' -f1)
        local repository=$(echo "$parsed" | cut -d'|' -f2)
        local current_tag=$(echo "$parsed" | cut -d'|' -f3)
        
        # Quick check - just get latest tags
        local latest_tags=$(get_available_tags "$registry" "$repository" 5)
        
        local found_newer=false
        while IFS= read -r t; do
            [ -z "$t" ] && continue
            local cmp=$(cmp_versions "$t" "$current_tag")
            if [ "$cmp" = "newer" ]; then
                found_newer=true
                break
            fi
        done <<< "$latest_tags"
        
        if [ "$found_newer" = "true" ]; then
            echo "$obj"
        fi
    done | if read -t 0; then
        cat
    else
        echo -e "${GREEN}All images are up to date!${NC}"
    fi
}

# Show help
show_help() {
    cat << EOF
Kubenix Image Updater

Usage: $(basename "$0") [command] [options]

Commands:
  scan                  List all images found in kubenix files
  check <image>         Check a specific image for updates
  check-all             Check all images for updates (slow - queries registries)
  outdated              Show only images with available updates

Options:
  --json                Output in JSON format (for scan command)
  --with-digest         Include image digests when checking (slower)
  --help, -h            Show this help message

Examples:
  # List all images
  $(basename "$0") scan

  # Check a specific image
  $(basename "$0") check ghcr.io/immich-app/immich-server:v2.5.2

  # Check all images (slow, fetches from registries)
  $(basename "$0") check-all

  # Show only outdated images
  $(basename "$0") outdated

EOF
}

# Main
main() {
    check_dependencies
    
    cd "$REPO_ROOT"
    
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        scan)
            local format="text"
            [ "${1:-}" = "--json" ] && format="json"
            scan_images "$format"
            ;;
        check)
            if [ -z "${1:-}" ]; then
                echo -e "${RED}Error: Image reference required${NC}"
                echo "Usage: $(basename "$0") check <image> [--with-digest]"
                exit 1
            fi
            local image="$1"
            shift || true
            local show_digest="false"
            [ "${1:-}" = "--with-digest" ] && show_digest="true"
            check_single_image "$image" "$show_digest"
            ;;
        check-all)
            local show_digest="false"
            [ "${1:-}" = "--with-digest" ] && show_digest="true"
            check_all_images "$show_digest"
            ;;
        outdated)
            show_outdated
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
