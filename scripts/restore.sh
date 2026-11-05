#!/bin/sh
# ДЗ 5: восстановление БД из бэкапа.
# Использование: scripts/restore.sh backups/rail_repair_20261114_030000.sql.gz
set -e
cd "$(dirname "$0")/.."

if [ -z "$1" ]; then
    echo "Укажите файл бэкапа. Доступные копии:"
    ls -1 backups/rail_repair_*.sql.gz 2>/dev/null || echo "  (бэкапов нет — сначала запустите scripts/backup.sh)"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "ОШИБКА: файл '$1' не найден. Доступные копии:"
    ls -1 backups/rail_repair_*.sql.gz 2>/dev/null
    exit 1
fi

echo "Восстанавливаю $1 ..."
gunzip -c "$1" | docker compose exec -T postgres psql -U app rail_repair
echo "БД восстановлена из $1"
