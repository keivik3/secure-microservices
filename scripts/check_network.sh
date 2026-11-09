#!/bin/sh
# ДЗ 4: проверка сегментации сетей.
# Явное разрешение — TCP-подключение проходит, явный запрет — не проходит.
# Запуск из корня проекта после `sh scripts/demo.sh docker` или `sh scripts/demo.sh podman`.
#
# ВАЖНО: обращаемся через "compose exec" (по имени СЕРВИСА),
# а не через имя контейнера — тогда скрипт не зависит
# от названия папки проекта (префикса контейнеров).
#
# Проверка использует утилиты, уже имеющиеся в контейнерах:
#   python в сервисах приложения, nc во frontend, ping в Alpine-образах.

set -e
cd "$(dirname "$0")/.."

. scripts/lib/runtime.sh

pass=0; fail=0

check() {  # $1=ожидание(ok/deny) $2=откуда(сервис) $3=куда $4=порт $5=пояснение
    if compose exec -T "$2" sh -c \
        "python -c \"import socket,sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), 2)\" $3 $4 2>/dev/null || nc -z -w2 $3 $4 >/dev/null 2>&1 || ping -c1 -W2 $3 >/dev/null 2>&1" \
        2>/dev/null
    then
        result="OK (доступен)"; actual=ok
    else
        result="ЗАПРЕЩЁН (недоступен)"; actual=deny
    fi
    if [ "$1" = "$actual" ]; then mark="PASS"; pass=$((pass+1)); else mark="FAIL"; fail=$((fail+1)); fi
    echo "[$mark] $2 -> $3:$4 : $result  # $5"
}

echo "=== Явные разрешения (одна сеть) ==="
check ok   frontend              api-gateway 8000  "frontend в frontend-net, gateway доступен"
check ok   api-gateway           repair-service 50054 "gateway в app-net, repair-service доступен"
check ok   repair-service        postgres   5432 "repair-service в data-net, БД доступна"
check ok   repair-service        redis      6379 "repair-service в data-net, кэш доступен"
check ok   repair-service        rabbitmq   5672 "repair-service в data-net, брокер доступен"
check ok   notification-service  rabbitmq   5672 "консьюмер в data-net, брокер доступен"

echo "=== Явные запреты (разные сети) ==="
check deny frontend              postgres   5432 "frontend НЕ в data-net — БД недоступна"
check deny api-gateway           postgres   5432 "gateway НЕ в data-net — БД недоступна"
check deny api-gateway           rabbitmq   5672 "gateway НЕ в data-net — брокер недоступен"
check deny notification-service  keycloak   8080 "notification-service НЕ в app-net — Keycloak недоступен"
check deny notification-service  prometheus 9090 "notification-service НЕ в app-net — метрики недоступны"
check deny postgres              keycloak   8080 "БД НЕ в app-net — Keycloak недоступен"

echo
echo "Итог: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
