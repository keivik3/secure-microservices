#!/bin/sh
# ДЗ 5: резервное копирование БД.
# Дамп пишется в ./backups/ (смонтирован в контейнер postgres как /backups).
# Расписание — cron на хосте, например ежедневно в 03:00:
#   0 3 * * * /path/to/rail-repair-grpc/scripts/backup.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p backups

FILE="backups/rail_repair_$(date +%Y%m%d_%H%M%S).sql.gz"
docker compose exec -T postgres pg_dump -U app rail_repair | gzip > "$FILE"
echo "Бэкап создан: $FILE ($(du -h "$FILE" | cut -f1))"

# Ротация: храним последние 7 копий
ls -t backups/rail_repair_*.sql.gz | tail -n +8 | xargs -r rm
echo "Ротация: оставлены последние 7 копий"
