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

# Create SQS client
sqs = boto3.client('sqs', region_name="us-east-1")

QUEUE_NAME = os.getenv("FACTOR_QUEUE_NAME", "SQS_FACTOR_DEV")
RESULT_QUEUE_NAME = os.getenv("FACTOR_RESULT_QUEUE_NAME", "SQS_FACTOR_RESULT_DEV")
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
    t0 = time.monotonic()
    factor_list = do_factor(factor)
    factor_time_ms = int((time.monotonic() - t0) * 1000)
    ms = max(0, pulled_time_ms - sent_time)

    send_entry = {
        'Id': str(index),
        'DelaySeconds': 0,
        'MessageAttributes': {
            'Result': {
                'DataType': 'String',
                'StringValue': str(factor_list)
            },
            'SentTime': {
                'DataType': 'String',
                'StringValue': str(sent_time)
            },
            'PulledTime': {
                'DataType': 'String',
                'StringValue': str(pulled_time_ms)
            },
            'Sequence': {
                'DataType': 'String',
                'StringValue': str(seq)
            },
            'Factor': {
                'DataType': 'String',
                'StringValue': str(factor)
            },
            'Scheme': {
                'DataType': 'String',
                'StringValue': str(scheme)
            },
            'ms': {
                'DataType': 'Number',
                'StringValue': str(ms)
            },
            'FactorTime': {
                'DataType': 'Number',
                'StringValue': str(factor_time_ms)
            }
        },
        'MessageBody': 'Factor'
    }

    delete_entry = {
        'Id': str(index),
        'ReceiptHandle': message['ReceiptHandle']
    }

    return index, send_entry, delete_entry

done = False
# Receive message from SQS queue
i = 0
while not done:
    i += 1
    if i % 100 == 0:
        logger.info("poll_count=%s", i)
    response = sqs.receive_message(
        QueueUrl=queue_url,
        AttributeNames=[
            'All'
        ],
        MaxNumberOfMessages=10,
        MessageAttributeNames=[
            'All'
        ],
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
        futures = [executor.submit(_build_entries, index, message) for index, message in enumerate(messages)]
        for future in as_completed(futures):
            index, send_entry, delete_entry = future.result()
            send_entries[index] = send_entry
            delete_entries[index] = delete_entry

    # Send results to persist (batch)
    send_response = sqs.send_message_batch(
        QueueUrl=send_queue_url,
        Entries=send_entries
    )
    failed_send = send_response.get("Failed", [])
    if failed_send:
        logger.error("send_failures=%s", failed_send)
        failed_ids = {entry["Id"] for entry in failed_send}
        delete_entries = [entry for entry in delete_entries if entry["Id"] not in failed_ids]
    else:
        logger.info("sent_messages=%s", len(send_entries))

    if delete_entries:
        # Delete received messages from queue (batch)
        sqs.delete_message_batch(
            QueueUrl=queue_url,
            Entries=delete_entries
        )
        logger.info("deleted_messages=%s", len(delete_entries))
