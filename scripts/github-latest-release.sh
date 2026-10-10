#!/usr/bin/env bash
# Fetch the latest stable release tag from a GitHub repository.
# Stable = not marked prerelease/draft by GitHub AND tag name has no
# beta/alpha/rc/pre/nightly/dev marker (some repos mislabel prereleases).
#
# Usage:
#   github-latest-release.sh owner/repo            # print latest stable tag
#   github-latest-release.sh owner/repo --list 10  # print 10 newest stable tags
#   github-latest-release.sh owner/repo --match '^v2\.'  # latest stable matching regex
#
# Auth (optional, raises rate limit): export GITHUB_TOKEN=ghp_...
set -euo pipefail

usage() { grep '^#' "$0" | cut -c3-; exit 1; }

[[ $# -ge 1 ]] || usage
REPO=$1; shift || true
LIST=0
MATCH='.*'
while [[ $# -gt 0 ]]; do
  case $1 in
    --list)  LIST=${2:?--list needs N}; shift 2 ;;
    --match) MATCH=${2:?--match needs regex}; shift 2 ;;
    *) usage ;;
  esac
done

AUTH=()
[[ -n "${GITHUB_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")

# Fetch up to 100 newest releases, filter to stable ones matching the pattern.
TAGS=$(
  curl -sf "${AUTH[@]}" "https://api.github.com/repos/${REPO}/releases?per_page=100" \
  | jq -r --arg match "$MATCH" '
      .[]
      | select(.draft == false and .prerelease == false)
      | select(.tag_name | test($match))
      | select(.tag_name | test("beta|alpha|rc[._0-9-v]|pre(view|lease)?[._0-9-v]|nightly|dev[._0-9-v]|canary|snapshot"; "i") | not)
      | .tag_name'
)

if [[ -z "$TAGS" ]]; then
  echo "error: no stable release found for ${REPO} (match: ${MATCH})" >&2
  exit 1
fi

if [[ "$LIST" -gt 0 ]]; then
  head -n "$LIST" <<< "$TAGS"
else
  head -n 1 <<< "$TAGS"
fi
