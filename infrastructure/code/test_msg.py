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

INITIAL_MESSAGES = 200000
TOPUP_MESSAGES = 100000
TOPUP_INTERVAL_SECONDS = 180
TOTAL_LIMIT = 700000
SCHEME_MIN = 400000
SCHEME_MAX = 500000000
BATCH_SIZE = 10
MAX_WORKERS = 40


def _pick_scheme():
    return random.randint(SCHEME_MIN, SCHEME_MAX)


def _build_entries(start_index: int, count: int, scheme: int):
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
                        'StringValue': str(random.randint(4, scheme)),
                    },
                    'Scheme': {
                        'DataType': 'Number',
                        'StringValue': str(scheme),
                    },
                    'Runtime': {
                        'DataType': 'String',
                        'StringValue': 'python',
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
    logger.debug("sent_messages=%s", len(response.get('Successful', [])))
    return response


def _send_messages(count, scheme, offset=0):
    logger.info("sending count=%s scheme=%s offset=%s", count, scheme, offset)
    futures = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        for start in range(0, count, BATCH_SIZE):
            if start % 10000 == 0:
                logger.info("batch_start=%s", offset + start)
            batch_count = min(BATCH_SIZE, count - start)
            entries = _build_entries(offset + start, batch_count, scheme)
            futures.append(executor.submit(_send_batch, entries))
    for future in as_completed(futures):
        future.result()
    logger.info("send_complete count=%s total_sent=%s", count, offset + count)


scheme = _pick_scheme()
logger.info("scheme=%s initial=%s topup=%s limit=%s", scheme, INITIAL_MESSAGES, TOPUP_MESSAGES, TOTAL_LIMIT)

total_sent = 0

_send_messages(INITIAL_MESSAGES, scheme, total_sent)
total_sent += INITIAL_MESSAGES

while total_sent < TOTAL_LIMIT:
    logger.info("sleeping %ss before next top-up, total_sent=%s", TOPUP_INTERVAL_SECONDS, total_sent)
    time.sleep(TOPUP_INTERVAL_SECONDS)
    scheme = _pick_scheme()
    remaining = TOTAL_LIMIT - total_sent
    batch = min(TOPUP_MESSAGES, remaining)
    _send_messages(batch, scheme, total_sent)
    total_sent += batch

logger.info("done total_sent=%s", total_sent)
