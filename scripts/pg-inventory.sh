#!/usr/bin/env bash
# Deterministic inventory of a PostgreSQL instance, for before/after migration diffs.
# Usage: pg-inventory.sh HOST PORT > inventory.txt
# Password: PGPASSWORD env var, or first line of stdin when PGPASSWORD is unset.
# Output lines (sorted within each section):
#   DB <name> <size_bytes>
#   ROLE <name> <super> <login>
#   EXT <db> <name> <version>
#   TABLE <db> <schema.table> <exact_count>
#   SEQ <db> <schema.seq> <last_value>
#   IDX <db> <count>
#   CONSTR <db> <count>
set -euo pipefail

HOST=$1
PORT=$2
if [ -z "${PGPASSWORD:-}" ]; then
  IFS= read -r PGPASSWORD
  export PGPASSWORD
fi

# Roles that the CloudNativePG operator creates on its own; not part of the app data.
CNPG_ROLES="'streaming_replica'"

P() { psql -h "$HOST" -p "$PORT" -U postgres -XAtq -v ON_ERROR_STOP=1 "$@"; }

P -d postgres -c "SELECT 'DB ' || datname || ' ' || pg_database_size(datname)
                  FROM pg_database WHERE NOT datistemplate ORDER BY datname"

P -d postgres -c "SELECT 'ROLE ' || rolname || ' ' || rolsuper || ' ' || rolcanlogin
                  FROM pg_roles WHERE rolname NOT LIKE 'pg\_%' AND rolname NOT IN ($CNPG_ROLES)
                  ORDER BY rolname"

for db in $(P -d postgres -c "SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn ORDER BY datname"); do
  P -d "$db" -c "SELECT 'EXT $db ' || extname || ' ' || extversion FROM pg_extension ORDER BY extname"

  # Generate one exact count(*) per user table and execute the generated statements.
  P -d "$db" -c "SELECT format('SELECT ''TABLE $db %s '' || count(*) FROM %s;',
                        quote_ident(n.nspname) || '.' || quote_ident(c.relname),
                        quote_ident(n.nspname) || '.' || quote_ident(c.relname))
                 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE c.relkind = 'r'
                   AND n.nspname NOT IN ('pg_catalog', 'information_schema')
                   AND n.nspname NOT LIKE 'pg_toast%'
                 ORDER BY 1" | P -d "$db"

  P -d "$db" -c "SELECT 'SEQ $db ' || schemaname || '.' || sequencename || ' ' || coalesce(last_value::text, 'null')
                 FROM pg_sequences ORDER BY schemaname, sequencename"

  P -d "$db" -c "SELECT 'IDX $db ' || count(*) FROM pg_indexes
                 WHERE schemaname NOT IN ('pg_catalog', 'information_schema')"

  P -d "$db" -c "SELECT 'CONSTR $db ' || count(*)
                 FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
                 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')"
done
