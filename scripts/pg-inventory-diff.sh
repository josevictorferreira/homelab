#!/usr/bin/env bash
# Compare two pg-inventory.sh outputs.
# Usage: pg-inventory-diff.sh SOURCE.txt TARGET.txt
# Exit 0 only when DB names, ROLE, TABLE, SEQ, IDX and CONSTR lines are identical.
# EXT versions and DB sizes are reported but never fail the comparison.
set -uo pipefail

SRC=$1
DST=$2

strict() {
  grep -E '^(ROLE|TABLE|SEQ|IDX|CONSTR) ' "$1"
  grep -E '^DB ' "$1" | cut -d' ' -f1,2
}

rc=0
echo "=== STRICT (names, row counts, sequences, index/constraint counts, roles)"
if diff <(strict "$SRC" | sort) <(strict "$DST" | sort); then
  echo "identical"
else
  echo "DIFFERENCES FOUND (< source, > target)"
  rc=1
fi

echo "=== EXT versions (informational; upward changes expected)"
diff <(grep '^EXT ' "$SRC" | sort) <(grep '^EXT ' "$DST" | sort) && echo "identical"

echo "=== DB sizes (informational)"
join <(grep '^DB ' "$SRC" | cut -d' ' -f2,3 | sort) <(grep '^DB ' "$DST" | cut -d' ' -f2,3 | sort) \
  | awk '{ printf "%-40s %14d -> %14d\n", $1, $2, $3 }'

exit $rc
