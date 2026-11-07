#!/bin/sh
# ДЗ 5: восстановление БД из бэкапа.
# Использование: scripts/restore.sh backups/rail_repair_20261114_030000.sql.gz
set -eu
cd "$(dirname "$0")/.."

. scripts/lib/runtime.sh
RESTORE_DB="${RESTORE_DB:-rail_repair}"

if [ "$#" -ne 1 ]; then
    echo "Укажите файл бэкапа. Доступные копии:"
    ls -1 backups/rail_repair_*.sql.gz 2>/dev/null || echo "  (бэкапов нет — сначала запустите scripts/backup.sh)"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "ОШИБКА: файл '$1' не найден. Доступные копии:"
    ls -1 backups/rail_repair_*.sql.gz 2>/dev/null
    exit 1
fi

gzip -t "$1"
umask 077
restore_sql="$(mktemp "${TMPDIR:-/tmp}/rail-repair-restore.XXXXXX.sql")"
cleanup() {
    rm -f -- "$restore_sql"
}
trap cleanup EXIT INT TERM

echo "Восстанавливаю $1 ..."
gunzip -c "$1" > "$restore_sql"
compose exec -T postgres psql \
    -X -v ON_ERROR_STOP=1 --single-transaction \
    -U app -d "$RESTORE_DB" < "$restore_sql"
echo "БД $RESTORE_DB восстановлена из $1"
