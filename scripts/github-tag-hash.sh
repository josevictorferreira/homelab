#!/usr/bin/env bash
# Fetch the commit SHA that GitHub displays on a repo's release/tag page.
# Handles both lightweight tags (ref IS the commit) and annotated tags
# (ref is a tag object; its .object.sha is the commit shown on the page).
#
# Usage: github-tag-hash.sh owner/repo TAG
# Auth (optional, raises rate limit): export GITHUB_TOKEN=ghp_...
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 owner/repo TAG" >&2; exit 1; }
REPO=$1
TAG=$2

AUTH=()
[[ -n "${GITHUB_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")

REF=$(curl -sf "${AUTH[@]}" "https://api.github.com/repos/${REPO}/git/ref/tags/${TAG}") \
  || { echo "error: tag ${TAG} not found in ${REPO}" >&2; exit 1; }

SHA=$(jq -r '.object.sha' <<< "$REF")
TYPE=$(jq -r '.object.type' <<< "$REF")

# Annotated tag: dereference the tag object to the commit.
if [[ "$TYPE" == "tag" ]]; then
  SHA=$(curl -sf "${AUTH[@]}" "https://api.github.com/repos/${REPO}/git/tags/${SHA}" | jq -r '.object.sha')
fi

echo "$SHA"
