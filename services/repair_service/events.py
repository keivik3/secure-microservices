"""Издатель событий в RabbitMQ.

Exchange: repair.events (тип topic, durable).
Routing keys: repair.created, repair.assigned, repair.status_changed, repair.deleted.
Консьюмер — notification-service.

Соединение ленивое с переподключением: если брокер недоступен, запрос
клиента НЕ падает — событие теряется, ошибка пишется в лог. Для учебного
проекта это осознанный компромисс; в бою использовали бы outbox-паттерн
(событие сначала пишется в БД, потом вычитывается ретраером).
"""

import json
import logging
import os
import time

import pika
import pika.exceptions

logger = logging.getLogger("repair.events")

EXCHANGE = "repair.events"

_connection: pika.BlockingConnection | None = None
_channel = None


def _connect() -> None:
    global _connection, _channel
    credentials = pika.PlainCredentials(
        os.getenv("RABBITMQ_USER", "app"),
        os.getenv("RABBITMQ_PASS", "app_secret"),
    )
    params = pika.ConnectionParameters(
        host=os.getenv("RABBITMQ_HOST", "localhost"),
        port=int(os.getenv("RABBITMQ_PORT", "5672")),
        credentials=credentials,
        connection_attempts=3,
        retry_delay=2,
    )
    _connection = pika.BlockingConnection(params)
    _channel = _connection.channel()
    _channel.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)
    logger.info("RabbitMQ подключён, exchange '%s' объявлен", EXCHANGE)


def init_events() -> None:
    try:
        _connect()
    except pika.exceptions.AMQPError as e:
        logger.warning("RabbitMQ недоступен при старте, переподключимся при отправке: %s", e)


def publish(routing_key: str, ticket: dict) -> None:
    """Публикует событие. При недоступности брокера — только лог."""
    global _channel
    payload = {
        "event": routing_key,
        "ticket_id": ticket["id"],
        "track_section": ticket["track_section"],
        "priority": ticket["priority"],
        "status": ticket["status"],
        "crew": ticket.get("crew", ""),
        "reporter": ticket["reporter"],
        "ts": int(time.time()),
    }
    for attempt in range(2):  # вторая попытка — после переподключения
        try:
            if _channel is None or _channel.is_closed:
                _connect()
            _channel.basic_publish(
                exchange=EXCHANGE,
                routing_key=routing_key,
                body=json.dumps(payload, ensure_ascii=False),
                properties=pika.BasicProperties(
                    delivery_mode=2,  # persistent: переживёт рестарт брокера
                    content_type="application/json",
                ),
            )
            logger.info("событие %s опубликовано: ticket_id=%s", routing_key, ticket["id"])
            return
        except pika.exceptions.AMQPError as e:
            logger.error("не удалось опубликовать %s (попытка %d): %s", routing_key, attempt + 1, e)
            _channel = None
