job "factor-test-msg" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "batch"

  periodic {
    crons            = ["*/2 * * * *"]
    prohibit_overlap = true
  }

  group "test-msg" {
    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    task "test-msg" {
      driver = "docker"

      config {
        image   = "python:3.11-slim"
        command = "/bin/sh"
        args    = ["-c", "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 'urllib3<2.0' && python /local/test_msg.py"]
      }

      template {
        destination = "local/test_msg.py"
        data        = <<PYEOF
import os, random, time, logging
from concurrent.futures import ThreadPoolExecutor, as_completed

import boto3

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

sqs = boto3.client('sqs', region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
QUEUE_NAME = os.getenv("FACTOR_QUEUE_NAME", "SQS_FACTOR_DEV")

def _resolve_queue_url(queue_name_or_url):
    if queue_name_or_url.startswith("https://"):
        return queue_name_or_url
    return sqs.get_queue_url(QueueName=queue_name_or_url)["QueueUrl"]

queue_url = _resolve_queue_url(QUEUE_NAME)

MESSAGES_MIN = 1000
MESSAGES_MAX = 1200
INTERVAL_SECONDS = 60
BATCH_SIZE = 10
MAX_WORKERS = 8
BATCH_DELAY_SECONDS = 0.25

def _build_entries(start_index, count):
    entries = []
    for offset in range(count):
        msg_index = start_index + offset
        entries.append({
            'Id': str(msg_index),
            'MessageBody': 'test',
            'MessageAttributes': {
                'Factor': {'DataType': 'Number', 'StringValue': str(random.randint(4, 400000))},
                'Scheme': {'DataType': 'Number', 'StringValue': '400000'},
            },
        })
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
PYEOF
      }

      env {
        AWS_DEFAULT_REGION = "us-east-1"
        FACTOR_QUEUE_NAME  = "SQS_FACTOR_DEV"
      }

      resources {
        cpu    = 256
        memory = 512
      }
    }
  }
}
