#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
CONTAINER_ENGINE="${1:-${CONTAINER_ENGINE:-docker}}"
export CONTAINER_ENGINE
sh scripts/init_env.sh
. scripts/lib/runtime.sh
set -a
. ./.env
set +a

sync_existing_postgres_password() {
    postgres_id="$(service_container_id postgres)"
    [ -n "$postgres_id" ] || return 0
    container start "$postgres_id" >/dev/null
    attempt=1
    while [ "$attempt" -le 30 ]; do
        if printf '%s\n' "ALTER ROLE app WITH PASSWORD :'db_password';" | \
            compose exec -T postgres psql -v ON_ERROR_STOP=1 -U app -d rail_repair \
                --set=db_password="$POSTGRES_PASSWORD" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    echo "[FAIL] не удалось обновить локальный пароль PostgreSQL" >&2
    return 1
}

wait_repair_service() {
    attempt=1
    while [ "$attempt" -le 60 ]; do
        if compose exec -T repair-service python -c \
            'import socket; s = socket.create_connection(("127.0.0.1", 50054), 2); s.close()' \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    compose logs repair-service >&2 || true
    echo "[FAIL] repair-service не готов принимать gRPC-запросы" >&2
    return 1
}

wait_api_gateway() {
    attempt=1
    while [ "$attempt" -le 60 ]; do
        if compose exec -T api-gateway python -c \
            'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8000/api/health", timeout=2)' \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    compose logs api-gateway >&2 || true
    echo "[FAIL] API Gateway не готов" >&2
    return 1
}

wait_frontend() {
    attempt=1
    while [ "$attempt" -le 60 ]; do
        if compose exec -T frontend wget -q --spider http://127.0.0.1:8080/; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    compose logs frontend >&2 || true
    echo "[FAIL] frontend не готов" >&2
    return 1
}

echo "=== 1/7. Сборка и запуск ==="
sync_existing_postgres_password
if [ "${SKIP_BUILD:-0}" = "1" ]; then
    compose up -d
else
    compose up --build -d
fi
wait_repair_service
wait_api_gateway
wait_frontend
compose ps

echo "=== 2/7. Продуктовый сценарий и SQL-схема ==="
sh scripts/demo_product.sh

echo "=== 3/7. Сетевая сегментация ==="
sh scripts/check_network.sh

echo "=== 4/7. Ошибка при запрете необходимой связи ==="
sh scripts/demo_network_failure.sh

echo "=== 5/7. Бэкап и восстановление ==="
sh scripts/demo_backup_restore.sh

echo "=== 6/7. Failover PostgreSQL и RabbitMQ ==="
sh scripts/demo_ha.sh

echo "=== 7/7. Итог ==="
echo "[PASS] отдельный frontend доступен на http://127.0.0.1:8000/"
echo "[PASS] REST API Gateway, gRPC и продуктовый CRUD"
echo "[PASS] SQL-файл и применённая схема PostgreSQL"
echo "[PASS] PostgreSQL, Redis и RabbitMQ"
echo "[PASS] разрешённые, запрещённые связи и контролируемый сетевой отказ"
echo "[PASS] backup/restore во временную БД"
echo "[PASS] PostgreSQL master -> standby и RabbitMQ leader -> standby"
echo "ИТОГ: полная демонстрация прошла успешно"
