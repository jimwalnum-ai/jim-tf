import boto3, json, os, psycopg2, secrets, time, uuid, threading
from ast import literal_eval
from concurrent.futures import ThreadPoolExecutor
from psycopg2 import sql
from psycopg2.extras import execute_values

QUEUE_NAME = os.getenv("FACTOR_RESULT_QUEUE_NAME", "SQS_FACTOR_RESULT_DEV")
VISIBILITY_TIMEOUT_SECONDS = int(os.getenv("SQS_VISIBILITY_TIMEOUT_SECONDS", "300"))
BATCH_SIZE = int(os.getenv("SQS_BATCH_SIZE", "10"))
WORKER_COUNT = int(os.getenv("PERSIST_WORKER_COUNT", "4"))

sqs = boto3.client('sqs', region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
sec = boto3.client('secretsmanager', region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
response = sec.get_secret_value(SecretId=os.getenv("RDS_SECRET_NAME", "cs-factor-credentials"))
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
    params = {"user": secret_data["username"], "password": secret_data["password"], "host": host}
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

conn_params = _build_conn_params(sec_data)
init_conn = _ensure_db(conn_params, db_name)
init_conn.autocommit = True
with init_conn.cursor() as _cur:
    _cur.execute("""
        CREATE TABLE IF NOT EXISTS factors (
            sequence UUID PRIMARY KEY,
            data JSONB NOT NULL
        )
    """)
init_conn.close()

def _resolve_queue_url(queue_name_or_url):
    if queue_name_or_url.startswith("https://"):
        return queue_name_or_url
    return sqs.get_queue_url(QueueName=queue_name_or_url)["QueueUrl"]

queue_url = _resolve_queue_url(QUEUE_NAME)

def _uuid7(timestamp_ms=None):
    if timestamp_ms is None:
        timestamp_ms = int(time.time() * 1000)
    ts = int(timestamp_ms) & ((1 << 48) - 1)
    rand_a = secrets.randbits(12)
    rand_b = secrets.randbits(62)
    uuid_int = (ts << 80) | (0x7 << 76) | (rand_a << 64) | (0x2 << 62) | rand_b
    return str(uuid.UUID(int=uuid_int))

def _parse_message(message):
    pull_start = time.monotonic()
    pulled_at_ms = int(time.time() * 1000)
    msg_json = message["MessageAttributes"]

    process_time = int(message["Attributes"]["SentTimestamp"])
    scheme = int(msg_json["Scheme"]["StringValue"])
    sequence_raw = msg_json.get("Sequence", {}).get("StringValue")
    sent_time_raw = msg_json.get("SentTime", {}).get("StringValue")
    pulled_time_raw = msg_json.get("PulledTime", {}).get("StringValue")
    factor_time_raw = msg_json.get("FactorTime", {}).get("StringValue")
    result = literal_eval(msg_json["Result"]["StringValue"])
    ms = int((time.monotonic() - pull_start) * 1000)
    persisted_at_ms = int(time.time() * 1000)

    if pulled_time_raw and pulled_time_raw.isdigit():
        pull_to_persist_ms = persisted_at_ms - int(pulled_time_raw)
    else:
        pull_to_persist_ms = persisted_at_ms - pulled_at_ms

    data = {
        "factor": int(msg_json["Factor"]["StringValue"]),
        "result": result, "scheme": scheme, "ms": ms,
        "queue_to_db_ms": ms, "pulled_at_ms": pulled_at_ms,
        "persisted_at_ms": persisted_at_ms, "pull_to_persist_ms": pull_to_persist_ms,
    }
    if factor_time_raw and factor_time_raw.isdigit():
        data["factor_time_ms"] = int(factor_time_raw)
    if sequence_raw:
        data["sequence_raw"] = sequence_raw
    if sent_time_raw:
        data["sent_time"] = sent_time_raw
        if sent_time_raw.isdigit():
            persisted_at_ms = int(time.time() * 1000)
            data["sent_to_persist_ms"] = persisted_at_ms - int(sent_time_raw)
    if pulled_time_raw:
        data["pulled_time"] = pulled_time_raw

    sequence = _uuid7(sent_time_raw if sent_time_raw and sent_time_raw.isdigit() else process_time)
    return sequence, json.dumps(data), message['ReceiptHandle']

def _worker(worker_id):
    conn = _ensure_db(conn_params, db_name)
    conn.autocommit = False
    cur = conn.cursor()
    print(f"[worker-{worker_id}] started")

    while True:
        resp = sqs.receive_message(
            QueueUrl=queue_url,
            AttributeNames=['All'],
            MaxNumberOfMessages=BATCH_SIZE,
            MessageAttributeNames=['All'],
            VisibilityTimeout=VISIBILITY_TIMEOUT_SECONDS,
            WaitTimeSeconds=20,
        )
        messages = resp.get('Messages', [])
        if not messages:
            break

        rows = []
        receipts = []
        for msg in messages:
            try:
                seq, data_json, receipt = _parse_message(msg)
                rows.append((seq, data_json))
                receipts.append(receipt)
            except Exception as e:
                print(f"[worker-{worker_id}] parse error: {e}")

        if rows:
            execute_values(cur, 'INSERT INTO factors (sequence, data) VALUES %s ON CONFLICT (sequence) DO NOTHING', rows)
            conn.commit()

        if receipts:
            for i in range(0, len(receipts), 10):
                batch = [{'Id': str(j), 'ReceiptHandle': r} for j, r in enumerate(receipts[i:i+10])]
                sqs.delete_message_batch(QueueUrl=queue_url, Entries=batch)

        print(f"[worker-{worker_id}] persisted {len(rows)} messages")

    cur.close()
    conn.close()
    print(f"[worker-{worker_id}] done (queue empty)")

with ThreadPoolExecutor(max_workers=WORKER_COUNT) as pool:
    futures = [pool.submit(_worker, i) for i in range(WORKER_COUNT)]
    for f in futures:
        f.result()
