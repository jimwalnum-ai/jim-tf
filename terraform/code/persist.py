import boto3,json,os,psycopg2
import secrets
import time
import uuid
from datetime import datetime
from ast import literal_eval
from psycopg2 import sql

QUEUE_NAME = os.getenv("FACTOR_RESULT_QUEUE_NAME", "SQS_FACTOR_RESULT_DEV")
VISIBILITY_TIMEOUT_SECONDS = int(os.getenv("SQS_VISIBILITY_TIMEOUT_SECONDS", "300"))
done = False
# connect to database
sqs = boto3.client('sqs',region_name="us-east-1")
sec = boto3.client('secretsmanager',region_name="us-east-1")
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

conn_params = _build_conn_params(sec_data)
conn = _ensure_db(conn_params, db_name)
conn.autocommit = True
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
    AttributeNames=[
	'All'
    ],
    MaxNumberOfMessages=1,
    MessageAttributeNames=[
	'All'
    ],
    VisibilityTimeout=VISIBILITY_TIMEOUT_SECONDS,
    WaitTimeSeconds=20
 )

 try:
   message = response['Messages'][0]
 except: break
 receipt_handle = message['ReceiptHandle']
 msg_json = message["MessageAttributes"]
 fetch_started = time.monotonic()
 print(msg_json)

 process_time = int(message["Attributes"]["SentTimestamp"])
 scheme = int(msg_json["Scheme"]["StringValue"])
 sequence_raw = msg_json.get("Sequence", {}).get("StringValue")
 sent_time_raw = msg_json.get("SentTime", {}).get("StringValue")
 result =  literal_eval(msg_json["Result"]["StringValue"])
 ms = int((time.monotonic() - fetch_started) * 1000)
 data = {"factor":int(msg_json["Factor"]["StringValue"]),"result":result,"scheme":scheme,"ms":ms}

 if sequence_raw:
  data["sequence_raw"] = sequence_raw
 if sent_time_raw:
  data["sent_time"] = sent_time_raw

 sequence = _uuid7(sent_time_raw if sent_time_raw and sent_time_raw.isdigit() else process_time)
 cur.execute('INSERT INTO factors (sequence, data) VALUES (%s, %s)', (sequence, json.dumps(data)) )
 conn.commit() 
 
 sqs.delete_message(
    QueueUrl=queue_url,
    ReceiptHandle=receipt_handle
 )
