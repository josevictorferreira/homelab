{ pkgs, lib, ... }:

let
  # Shared bash library for image scanning
  imageUpdaterLib = builtins.readFile ./image-updater-lib.sh;

  # Base dependencies for all commands
  baseDeps = with pkgs; [ jq gnugrep gawk findutils gnused ];

  # Additional deps for registry queries
  registryDeps = [ pkgs.skopeo ];

in
{
  # image-scan: List all images from kubenix files
  image-scan = pkgs.writeShellApplication {
    name = "image-scan";
    runtimeInputs = baseDeps;
    excludeShellChecks = [ "SC2034" "SC2155" "SC2295" ];
    text = ''
      ${imageUpdaterLib}
      
      main() {
        _init_paths || exit 1
        echo -e "''${BLUE}Scanning kubenix files for container images...''${NC}" >&2
        local images
        images=$(extract_images)
        local count
        count=$(echo "$images" | wc -l)
        echo -e "''${GREEN}Found $count unique image references''${NC}" >&2
        echo "" >&2
        
        if [ "''${1:-}" = "--json" ]; then
          echo "$images" | jq -s '.'
        else
          echo -e "''${CYAN}FILE''${NC}                                              ''${CYAN}IMAGE''${NC}"
          echo "--------------------------------------------------------------------------------"
          echo "$images" | while read -r obj; do
            printf "%-50s %s\n" "$(echo "$obj" | jq -r '.file')" "$(echo "$obj" | jq -r '.image')"
          done
        fi
      }
      main "$@"
    '';
  };

  # image-outdated: Show images with available updates
  image-outdated = pkgs.writeShellApplication {
    name = "image-outdated";
    runtimeInputs = baseDeps ++ registryDeps;
    excludeShellChecks = [ "SC2034" "SC2155" "SC2295" ];
    text = ''
      ${imageUpdaterLib}
      
      main() {
        _init_paths || exit 1
        echo -e "''${BLUE}Checking for outdated images...''${NC}" >&2
        local images
        images=$(extract_images)
        local total
        total=$(echo "$images" | wc -l)
        echo -e "Checking ''${total} images..." >&2
        
        local outdated_count=0
        local idx=0
        echo "================================================================================"
        echo -e "''${CYAN}FILE                                              CURRENT → LATEST @ DIGEST''${NC}"
        echo "--------------------------------------------------------------------------------"
        
        while IFS= read -r obj; do
          idx=$((idx + 1))
          [ -z "$obj" ] && continue
          
          local file
          file=$(echo "$obj" | jq -r '.file')
          local image
          image=$(echo "$obj" | jq -r '.image')
          echo -e "  [''${idx}/''${total}] Checking ''${YELLOW}''${image}''${NC}" >&2
          
          local parsed
          parsed=$(parse_image_ref "$image")
          local registry
          registry=$(echo "$parsed" | cut -d'|' -f1)
          local repository
          repository=$(echo "$parsed" | cut -d'|' -f2)
          local current_tag
          current_tag=$(echo "$parsed" | cut -d'|' -f3)
          
          local all_tags
          all_tags=$(get_available_tags "$registry" "$repository" 50)
          [ -z "$all_tags" ] && { echo -e "    ''${RED}Failed to fetch tags from ''${registry}''${NC}" >&2; continue; }
          
          local latest_tag
          latest_tag=$(find_latest_semver "$all_tags")
          [ -z "$latest_tag" ] && { echo -e "    ''${CYAN}No semantic version tags found''${NC}" >&2; continue; }
          
          if [ "$(cmp_versions "$latest_tag" "$current_tag")" = "newer" ]; then
            local latest_digest
            latest_digest=$(get_digest "$registry" "$repository" "$latest_tag")
            local digest_str="''${latest_digest:+@$latest_digest}"
            printf "%-50s %s → %s%s\n" "$file" "$current_tag" "$latest_tag" "$digest_str"
            outdated_count=$((outdated_count + 1))
          fi
        done <<< "$images"
        
        echo "================================================================================"
        echo "" >&2
        
        if [ $outdated_count -eq 0 ]; then
          echo -e "''${GREEN}All images are up to date!''${NC}"
        else
          echo -e "''${YELLOW}Found $outdated_count outdated image(s)''${NC}" >&2
        fi
      }
      main
    '';
  };

  # image-updater: Check specific images
  image-updater = pkgs.writeShellApplication {
    name = "image-updater";
    runtimeInputs = baseDeps ++ registryDeps;
    excludeShellChecks = [ "SC2034" "SC2155" "SC2295" ];
    text = ''
            ${imageUpdaterLib}
      
            show_help() {
              cat << EOF
      Usage: image-updater <command> [options]

      Commands:
        check <image>     Check a specific image for updates
        check-all         Check all images for updates (slow)
        help              Show this help

      Options:
        --with-digest     Include image digests when checking
      EOF
            }

            check_single_image() {
              local image_ref="$1"
              local show_digest="''${2:-false}"
              echo -e "''${YELLOW}Checking:''${NC} $image_ref" >&2
        
              local parsed
              parsed=$(parse_image_ref "$image_ref")
              local registry
              registry=$(echo "$parsed" | cut -d'|' -f1)
              local repository
              repository=$(echo "$parsed" | cut -d'|' -f2)
              local current_tag
              current_tag=$(echo "$parsed" | cut -d'|' -f3)
        
              echo -e "  Registry:   $registry" >&2
              echo -e "  Repository: $repository" >&2
              echo -e "  Current:    ''${CYAN}$current_tag''${NC}" >&2
        
              if [ "$show_digest" = "true" ]; then
                local d
                d=$(get_digest "$registry" "$repository" "$current_tag")
                [ -n "$d" ] && echo -e "  Digest:     ''${GREEN}$d''${NC}" >&2
              fi
        
              echo "" >&2
              echo -e "''${BLUE}Available tags:''${NC}" >&2
        
              local tags
              tags=$(get_available_tags "$registry" "$repository" 10)
              [ -z "$tags" ] && { echo -e "  ''${RED}Failed to fetch tags''${NC}" >&2; return 1; }
        
              local found_newer=false
              while IFS= read -r tag; do
                [ -z "$tag" ] && continue
                local marker="  "
                [ "$tag" = "$current_tag" ] && marker="''${GREEN}* ''${NC}"
                if [ "$(cmp_versions "$tag" "$current_tag")" = "newer" ]; then
                  marker="''${YELLOW}> ''${NC}"
                  found_newer=true
                fi
          
                local digest_str=""
                if [ "$show_digest" = "true" ]; then
                  local d
                  d=$(get_digest "$registry" "$repository" "$tag")
                  [ -n "$d" ] && digest_str=" @$d"
                fi
                printf "  %b%s%b%s\n" "$marker" "$tag" "$NC" "$digest_str" >&2
              done <<< "$tags"
        
              echo "" >&2
              if [ "$found_newer" = "true" ]; then
                echo -e "''${YELLOW}Update available!''${NC}" >&2
              else
                echo -e "''${GREEN}Up to date''${NC}" >&2
              fi
            }

            main() {
              _init_paths || exit 1
              case "''${1:-help}" in
                check)
                  [ -z "''${2:-}" ] && { echo "Error: Image reference required" >&2; exit 1; }
                  check_single_image "$2" "''${3:-}"
                  ;;
                check-all)
                  local images
                  images=$(extract_images)
                  local count
                  count=$(echo "$images" | wc -l)
                  local idx=0
                  echo "$images" | while read -r obj; do
                    idx=$((idx + 1))
                    echo -e "''${BLUE}[$idx/$count]''${NC} $(echo "$obj" | jq -r '.file')" >&2
                    check_single_image "$(echo "$obj" | jq -r '.image')" "''${2:-}"
                    echo "" >&2
                  done
                  ;;
                help|--help|-h) show_help ;;
                *) echo "Unknown command: $1" >&2; show_help; exit 1 ;;
              esac
            }
            main "$@"
    '';
  };
}
