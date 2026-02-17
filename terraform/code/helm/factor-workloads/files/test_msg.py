import random
from concurrent.futures import ThreadPoolExecutor, as_completed
from importlib.metadata import PackageNotFoundError, version

try:
    import boto3
except ModuleNotFoundError as exc:
    raise SystemExit("boto3 is required. Install with: pip install -r docker/requirements.txt") from exc


def _ensure_urllib3_legacy():
    try:
        urllib3_version = version("urllib3")
    except PackageNotFoundError:
        return
    major = int(urllib3_version.split(".")[0])
    if major >= 2:
        raise SystemExit("urllib3>=2.0 is incompatible with botocore in this repo; install urllib3<1.27.")


_ensure_urllib3_legacy()

# Create SQS client
sqs = boto3.client('sqs',region_name="us-east-1")

queue_url = 'SQS_FACTOR_DEV'

TOTAL_MESSAGES = 5000
BATCH_SIZE = 10
MAX_WORKERS = 16


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
                        'StringValue': str(random.randint(4, 16000)),
                    },
                    'Scheme': {
                        'DataType': 'Number',
                        'StringValue': '16000',
                    },
                },
            }
        )
    return entries


def _send_batch(entries):
    response = sqs.send_message_batch(QueueUrl=queue_url, Entries=entries)
    failed = response.get('Failed')
    if failed:
        raise RuntimeError(f"Failed to send {len(failed)} messages: {failed}")
    return response


# Send messages to SQS queue using batch + concurrency
futures = []
with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
    for start in range(0, TOTAL_MESSAGES, BATCH_SIZE):
        if start % 100 == 0:
            print(start)
        count = min(BATCH_SIZE, TOTAL_MESSAGES - start)
        entries = _build_entries(start, count)
        futures.append(executor.submit(_send_batch, entries))

last_message_id = None
for future in as_completed(futures):
    response = future.result()
    successful = response.get('Successful', [])
    if successful:
        last_message_id = successful[-1].get('MessageId')

if last_message_id:
    print(last_message_id)
