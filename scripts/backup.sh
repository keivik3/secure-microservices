#!/bin/sh
# ДЗ 5: резервное копирование БД.
# Дамп пишется в ./backups/ (смонтирован в контейнер postgres как /backups).
# Расписание — cron на хосте, например ежедневно в 03:00:
#   0 3 * * * /path/to/rail-repair-grpc/scripts/backup.sh
set -e
cd "$(dirname "$0")/.."

. scripts/lib/runtime.sh

BACKUP_DIR="${BACKUP_DIR:-backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"
case "$BACKUP_RETENTION" in
    ''|*[!0-9]*|0) echo "ОШИБКА: BACKUP_RETENTION должен быть положительным числом" >&2; exit 2 ;;
esac

mkdir -p "$BACKUP_DIR"
umask 077
stamp="$(date +%Y%m%d_%H%M%S)_$$"
FILE="$BACKUP_DIR/rail_repair_${stamp}.sql.gz"
tmp_sql="$BACKUP_DIR/.rail_repair_${stamp}.sql"
tmp_gz="${FILE}.tmp"
cleanup() {
    rm -f -- "$tmp_sql" "$tmp_gz"
}
trap cleanup EXIT INT TERM

compose exec -T postgres pg_dump \
    --clean --if-exists --no-owner --no-privileges \
    -U app rail_repair > "$tmp_sql"
gzip -c "$tmp_sql" > "$tmp_gz"
gzip -t "$tmp_gz"
mv -- "$tmp_gz" "$FILE"
rm -f -- "$tmp_sql"
trap - EXIT INT TERM
echo "Бэкап создан: $FILE ($(du -h "$FILE" | cut -f1))"

# Ротация: храним последние 7 копий
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'rail_repair_*.sql.gz' -print | sort -r | tail -n "+$((BACKUP_RETENTION + 1))" | while IFS= read -r old_backup; do
    [ -z "$old_backup" ] || rm -- "$old_backup"
done
echo "Ротация: оставлены последние $BACKUP_RETENTION копий"
