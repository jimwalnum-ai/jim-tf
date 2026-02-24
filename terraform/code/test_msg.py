import json
import os
import random
import time
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from importlib.metadata import PackageNotFoundError, version

try:
    import boto3
except ModuleNotFoundError as exc:
    raise SystemExit("boto3 is required. Install with: pip install -r docker/requirements.txt") from exc

import psycopg2
from psycopg2 import sql


def _ensure_urllib3_legacy():
    try:
        urllib3_version = version("urllib3")
    except PackageNotFoundError:
        return
    major = int(urllib3_version.split(".")[0])
    if major >= 2:
        raise SystemExit("urllib3>=2.0 is incompatible with botocore in this repo; install urllib3<1.27.")


_ensure_urllib3_legacy()

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

sec = boto3.client('secretsmanager', region_name="us-east-1")
response = sec.get_secret_value(
    SecretId='cs-factor-credentials',
)
sec_data = json.loads(response["SecretString"])

db_name = os.getenv("FACTOR_DB_NAME", sec_data.get("database", "factors"))

def _build_conn_params(secret_data):
    host = secret_data["host"]
    port = secret_data.get("port")
    if host and ":" in host:
        host_part, host_port = host.rsplit(":", 1)
        if host_port.isdigit():
            host = host_part
            if not port:
                port = host_port
    params = {
        "user": secret_data["username"],
        "password": secret_data["password"],
        "host": host,
    }
    if port:
        params["port"] = int(port)
    return params


def _connect_db(params, name):
    return psycopg2.connect(**params, dbname=name)


def _ensure_db(params, name):
    try:
        return _connect_db(params, name)
    except psycopg2.OperationalError as exc:
        if f'database "{name}" does not exist' not in str(exc):
            raise
        admin_db = os.getenv("POSTGRES_ADMIN_DB", "postgres")
        admin_conn = _connect_db(params, admin_db)
        admin_conn.autocommit = True
        with admin_conn.cursor() as admin_cur:
            admin_cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(name)))
        admin_conn.close()
        return _connect_db(params, name)


def _ensure_table(conn):
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS factors (
                sequence UUID PRIMARY KEY,
                data JSONB NOT NULL
            )
            """
        )


conn_params = _build_conn_params(sec_data)
conn = _ensure_db(conn_params, db_name)
conn.autocommit = True
_ensure_table(conn)
conn.close()

# Create SQS client
sqs = boto3.client('sqs', region_name="us-east-1")

QUEUE_NAME = os.getenv("FACTOR_QUEUE_NAME", "SQS_FACTOR_DEV")


def _resolve_queue_url(queue_name_or_url):
    if queue_name_or_url.startswith("https://"):
        return queue_name_or_url
    return sqs.get_queue_url(QueueName=queue_name_or_url)["QueueUrl"]


queue_url = _resolve_queue_url(QUEUE_NAME)

MESSAGES_PER_MINUTE = 1000
MESSAGES_MIN = 1000
MESSAGES_MAX = 1200
INTERVAL_SECONDS = 60
BATCH_SIZE = 10
MAX_WORKERS = 8
BATCH_DELAY_SECONDS = 0.25


def _build_entries(start_index: int, count: int):
    entries = []
    for offset in range(count):
        msg_index = start_index + offset
        entries.append(
            {
                'Id': str(msg_index),
                'MessageBody': 'test',
                'MessageAttributes': {
                    'Factor': {
                        'DataType': 'Number',
                        'StringValue': str(random.randint(4, 400000)),
                    },
                    'Scheme': {
                        'DataType': 'Number',
                        'StringValue': '400000',
                    },
                },
            }
        )
    return entries


def _send_batch(entries):
    response = sqs.send_message_batch(QueueUrl=queue_url, Entries=entries)
    failed = response.get('Failed')
    if failed:
        logger.error("failed_to_send=%s details=%s", len(failed), failed)
        raise RuntimeError(f"Failed to send {len(failed)} messages: {failed}")
    logger.info("sent_messages=%s", len(response.get('Successful', [])))
    return response


while True:
    target_messages = random.randint(MESSAGES_MIN, MESSAGES_MAX)
    logger.info("target_messages=%s", target_messages)
    futures = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        for start in range(0, target_messages, BATCH_SIZE):
            if start % 100 == 0:
                logger.info("batch_start=%s", start)
            count = min(BATCH_SIZE, target_messages - start)
            entries = _build_entries(start, count)
            futures.append(executor.submit(_send_batch, entries))
            time.sleep(BATCH_DELAY_SECONDS)

    last_message_id = None
    for future in as_completed(futures):
        response = future.result()
        successful = response.get('Successful', [])
        if successful:
            last_message_id = successful[-1].get('MessageId')

    if last_message_id:
        logger.info("last_message_id=%s", last_message_id)

    time.sleep(INTERVAL_SECONDS)
