job "factor-persist" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "service"

  group "persist" {
    count = 0

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "persist" {
      driver = "docker"

      config {
        image   = "python:3.11-slim"
        command = "/bin/sh"
        args    = ["-c", "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 'urllib3<2.0' psycopg2-binary && while true; do python /local/persist.py || true; sleep 30; done"]
      }

      template {
        destination = "local/persist.py"
        data        = <<PYEOF
import boto3, json, os, psycopg2, secrets, time, uuid
from datetime import datetime
from ast import literal_eval
from psycopg2 import sql

QUEUE_NAME = os.getenv("FACTOR_RESULT_QUEUE_NAME", "SQS_FACTOR_RESULT_DEV")
VISIBILITY_TIMEOUT_SECONDS = int(os.getenv("SQS_VISIBILITY_TIMEOUT_SECONDS", "300"))
done = False

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
conn = _ensure_db(conn_params, db_name)
conn.autocommit = True
with conn.cursor() as _cur:
    _cur.execute("""
        CREATE TABLE IF NOT EXISTS factors (
            sequence UUID PRIMARY KEY,
            data JSONB NOT NULL
        )
    """)
cur = conn.cursor()

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

while not done:
    response = sqs.receive_message(
        QueueUrl=queue_url,
        AttributeNames=['All'],
        MaxNumberOfMessages=1,
        MessageAttributeNames=['All'],
        VisibilityTimeout=VISIBILITY_TIMEOUT_SECONDS,
        WaitTimeSeconds=20
    )
    try:
        message = response['Messages'][0]
    except:
        break
    pull_start = time.monotonic()
    pulled_at_ms = int(time.time() * 1000)
    receipt_handle = message['ReceiptHandle']
    msg_json = message["MessageAttributes"]
    fetch_started = time.monotonic()
    print(msg_json)

    process_time = int(message["Attributes"]["SentTimestamp"])
    scheme = int(msg_json["Scheme"]["StringValue"])
    sequence_raw = msg_json.get("Sequence", {}).get("StringValue")
    sent_time_raw = msg_json.get("SentTime", {}).get("StringValue")
    pulled_time_raw = msg_json.get("PulledTime", {}).get("StringValue")
    result = literal_eval(msg_json["Result"]["StringValue"])
    ms = int((time.monotonic() - fetch_started) * 1000)
    queue_to_db_ms = int((time.monotonic() - pull_start) * 1000)
    persisted_at_ms = int(time.time() * 1000)
    if pulled_time_raw and pulled_time_raw.isdigit():
        pull_to_persist_ms = persisted_at_ms - int(pulled_time_raw)
    else:
        pull_to_persist_ms = persisted_at_ms - pulled_at_ms
    data = {
        "factor": int(msg_json["Factor"]["StringValue"]),
        "result": result, "scheme": scheme, "ms": ms,
        "queue_to_db_ms": queue_to_db_ms, "pulled_at_ms": pulled_at_ms,
        "persisted_at_ms": persisted_at_ms, "pull_to_persist_ms": pull_to_persist_ms,
    }
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
    cur.execute('INSERT INTO factors (sequence, data) VALUES (%s, %s)', (sequence, json.dumps(data)))
    conn.commit()

    sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)
PYEOF
      }

      env {
        AWS_DEFAULT_REGION       = "us-east-1"
        FACTOR_RESULT_QUEUE_NAME = "SQS_FACTOR_RESULT_DEV"
        RDS_SECRET_NAME          = "cs-factor-credentials"
      }

      resources {
        cpu    = 256
        memory = 512
      }

      service {
        name     = "factor-persist"
        provider = "consul"

        check {
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "pgrep -f persist.py"]
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
