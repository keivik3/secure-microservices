#!/bin/sh
set -eu
: "${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 \
    --set=replication_password="$POSTGRES_REPLICATION_PASSWORD" \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD :'replication_password';
SELECT pg_create_physical_replication_slot('ha_standby');
SQL

printf '%s\n' \
    'host replication replicator 0.0.0.0/0 scram-sha-256' \
    'host replication replicator ::/0 scram-sha-256' \
    >> "$PGDATA/pg_hba.conf"
