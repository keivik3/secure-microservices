#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

. scripts/lib/runtime.sh

probe_postgres() {
    compose exec -T repair-service python -c \
        'import socket; connection = socket.create_connection(("postgres", 5432), 2); connection.close()'
}

needs_restore=0
restore_service() {
    if [ "$needs_restore" = "1" ]; then
        echo "Восстанавливаем штатные сети repair-service..."
        compose up -d --force-recreate repair-service >/dev/null 2>&1 || true
        needs_restore=0
    fi
}
trap restore_service EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

repair_container="$(service_container_id repair-service)"
[ -n "$repair_container" ] || fail "контейнер repair-service не запущен"
data_network="${DATA_NETWORK:-${COMPOSE_PROJECT_NAME}_data-net}"

echo "=== 1. Штатное разрешённое соединение ==="
probe_postgres || fail "repair-service не подключается к PostgreSQL до проверки"
echo "[PASS] repair-service -> PostgreSQL: доступ разрешён"

echo "=== 2. Пункт 4.5: запрет необходимой сетевой связи ==="
echo "Отключаем контейнер $repair_container от сети $data_network"
container network disconnect "$data_network" "$repair_container"
needs_restore=1

echo "=== 3. Ожидаемая ошибка приложения ==="
if error_output="$(probe_postgres 2>&1)"; then
    fail "соединение с PostgreSQL сохранилось после запрета"
fi
printf '%s\n' "$error_output"
echo "[PASS] после запрета необходимой связи получена ожидаемая ошибка доступа"

echo "=== 4. Восстановление штатной конфигурации ==="
compose up -d --force-recreate repair-service >/dev/null
needs_restore=0

restored=0
attempt=1
while [ "$attempt" -le 20 ]; do
    if probe_postgres >/dev/null 2>&1; then
        restored=1
        break
    fi
    sleep 1
    attempt=$((attempt + 1))
done
[ "$restored" = "1" ] || fail "доступ к PostgreSQL не восстановился"
echo "[PASS] штатная сеть и доступ к PostgreSQL восстановлены"

echo
echo "Итог: отказ при запрете легитимной связи продемонстрирован, стенд восстановлен"
