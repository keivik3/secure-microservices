#!/bin/sh
# ДЗ 4: проверка сегментации сетей.
# Явное разрешение — TCP-подключение проходит, явный запрет — не проходит.
# Запуск из корня проекта ПОСЛЕ docker compose up.
#
# ВАЖНО: обращаемся через "docker compose exec" (по имени СЕРВИСА),
# а не "docker exec" (по имени контейнера) — тогда скрипт не зависит
# от названия папки проекта (префикса контейнеров).
#
# Проверка делается тем, что есть в контейнере:
#   python-образы (repair, notification) — TCP-connect через python;
#   alpine-образы (postgres и др.) — ping.

pass=0; fail=0

check() {  # $1=ожидание(ok/deny) $2=откуда(сервис) $3=куда $4=порт $5=пояснение
    if docker compose exec -T "$2" sh -c \
        "python -c \"import socket,sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), 2)\" $3 $4 2>/dev/null || ping -c1 -W2 $3 >/dev/null 2>&1"
    then
        result="OK (доступен)"; actual=ok
    else
        result="ЗАПРЕЩЁН (недоступен)"; actual=deny
    fi
    if [ "$1" = "$actual" ]; then mark="PASS"; pass=$((pass+1)); else mark="FAIL"; fail=$((fail+1)); fi
    echo "[$mark] $2 -> $3:$4 : $result  # $5"
}

echo "=== Явные разрешения (одна сеть) ==="
check ok   repair-service        postgres   5432 "repair-service в data-net, БД доступна"
check ok   repair-service        redis      6379 "repair-service в data-net, кэш доступен"
check ok   repair-service        rabbitmq   5672 "repair-service в data-net, брокер доступен"
check ok   notification-service  rabbitmq   5672 "консьюмер в data-net, брокер доступен"

echo "=== Явные запреты (разные сети) ==="
check deny notification-service  keycloak   8080 "notification-service НЕ в app-net — Keycloak недоступен"
check deny notification-service  prometheus 9090 "notification-service НЕ в app-net — метрики недоступны"
check deny postgres              keycloak   8080 "БД НЕ в app-net — Keycloak недоступен"

echo
echo "Итог: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
