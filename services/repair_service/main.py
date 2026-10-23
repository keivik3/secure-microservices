"""Точка входа repair-service: gRPC-сервер на :50054 с TLS/mTLS.

Переменные окружения:
  PORT             — порт (по умолчанию 50054)
  TLS_ENABLED      — 'true'/'false' (по умолчанию 'true')
  TLS_CERT_FILE    — сертификат сервера
  TLS_KEY_FILE     — приватный ключ сервера
  TLS_CA_FILE      — корневой CA (если задан, требуем клиентский сертификат — mTLS)
  GEN_PATH         — путь к сгенерированному pb2-коду (по умолчанию ../../gen)
  POSTGRES_*, REDIS_*, RABBITMQ_* — см. db.py, cache.py, events.py
"""

import logging
import os
import sys
from concurrent import futures

import grpc

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.getenv("GEN_PATH", os.path.join(BASE_DIR, "..", "..", "gen")))

import cache
import db
import events
from handler import RepairService
from proto.repair import repair_pb2_grpc

logging.basicConfig(
    level=logging.INFO,
    format='{"ts": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "msg": "%(message)s"}',
)
logger = logging.getLogger("repair.main")

PORT = int(os.getenv("PORT", "50054"))
TLS_ENABLED = os.getenv("TLS_ENABLED", "true").lower() == "true"
TLS_CERT_FILE = os.getenv("TLS_CERT_FILE", os.path.join(BASE_DIR, "cert", "server-cert.pem"))
TLS_KEY_FILE = os.getenv("TLS_KEY_FILE", os.path.join(BASE_DIR, "cert", "server-key.pem"))
TLS_CA_FILE = os.getenv("TLS_CA_FILE", os.path.join(BASE_DIR, "cert", "ca-cert.pem"))


def make_server_credentials() -> grpc.ServerCredentials:
    """TLS-серверные креды; при наличии CA — взаимная аутентификация (mTLS)."""
    with open(TLS_KEY_FILE, "rb") as f:
        key = f.read()
    with open(TLS_CERT_FILE, "rb") as f:
        cert = f.read()
    root = None
    require_client_auth = False
    if os.path.exists(TLS_CA_FILE):
        with open(TLS_CA_FILE, "rb") as f:
            root = f.read()
        require_client_auth = True  # mTLS: принимаем только своих
    return grpc.ssl_server_credentials(
        [(key, cert)],
        root_certificates=root,
        require_client_auth=require_client_auth,
    )


def serve() -> None:
    logger.info("инициализация PostgreSQL...")
    db.init_db()
    cache.init_cache()
    events.init_events()

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    repair_pb2_grpc.add_RepairServiceServicer_to_server(RepairService(), server)

    if TLS_ENABLED:
        server.add_secure_port(f"[::]:{PORT}", make_server_credentials())
        logger.info("repair-service: gRPC+TLS на :%d", PORT)
    else:
        server.add_insecure_port(f"[::]:{PORT}")
        logger.info("repair-service: gRPC БЕЗ TLS на :%d (режим отладки)", PORT)

    server.start()
    server.wait_for_termination()


if __name__ == "__main__":
    serve()
