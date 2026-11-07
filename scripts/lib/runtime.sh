#!/bin/sh
CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
if [ -z "${COMPOSE_PROJECT_NAME:-}" ]; then
    COMPOSE_PROJECT_NAME="$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g; s/^[^a-z0-9]*//')"
    [ -n "$COMPOSE_PROJECT_NAME" ] || COMPOSE_PROJECT_NAME=compose
fi
export COMPOSE_PROJECT_NAME

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

pass() {
    echo "[PASS] $1"
}

case "$CONTAINER_ENGINE" in
    docker|podman) ;;
    *) echo "[FAIL] движок должен быть docker или podman" >&2; exit 2 ;;
esac

command -v "$CONTAINER_ENGINE" >/dev/null 2>&1 || {
    echo "[FAIL] $CONTAINER_ENGINE не установлен или отсутствует в PATH" >&2
    exit 127
}

compose() {
    "$CONTAINER_ENGINE" compose -f "$COMPOSE_FILE" "$@"
}

container() {
    "$CONTAINER_ENGINE" "$@"
}

service_container_id() {
    container ps -aq \
        --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
        --filter "label=com.docker.compose.service=$1" | sed -n '1p'
}

remove_services() {
    for service in "$@"; do
        ids="$(container ps -aq \
            --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
            --filter "label=com.docker.compose.service=$service")"
        [ -z "$ids" ] || container rm -f -v $ids >/dev/null
    done
}

remove_project_volumes() {
    for volume in "$@"; do
        container volume rm -f "${COMPOSE_PROJECT_NAME}_${volume}" >/dev/null 2>&1 || true
    done
}
