#!/bin/sh
# ДЗ 4: проверка сегментации сетей.
# Явное разрешение — ping проходит, явный запрет — не проходит.
# Запуск из корня проекта ПОСЛЕ docker compose up.

pass=0; fail=0

check() {  # $1=ожидание(ok/deny) $2=откуда $3=куда $4=пояснение
    if docker exec "$2" sh -c "ping -c1 -W2 $3 >/dev/null 2>&1"; then
        result="OK (доступен)"; actual=ok
    else
        result="ЗАПРЕЩЁН (недоступен)"; actual=deny
    fi
    if [ "$1" = "$actual" ]; then mark="PASS"; pass=$((pass+1)); else mark="FAIL"; fail=$((fail+1)); fi
    echo "[$mark] $2 -> $3 : $result  # $4"
}

echo "=== Явные разрешения (одна сеть) ==="
check ok   repair-service        postgres   "repair-service в data-net, БД доступна"
check ok   repair-service        redis      "repair-service в data-net, кэш доступен"
check ok   repair-service        rabbitmq   "repair-service в data-net, брокер доступен"
check ok   notification-service  rabbitmq   "консьюмер в data-net, брокер доступен"

echo "=== Явные запреты (разные сети) ==="
check deny notification-service  keycloak   "notification-service НЕ в app-net — Keycloak недоступен"
check deny notification-service  prometheus "notification-service НЕ в app-net — метрики недоступны"
check deny postgres              keycloak   "БД НЕ в app-net — Keycloak недоступен"

echo
echo "Итог: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
