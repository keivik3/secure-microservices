"""Redis-кэш для заявок.

Стратегия cache-aside (ленивое наполнение):
  - GetTicket: сначала смотрим в кэш, при промахе — в БД и кладём в кэш.
  - При любом изменении/удалении заявки — инвалидируем ключ ticket:{id}.
TTL 300 секунд: даже при потере инвалидации данные устареют максимум на 5 минут.

Кэш — не критичный компонент: если Redis недоступен, сервис продолжает
работать напрямую через БД (graceful degradation).
"""

import json
import logging
import os

import redis

logger = logging.getLogger("repair.cache")

TTL_SECONDS = 300

_client: redis.Redis | None = None


def init_cache() -> None:
    global _client
    _client = redis.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        decode_responses=True,  # работаем со строками, а не байтами
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    try:
        _client.ping()
        logger.info("Redis подключён")
    except redis.RedisError as e:
        logger.warning("Redis недоступен, работаем без кэша: %s", e)
        _client = None


def _key(ticket_id: int) -> str:
    return f"ticket:{ticket_id}"


def get_ticket(ticket_id: int) -> dict | None:
    if _client is None:
        return None
    try:
        raw = _client.get(_key(ticket_id))
        if raw is not None:
            logger.info("cache HIT: %s", _key(ticket_id))
            return json.loads(raw)
        logger.info("cache MISS: %s", _key(ticket_id))
    except redis.RedisError as e:
        logger.warning("ошибка чтения кэша: %s", e)
    return None


def set_ticket(ticket: dict) -> None:
    if _client is None:
        return
    try:
        _client.setex(_key(ticket["id"]), TTL_SECONDS, json.dumps(ticket))
    except redis.RedisError as e:
        logger.warning("ошибка записи в кэш: %s", e)


def invalidate(ticket_id: int) -> None:
    if _client is None:
        return
    try:
        _client.delete(_key(ticket_id))
        logger.info("cache INVALIDATE: %s", _key(ticket_id))
    except redis.RedisError as e:
        logger.warning("ошибка инвалидации кэша: %s", e)
