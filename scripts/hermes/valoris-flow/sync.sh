#!/usr/bin/env bash
# Copy the valoris-flow scripts and skills from this repo into the live hermes data dir.
#   sync.sh --check   list drift, exit 1 if any
#   sync.sh --apply   copy sources over targets, archive stale skill copies
# HERMES_DATA defaults to ~/Homelab/hermes (the CephFS dir mounted in the pod as /opt/data).
set -euo pipefail

mode=${1:-}
[[ $mode == --check || $mode == --apply ]] || { echo "usage: $0 --check|--apply" >&2; exit 2; }

src=$(cd "$(dirname "$0")" && pwd)
data=${HERMES_DATA:-$HOME/Homelab/hermes}
profiles=$data/profiles

# skill -> the one profile that runs it
declare -A owner=(
  [valoris-log-triage]=jaheira
  [valoris-pr-test]=jaheira
  [valoris-issue-triage]=irenicus
  [valoris-fix]=valygar
  [valoris-pr-review]=keldorn
)
flow_profiles=(irenicus jaheira valygar keldorn)

drift=0

# Copy in place: live files belong to the pod user and are only group-writable for us, so
# overwrite contents (cp keeps owner and mode). New files get the share's owner/group mapping;
# never chmod (the share refuses it).
put() {
  local from=$1 to=$2
  cmp -s "$from" "$to" 2>/dev/null && return 0
  drift=1
  echo "changed: $to"
  [[ $mode == --apply ]] || return 0
  mkdir -p "$(dirname "$to")"
  cp "$from" "$to"
}

for f in "$src"/scripts/*.py; do
  put "$f" "$profiles/irenicus/scripts/$(basename "$f")"
done

for skill in "${!owner[@]}"; do
  put "$src/skills/$skill/SKILL.md" "$profiles/${owner[$skill]}/skills/$skill/SKILL.md"
  for p in "${flow_profiles[@]}"; do
    [[ $p == "${owner[$skill]}" ]] && continue
    stale=$profiles/$p/skills/$skill
    [[ -d $stale ]] || continue
    drift=1
    echo "stale:   $stale"
    if [[ $mode == --apply ]]; then
      mkdir -p "$profiles/$p/skills/.archive"
      mv "$stale" "$profiles/$p/skills/.archive/$skill-$(date +%Y%m%d%H%M%S)"
    fi
  done
done

if [[ $mode == --check ]]; then
  exit $drift
fi
echo "sync done"
