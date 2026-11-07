#!/bin/sh
set -eu

if [ "$(id -u)" = "0" ]; then
    mkdir -p "$PGDATA"
    chown -R postgres:postgres "$PGDATA"
    exec gosu postgres /bin/sh /standby-entrypoint.sh "$@"
fi

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Standby: ожидаем PostgreSQL master..."
    until pg_isready -h postgres-ha-master -U replicator -d rail_repair >/dev/null 2>&1; do
        sleep 1
    done

    find "$PGDATA" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    until pg_basebackup \
        -d "host=postgres-ha-master user=replicator application_name=ha_standby" \
        -D "$PGDATA" \
        -Fp -Xs -P -R -S ha_standby
    do
        echo "Standby: повторяем pg_basebackup..."
        sleep 2
    done
    chmod 700 "$PGDATA"
fi

exec docker-entrypoint.sh postgres -c hot_standby=on
