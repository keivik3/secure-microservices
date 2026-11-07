#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

. scripts/lib/runtime.sh

ha_compose() {
    compose --profile ha-demo "$@"
}

cleanup() {
    echo "Удаляем временный HA-стенд..."
    remove_services \
        ha-client rabbitmq-ha-standby-2 rabbitmq-ha-standby-1 rabbitmq-ha-master \
        postgres-ha-standby postgres-ha-master \
        >/dev/null 2>&1 || true
    remove_project_volumes \
        rabbitmq-ha-master-data rabbitmq-ha-standby-1-data rabbitmq-ha-standby-2-data
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_postgres_value() {
    service="$1"
    sql="$2"
    expected="$3"
    attempt=1
    while [ "$attempt" -le 30 ]; do
        value="$(ha_compose exec -T "$service" psql -U app -d rail_repair -Atqc "$sql" 2>/dev/null || true)"
        if [ "$value" = "$expected" ]; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

wait_rabbit() {
    service="$1"
    attempt=1
    while [ "$attempt" -le 120 ]; do
        if ha_compose exec -T "$service" rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
            return 0
        fi
        rabbit_id="$(service_container_id "$service")"
        if [ -n "$rabbit_id" ] && [ "$(container inspect -f '{{.State.Running}}' "$rabbit_id" 2>/dev/null || true)" = "false" ]; then
            ha_compose logs "$service" >&2 || true
            return 1
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    ha_compose logs "$service" >&2 || true
    return 1
}

wait_rabbit_cluster() {
    attempt=1
    while [ "$attempt" -le 120 ]; do
        status="$(ha_compose exec -T rabbitmq-ha-master rabbitmqctl cluster_status 2>/dev/null || true)"
        if printf '%s\n' "$status" | grep -q 'rabbit@rabbitmq-ha-master' && \
            printf '%s\n' "$status" | grep -q 'rabbit@rabbitmq-ha-standby-1' && \
            printf '%s\n' "$status" | grep -q 'rabbit@rabbitmq-ha-standby-2'; then
            printf '%s\n' "$status"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

echo "=== 5.1. PostgreSQL master -> авария -> standby ==="
cleanup
ha_compose up -d postgres-ha-master postgres-ha-standby
wait_postgres_value postgres-ha-master 'SELECT pg_is_in_recovery()' f || \
    fail "PostgreSQL master не готов"
wait_postgres_value postgres-ha-standby 'SELECT pg_is_in_recovery()' t || \
    fail "PostgreSQL standby не запущен в recovery"
wait_postgres_value postgres-ha-master \
    "SELECT active FROM pg_replication_slots WHERE slot_name = 'ha_standby'" t || \
    fail "слот физической репликации не активен"
ha_compose exec -T postgres-ha-master psql -U app -d rail_repair -v ON_ERROR_STOP=1 -c \
    "ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (ha_standby)'" >/dev/null
ha_compose exec -T postgres-ha-master psql -U app -d rail_repair -v ON_ERROR_STOP=1 -c \
    "SELECT pg_reload_conf()" >/dev/null
wait_postgres_value postgres-ha-master \
    "SELECT sync_state FROM pg_stat_replication WHERE application_name = 'ha_standby'" sync || \
    fail "standby не перешёл в синхронный режим"
echo "[PASS] standby работает в recovery через активный replication slot и синхронную репликацию"

ha_compose exec -T postgres-ha-master psql -U app -d rail_repair -v ON_ERROR_STOP=1 -c \
    "INSERT INTO tickets (track_section, defect_type, description, priority, reporter, created_at, updated_at) VALUES ('HA-PRIMARY', 'RAIL', 'До отказа master', 'HIGH', 'ha_demo', 1, 1);" \
    >/dev/null
wait_postgres_value postgres-ha-standby \
    "SELECT COUNT(*) FROM tickets WHERE track_section = 'HA-PRIMARY'" 1 || \
    fail "запись master не реплицировалась на standby"
echo "[PASS] streaming replication передала запись на standby"

postgres_master_id="$(service_container_id postgres-ha-master)"
[ -n "$postgres_master_id" ] || fail "не найден контейнер PostgreSQL master"
echo "Аварийно завершаем PostgreSQL master: $postgres_master_id"
container kill "$postgres_master_id" >/dev/null
[ -z "$(container ps -q --filter "id=$postgres_master_id")" ] || \
    fail "старый PostgreSQL master не изолирован"

ha_compose exec -T -u postgres postgres-ha-standby \
    pg_ctl -D /var/lib/postgresql/data promote -w >/dev/null
wait_postgres_value postgres-ha-standby 'SELECT pg_is_in_recovery()' f || \
    fail "standby не переключился в режим master"
ha_compose exec -T postgres-ha-standby psql -U app -d rail_repair -v ON_ERROR_STOP=1 -c \
    "INSERT INTO tickets (track_section, defect_type, description, priority, reporter, created_at, updated_at) VALUES ('HA-AFTER-FAILOVER', 'RAIL', 'После переключения', 'CRITICAL', 'ha_demo', 2, 2);" \
    >/dev/null
wait_postgres_value postgres-ha-standby \
    "SELECT COUNT(*) FROM tickets WHERE track_section IN ('HA-PRIMARY', 'HA-AFTER-FAILOVER')" 2 || \
    fail "новый master не сохранил данные после failover"
echo "[PASS] master упал, standby повышен до master и принимает чтение/запись"

remove_services postgres-ha-standby postgres-ha-master >/dev/null 2>&1 || true

echo "=== 5.2. RabbitMQ leader -> авария -> standby ==="
ha_compose up -d rabbitmq-ha-master rabbitmq-ha-standby-1 rabbitmq-ha-standby-2 ha-client
wait_rabbit rabbitmq-ha-master || fail "RabbitMQ master не готов"
wait_rabbit rabbitmq-ha-standby-1 || fail "RabbitMQ standby-1 не готов"
wait_rabbit rabbitmq-ha-standby-2 || fail "RabbitMQ standby-2 не готов"
wait_rabbit_cluster || fail "три узла RabbitMQ не объединились в кластер"
echo "[PASS] три узла RabbitMQ объединены в кластер"

ha_compose exec -T ha-client python -c '
import pika
import os
p = pika.ConnectionParameters("rabbitmq-ha-master", credentials=pika.PlainCredentials(
    os.environ["RABBITMQ_USER"], os.environ["RABBITMQ_PASSWORD"]))
c = pika.BlockingConnection(p); ch = c.channel(); ch.confirm_delivery()
ch.queue_declare(queue="ha.demo", durable=True, arguments={
    "x-queue-type": "quorum",
    "x-quorum-initial-group-size": 3,
    "x-queue-leader-locator": "client-local",
})
ch.basic_publish(exchange="", routing_key="ha.demo", body=b"before-failover", mandatory=True,
                 properties=pika.BasicProperties(delivery_mode=2))
c.close()
' >/dev/null
ha_compose exec -T rabbitmq-ha-master rabbitmqctl list_queues name type durable messages
echo "[PASS] persistent-сообщение записано в quorum queue"

rabbit_master_id="$(service_container_id rabbitmq-ha-master)"
[ -n "$rabbit_master_id" ] || fail "не найден контейнер RabbitMQ master"
echo "Аварийно завершаем RabbitMQ leader: $rabbit_master_id"
container kill "$rabbit_master_id" >/dev/null

rabbit_ok=0
attempt=1
while [ "$attempt" -le 30 ]; do
    if ha_compose exec -T ha-client python -c '
import pika
import os
p = pika.ConnectionParameters("rabbitmq-ha-standby-1", credentials=pika.PlainCredentials(
    os.environ["RABBITMQ_USER"], os.environ["RABBITMQ_PASSWORD"]))
c = pika.BlockingConnection(p); ch = c.channel(); ch.confirm_delivery()
method, props, body = ch.basic_get("ha.demo", auto_ack=False)
assert method is not None and body == b"before-failover"
ch.basic_ack(method.delivery_tag)
ch.basic_publish(exchange="", routing_key="ha.demo", body=b"after-failover", mandatory=True,
                 properties=pika.BasicProperties(delivery_mode=2))
method, props, body = ch.basic_get("ha.demo", auto_ack=True)
assert method is not None and body == b"after-failover"
c.close()
' >/dev/null 2>&1; then
        rabbit_ok=1
        break
    fi
    sleep 1
    attempt=$((attempt + 1))
done
[ "$rabbit_ok" = "1" ] || fail "RabbitMQ standby не принял нагрузку после падения leader"
ha_compose exec -T rabbitmq-ha-standby-1 rabbitmqctl cluster_status
echo "[PASS] leader упал, quorum queue сохранила старое сообщение, standby принимает новые"

cleanup
trap - EXIT INT TERM
echo
echo "Итог: пункты 5.1 и 5.2 продемонстрированы успешно"
