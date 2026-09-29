import json
import logging
import os
import time
from decimal import Decimal, InvalidOperation

import pika
from sqlalchemy.exc import SQLAlchemyError

from app.db import Order, get_session_factory

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("billing-consumer")

DB_RETRY_DELAY = 3  # seconds to wait before requeueing after a database error


def connect():
    host = os.environ["RABBITMQ_HOST"]
    port = int(os.environ["RABBITMQ_PORT"])
    user = os.environ["RABBITMQ_USER"]
    password = os.environ["RABBITMQ_PASSWORD"]

    credentials = pika.PlainCredentials(user, password)
    parameters = pika.ConnectionParameters(host=host, port=port, credentials=credentials, heartbeat=30)

    while True:
        try:
            return pika.BlockingConnection(parameters)
        except pika.exceptions.AMQPConnectionError:
            logger.warning("RabbitMQ not reachable yet, retrying in 3s...")
            time.sleep(3)


def parse_order(body):
    """Build an Order from a message body. Raises ValueError if the message is invalid."""
    try:
        payload = json.loads(body)
        total_amount = Decimal(str(payload["total_amount"]))
        if not total_amount.is_finite():
            raise ValueError("total_amount is not finite")
        return Order(
            user_id=str(payload["user_id"]),
            number_of_items=int(payload["number_of_items"]),
            total_amount=total_amount,
        )
    except (ValueError, KeyError, TypeError, InvalidOperation) as exc:
        raise ValueError(f"invalid order message: {exc!r}") from exc


def run():
    queue_name = os.environ["BILLING_QUEUE"]
    session_factory = get_session_factory()

    connection = connect()
    channel = connection.channel()
    channel.queue_declare(queue=queue_name, durable=True)
    channel.basic_qos(prefetch_count=1)

    def on_message(ch, method, _properties, body):
        try:
            order = parse_order(body)
        except ValueError:
            # A malformed message will never succeed: drop it instead of
            # requeueing, or it would block every message behind it.
            logger.exception("Discarding message: %r", body)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
            return

        user_id = order.user_id  # read before commit expires the object
        session = session_factory()
        try:
            session.add(order)
            session.commit()
        except SQLAlchemyError:
            # Database problems are temporary: keep the message and retry.
            session.rollback()
            logger.exception("Database error, requeueing in %ss", DB_RETRY_DELAY)
            time.sleep(DB_RETRY_DELAY)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
            return
        finally:
            session.close()

        logger.info("Stored order for user_id=%s", user_id)
        ch.basic_ack(delivery_tag=method.delivery_tag)

    channel.basic_consume(queue=queue_name, on_message_callback=on_message)
    logger.info("Billing consumer started, waiting for messages on '%s'", queue_name)
    channel.start_consuming()
