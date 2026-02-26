job "factor-process" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "service"

  group "process" {
    count = 0

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "process" {
      driver = "docker"

      config {
        image   = "${docker_image}"
        command = "/bin/sh"
        args    = ["-c", "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 'urllib3<2.0' && while true; do python /local/process.py || true; sleep 30; done"]
      }

      template {
        destination = "local/process.py"
        data        = <<PYEOF
import boto3, datetime, time, os, logging
from concurrent.futures import ThreadPoolExecutor, as_completed

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

def do_factor(in_num):
    if in_num <= 1:
        return []
    small = []
    large = []
    limit = int(in_num ** 0.5)
    for i in range(1, limit + 1):
        if in_num % i == 0:
            if i != in_num:
                small.append(i)
            other = in_num // i
            if other != i and other != in_num:
                large.append(other)
    return small + large[::-1]

sqs = boto3.client('sqs', region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))

QUEUE_NAME = os.getenv("FACTOR_QUEUE_NAME", "${factor_queue_name}")
RESULT_QUEUE_NAME = os.getenv("FACTOR_RESULT_QUEUE_NAME", "${factor_result_queue_name}")
VISIBILITY_TIMEOUT_SECONDS = int(os.getenv("SQS_VISIBILITY_TIMEOUT_SECONDS", "300"))
MAX_WORKERS = 8

def _resolve_queue_url(queue_name_or_url):
    if queue_name_or_url.startswith("https://"):
        return queue_name_or_url
    return sqs.get_queue_url(QueueName=queue_name_or_url)["QueueUrl"]

queue_url = _resolve_queue_url(QUEUE_NAME)
send_queue_url = _resolve_queue_url(RESULT_QUEUE_NAME)

def _build_entries(index, message):
    pulled_time_ms = int(time.time() * 1000)
    factor = int(message["MessageAttributes"]["Factor"]["StringValue"])
    scheme = int(message["MessageAttributes"]["Scheme"]["StringValue"])
    sent_time = int(message["Attributes"]["SentTimestamp"])
    seq = message["MessageId"]
    factor_list = do_factor(factor)
    ms = max(0, pulled_time_ms - sent_time)

    send_entry = {
        'Id': str(index),
        'DelaySeconds': 0,
        'MessageAttributes': {
            'Result':    {'DataType': 'String', 'StringValue': str(factor_list)},
            'SentTime':  {'DataType': 'String', 'StringValue': str(sent_time)},
            'PulledTime':{'DataType': 'String', 'StringValue': str(pulled_time_ms)},
            'Sequence':  {'DataType': 'String', 'StringValue': str(seq)},
            'Factor':    {'DataType': 'String', 'StringValue': str(factor)},
            'Scheme':    {'DataType': 'String', 'StringValue': str(scheme)},
            'ms':        {'DataType': 'Number', 'StringValue': str(ms)},
        },
        'MessageBody': 'Factor'
    }
    delete_entry = {'Id': str(index), 'ReceiptHandle': message['ReceiptHandle']}
    return index, send_entry, delete_entry

done = False
i = 0
while not done:
    i += 1
    if i % 100 == 0:
        logger.info("poll_count=%s", i)
    response = sqs.receive_message(
        QueueUrl=queue_url,
        AttributeNames=['All'],
        MaxNumberOfMessages=10,
        MessageAttributeNames=['All'],
        VisibilityTimeout=VISIBILITY_TIMEOUT_SECONDS,
        WaitTimeSeconds=20
    )
    messages = response.get('Messages', [])
    if not messages:
        logger.info("no_messages_received")
        break

    logger.info("received_messages=%s", len(messages))
    send_entries = [None] * len(messages)
    delete_entries = [None] * len(messages)
    max_workers = min(MAX_WORKERS, len(messages))
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(_build_entries, idx, msg) for idx, msg in enumerate(messages)]
        for future in as_completed(futures):
            idx, se, de = future.result()
            send_entries[idx] = se
            delete_entries[idx] = de

    send_response = sqs.send_message_batch(QueueUrl=send_queue_url, Entries=send_entries)
    failed_send = send_response.get("Failed", [])
    if failed_send:
        logger.error("send_failures=%s", failed_send)
        failed_ids = {entry["Id"] for entry in failed_send}
        delete_entries = [e for e in delete_entries if e["Id"] not in failed_ids]
    else:
        logger.info("sent_messages=%s", len(send_entries))

    if delete_entries:
        sqs.delete_message_batch(QueueUrl=queue_url, Entries=delete_entries)
        logger.info("deleted_messages=%s", len(delete_entries))
PYEOF
      }

      env {
        AWS_DEFAULT_REGION       = "us-east-1"
        FACTOR_QUEUE_NAME        = "${factor_queue_name}"
        FACTOR_RESULT_QUEUE_NAME = "${factor_result_queue_name}"
      }

      resources {
        cpu    = 256
        memory = 512
      }

      service {
        name     = "factor-process"
        provider = "consul"

        check {
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "pgrep -f process.py"]
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
