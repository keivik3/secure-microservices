#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

GRPCURL_IMAGE="${GRPCURL_IMAGE:-docker.io/fullstorydev/grpcurl:latest}"
ticket_id=""

. scripts/lib/runtime.sh
APP_NETWORK="${APP_NETWORK:-${COMPOSE_PROJECT_NAME}_app-net}"

grpc() {
    container run --rm --network "$APP_NETWORK" "$GRPCURL_IMAGE" \
        -plaintext "$@"
}

cleanup() {
    if [ -n "$ticket_id" ]; then
        grpc -d "{\"id\":$ticket_id}" repair-service:50054 repair.RepairService/DeleteTicket >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

echo "=== 1. gRPC service discovery ==="
services=""
attempt=1
while [ "$attempt" -le 30 ]; do
    services="$(grpc repair-service:50054 list 2>/dev/null || true)"
    if printf '%s\n' "$services" | grep -q '^repair.RepairService$'; then
        break
    fi
    sleep 1
    attempt=$((attempt + 1))
done
printf '%s\n' "$services"
printf '%s\n' "$services" | grep -q '^repair.RepairService$' || fail "RepairService не найден"
pass "RepairService доступен"

echo "=== 2. CreateTicket ==="
stamp="$(date +%Y%m%d_%H%M%S)"
created="$(grpc -d "{\"track_section\":\"DEMO-$stamp\",\"defect_type\":\"RAIL\",\"description\":\"Демонстрация продуктового сценария\",\"priority\":\"CRITICAL\",\"reporter\":\"defense_demo\"}" repair-service:50054 repair.RepairService/CreateTicket)"
printf '%s\n' "$created"
ticket_id="$(printf '%s\n' "$created" | sed -n 's/.*"id": *"\([0-9][0-9]*\)".*/\1/p' | sed -n '1p')"
[ -n "$ticket_id" ] || fail "не удалось получить id заявки"
pass "создана заявка id=$ticket_id"

echo "=== 3. PostgreSQL ==="
db_count="$(compose exec -T postgres psql -U app -d rail_repair -Atqc "SELECT COUNT(*) FROM tickets WHERE id = $ticket_id")"
[ "$db_count" = "1" ] || fail "заявка не найдена в PostgreSQL"
compose exec -T postgres psql -U app -d rail_repair -c \
    "SELECT id, track_section, priority, status FROM tickets WHERE id = $ticket_id;"
pass "INSERT и SELECT в PostgreSQL работают"

echo "=== 4. Пункт 3.2: SQL schema file and applied schema ==="
schema_file="services/repair_service/schema.sql"
[ -f "$schema_file" ] || fail "не найден SQL-файл схемы: $schema_file"
echo "SQL-файл, создающий таблицу и индексы: $schema_file"
sed -n '1,120p' "$schema_file"
column_count="$(compose exec -T postgres psql -U app -d rail_repair -Atqc \
    "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tickets'")"
[ "$column_count" -ge 12 ] || fail "схема из SQL-файла не применена: найдено столбцов $column_count"
compose exec -T postgres psql -U app -d rail_repair -c '\d tickets'
pass "SQL-файл существует, таблица tickets создана, схема применена"

echo "=== 5. Redis cache-aside ==="
compose exec -T redis redis-cli DEL "ticket:$ticket_id" >/dev/null
grpc -d "{\"id\":$ticket_id}" repair-service:50054 repair.RepairService/GetTicket >/dev/null
cached="$(compose exec -T redis redis-cli EXISTS "ticket:$ticket_id")"
[ "$cached" = "1" ] || fail "заявка не попала в Redis"
grpc -d "{\"id\":$ticket_id}" repair-service:50054 repair.RepairService/GetTicket >/dev/null
pass "cache MISS заполняет Redis, повторное чтение берёт данные из кэша"

echo "=== 6. Update and cache invalidation ==="
grpc -d "{\"id\":$ticket_id,\"crew\":\"Демо-бригада\",\"planned_date\":\"2026-11-15\"}" \
    repair-service:50054 repair.RepairService/AssignTicket >/dev/null
cached="$(compose exec -T redis redis-cli EXISTS "ticket:$ticket_id")"
[ "$cached" = "0" ] || fail "кэш не инвалидирован после AssignTicket"
grpc -d "{\"id\":$ticket_id,\"status\":\"IN_PROGRESS\",\"comment\":\"Демонстрация\"}" \
    repair-service:50054 repair.RepairService/UpdateTicketStatus >/dev/null
status="$(compose exec -T postgres psql -U app -d rail_repair -Atqc "SELECT status FROM tickets WHERE id = $ticket_id")"
[ "$status" = "IN_PROGRESS" ] || fail "UPDATE статуса не сохранился"
pass "UPDATE и инвалидация Redis работают"

echo "=== 7. RabbitMQ consumer ==="
event_found=0
attempt=1
while [ "$attempt" -le 5 ]; do
    logs="$(compose logs notification-service 2>&1 || true)"
    if printf '%s\n' "$logs" | grep -q "заявка №$ticket_id"; then
        event_found=1
        break
    fi
    sleep 1
    attempt=$((attempt + 1))
done
[ "$event_found" = "1" ] || fail "notification-service не получил событие"
printf '%s\n' "$logs" | grep "заявка №$ticket_id" | tail -n 4
pass "RabbitMQ доставил событие consumer-сервису"

echo "=== 8. DeleteTicket ==="
grpc -d "{\"id\":$ticket_id}" repair-service:50054 repair.RepairService/DeleteTicket >/dev/null
db_count="$(compose exec -T postgres psql -U app -d rail_repair -Atqc "SELECT COUNT(*) FROM tickets WHERE id = $ticket_id")"
[ "$db_count" = "0" ] || fail "DELETE не удалил заявку из PostgreSQL"
cached="$(compose exec -T redis redis-cli EXISTS "ticket:$ticket_id")"
[ "$cached" = "0" ] || fail "ключ Redis остался после DELETE"
ticket_id=""
pass "DELETE удалил заявку и кэш"

echo
echo "Итог: продуктовый сценарий выполнен успешно"
