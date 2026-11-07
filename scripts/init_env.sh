#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

env_file="${ENV_FILE:-.env}"
[ ! -e "$env_file" ] || exit 0
command -v openssl >/dev/null 2>&1 || {
    echo "[FAIL] openssl не установлен" >&2
    exit 127
}

umask 077
tmp_file="${env_file}.tmp.$$"
cleanup() {
    rm -f -- "$tmp_file"
}
trap cleanup EXIT INT TERM

cat > "$tmp_file" <<EOF
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -hex 24)
POSTGRES_PASSWORD=$(openssl rand -hex 24)
POSTGRES_REPLICATION_PASSWORD=$(openssl rand -hex 24)
RABBITMQ_PASSWORD=$(openssl rand -hex 24)
RABBITMQ_ERLANG_COOKIE=$(openssl rand -hex 32)
EOF
mv -- "$tmp_file" "$env_file"
trap - EXIT INT TERM
echo "Создан локальный $env_file"
