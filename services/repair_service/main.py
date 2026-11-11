"""Точка входа repair-service: gRPC-сервер на :50054.

Переменные окружения:
  PORT             — порт (по умолчанию 50054)
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
from grpc_reflection.v1alpha import reflection
from handler import RepairService
from proto.repair import repair_pb2, repair_pb2_grpc

logging.basicConfig(
    level=logging.INFO,
    format='{"ts": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "msg": "%(message)s"}',
)
logger = logging.getLogger("repair.main")

PORT = int(os.getenv("PORT", "50054"))
ENABLE_GRPC_REFLECTION = os.getenv("ENABLE_GRPC_REFLECTION", "false").lower() == "true"


def serve() -> None:
    logger.info("инициализация PostgreSQL...")
    db.init_db()
    cache.init_cache()
    events.init_events()

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    repair_pb2_grpc.add_RepairServiceServicer_to_server(RepairService(), server)

    if ENABLE_GRPC_REFLECTION:
        reflection.enable_server_reflection(
            (
                repair_pb2.DESCRIPTOR.services_by_name["RepairService"].full_name,
                reflection.SERVICE_NAME,
            ),
            server,
        )

    server.add_insecure_port(f"[::]:{PORT}")
    logger.info("repair-service: gRPC на :%d", PORT)

    server.start()
    server.wait_for_termination()


if __name__ == "__main__":
    serve()
