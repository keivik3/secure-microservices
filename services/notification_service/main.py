"""Notification Service — консьюмер событий из RabbitMQ.

Подписан на exchange 'repair.events' (topic) по шаблону 'repair.#' —
то есть получает ВСЕ события: created, assigned, status_changed, deleted.
Каждое событие превращает в текстовое уведомление и пишет в лог.
В учебной версии "уведомление" = запись в лог; в боевой — тут была бы
отправка email/Telegram диспетчеру и бригаде.

Надёжность:
  - очередь durable, сообщения подтверждаем вручную (ack) ПОСЛЕ обработки;
  - если сервис упал до ack — брокер вернёт сообщение в очередь
    (at-least-once delivery);
  - бесконечный цикл переподключения: брокер перезапустился — подключимся снова.
"""

import json
import logging
import os
import time

import pika
import pika.exceptions

logging.basicConfig(
    level=logging.INFO,
    format='{"ts": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "msg": "%(message)s"}',
)
logger = logging.getLogger("notification")

EXCHANGE = "repair.events"
QUEUE = "notifications"
BINDING_KEY = "repair.#"  # все события домена repair

# Кому адресовано уведомление по типу события
AUDIENCE = {
    "repair.created": "диспетчеру",
    "repair.assigned": "бригаде",
    "repair.status_changed": "диспетчеру и автору заявки",
    "repair.deleted": "диспетчеру",
}


def format_notification(event: dict) -> str:
    """Событие -> человекочитаемый текст уведомления."""
    kind = event.get("event", "?")
    audience = AUDIENCE.get(kind, "диспетчеру")
    text = (f"Уведомление {audience}: событие '{kind}', заявка №{event.get('ticket_id')} "
            f"(участок: {event.get('track_section')}, приоритет: {event.get('priority')}, "
            f"статус: {event.get('status')})")
    if kind == "repair.assigned" and event.get("crew"):
        text += f", бригада: {event['crew']}"
    # Критичный приоритет — особая пометка срочности
    if event.get("priority") == "CRITICAL":
        text = "!!! СРОЧНО !!! " + text
    return text


def on_message(channel, method, properties, body: bytes) -> None:
    """Callback брокера: обработать событие и подтвердить (ack)."""
    try:
        event = json.loads(body)
        logger.info(format_notification(event))
        channel.basic_ack(delivery_tag=method.delivery_tag)  # подтверждаем ПОСЛЕ обработки
    except (json.JSONDecodeError, KeyError) as e:
        logger.error("битое сообщение, отклоняем без повтора: %s", e)
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=False)


def run() -> None:
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

    while True:  # вечное переподключение при обрывах
        try:
            connection = pika.BlockingConnection(params)
            channel = connection.channel()
            channel.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)
            channel.queue_declare(queue=QUEUE, durable=True)
            channel.queue_bind(exchange=EXCHANGE, queue=QUEUE, routing_key=BINDING_KEY)
            channel.basic_qos(prefetch_count=1)  # по одному сообщению за раз
            channel.basic_consume(queue=QUEUE, on_message_callback=on_message)
            logger.info("слушаем очередь '%s' (binding '%s')", QUEUE, BINDING_KEY)
            channel.start_consuming()
        except pika.exceptions.AMQPError as e:
            logger.warning("потеряно соединение с брокером: %s; повтор через 5 сек", e)
            time.sleep(5)


if __name__ == "__main__":
    run()
