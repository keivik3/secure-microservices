#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

DEMO_DB="rail_repair_restore_demo"
demo_backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/rail-repair-backup.XXXXXX")"

. scripts/lib/runtime.sh

cleanup() {
    compose exec -T postgres dropdb -U app --if-exists "$DEMO_DB" >/dev/null 2>&1 || true
    rm -rf -- "$demo_backup_dir"
}
trap cleanup EXIT INT TERM

echo "=== 1. Создание бэкапа ==="
BACKUP_DIR="$demo_backup_dir" BACKUP_RETENTION=1 sh scripts/backup.sh
backup_file="$(find "$demo_backup_dir" -maxdepth 1 -type f -name 'rail_repair_*.sql.gz' -print | sed -n '1p')"
[ -n "$backup_file" ]
gzip -t "$backup_file"
echo "[PASS] gzip-архив цел: $backup_file"

source_count="$(compose exec -T postgres psql -U app -d rail_repair -Atqc 'SELECT COUNT(*) FROM tickets')"
echo "Записей в рабочей БД: $source_count"

echo "=== 2. Восстановление во временную БД ==="
compose exec -T postgres dropdb -U app --if-exists "$DEMO_DB"
compose exec -T postgres createdb -U app "$DEMO_DB"
RESTORE_DB="$DEMO_DB" sh scripts/restore.sh "$backup_file" >/dev/null

restored_count="$(compose exec -T postgres psql -U app -d "$DEMO_DB" -Atqc 'SELECT COUNT(*) FROM tickets')"
echo "Записей в восстановленной БД: $restored_count"
[ "$source_count" = "$restored_count" ] || {
    echo "[FAIL] количество записей не совпало" >&2
    exit 1
}

compose exec -T postgres psql -U app -d "$DEMO_DB" -c \
    'SELECT id, track_section, priority, status FROM tickets ORDER BY id LIMIT 5;'
echo "[PASS] бэкап успешно восстановлен и проверен"

cleanup
trap - EXIT INT TERM
echo "[PASS] временная БД удалена, рабочая БД не изменялась"
