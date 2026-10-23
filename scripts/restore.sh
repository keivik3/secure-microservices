#!/bin/sh
# ДЗ 5: восстановление БД из бэкапа.
# Использование: scripts/restore.sh backups/rail_repair_20261114_030000.sql.gz
set -e
cd "$(dirname "$0")/.."

if [ -z "$1" ]; then
    echo "Укажите файл бэкапа:"; ls -1 backups/rail_repair_*.sql.gz
    exit 1
fi

gunzip -c "$1" | docker compose exec -T postgres psql -U app rail_repair
echo "БД восстановлена из $1"
