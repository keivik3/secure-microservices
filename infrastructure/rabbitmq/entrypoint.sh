#!/bin/sh
set -eu
mkdir -p "$HOME"
chown rabbitmq:rabbitmq "$HOME"
chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
exec docker-entrypoint.sh rabbitmq-server
