#!/bin/sh
# Генерация Python-кода из proto-контрактов.
# Зависимости: pip install grpcio-tools
set -e
cd "$(dirname "$0")/.."

python -m grpc_tools.protoc \
  -I. \
  --python_out=./gen \
  --grpc_python_out=./gen \
  proto/auth/auth.proto \
  proto/user/user.proto \
  proto/repair/repair.proto \
  proto/gateway/gateway.proto

echo "OK: сгенерированный код в ./gen"
