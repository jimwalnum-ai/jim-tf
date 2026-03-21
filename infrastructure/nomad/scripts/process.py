import boto3, time, os, logging, threading
from concurrent.futures import ProcessPoolExecutor

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

QUEUE_NAME = os.getenv("FACTOR_QUEUE_NAME", "SQS_FACTOR_DEV")
RESULT_QUEUE_NAME = os.getenv("FACTOR_RESULT_QUEUE_NAME", "SQS_FACTOR_RESULT_DEV")
VISIBILITY_TIMEOUT_SECONDS = int(os.getenv("SQS_VISIBILITY_TIMEOUT_SECONDS", "60"))
MAX_WORKERS = int(os.getenv("FACTOR_WORKERS", "4"))
RECEIVER_THREADS = int(os.getenv("RECEIVER_THREADS", "8"))


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


def _timed_factor(factor):
    t0 = time.monotonic()
    result = do_factor(factor)
    elapsed_ms = int((time.monotonic() - t0) * 1000)
    return result, elapsed_ms


def _build_entry(index, message, factor_list, factor_time_ms):
    pulled_time_ms = int(time.time() * 1000)
    factor = int(message["MessageAttributes"]["Factor"]["StringValue"])
    scheme = int(message["MessageAttributes"]["Scheme"]["StringValue"])
    sent_time = int(message["Attributes"]["SentTimestamp"])
    seq = message["MessageId"]
    ms = max(0, pulled_time_ms - sent_time)

    send_entry = {
        'Id': str(index),
        'DelaySeconds': 0,
        'MessageAttributes': {
            'Result':     {'DataType': 'String', 'StringValue': str(factor_list)},
            'SentTime':   {'DataType': 'String', 'StringValue': str(sent_time)},
            'PulledTime': {'DataType': 'String', 'StringValue': str(pulled_time_ms)},
            'Sequence':   {'DataType': 'String', 'StringValue': str(seq)},
            'Factor':     {'DataType': 'String', 'StringValue': str(factor)},
            'Scheme':     {'DataType': 'String', 'StringValue': str(scheme)},
            'ms':         {'DataType': 'Number', 'StringValue': str(ms)},
            'FactorTime': {'DataType': 'Number', 'StringValue': str(factor_time_ms)},
        },
        'MessageBody': 'Factor'
    }
    delete_entry = {'Id': str(index), 'ReceiptHandle': message['ReceiptHandle']}
    return send_entry, delete_entry


def _receiver_loop(thread_id, pool, sqs, queue_url, send_queue_url):
    """Pull from SQS, farm factor computation to the process pool, send results."""
    empty_polls = 0
    processed = 0
    while True:
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
            empty_polls += 1
            if empty_polls >= 3:
                break
            continue
        empty_polls = 0

        factors = [int(m["MessageAttributes"]["Factor"]["StringValue"]) for m in messages]
        futures = [pool.submit(_timed_factor, f) for f in factors]

        send_entries = []
        delete_entries = []
        for idx, (msg, fut) in enumerate(zip(messages, futures)):
            factor_list, factor_time_ms = fut.result()
            se, de = _build_entry(idx, msg, factor_list, factor_time_ms)
            send_entries.append(se)
            delete_entries.append(de)

        send_response = sqs.send_message_batch(
            QueueUrl=send_queue_url, Entries=send_entries
        )
        failed_send = send_response.get("Failed", [])
        if failed_send:
            logger.error("thread=%s send_failures=%s", thread_id, failed_send)
            failed_ids = {e["Id"] for e in failed_send}
            delete_entries = [e for e in delete_entries if e["Id"] not in failed_ids]

        if delete_entries:
            sqs.delete_message_batch(QueueUrl=queue_url, Entries=delete_entries)

        processed += len(messages)
        if processed % 100 < 11:
            logger.info("thread=%s processed=%s", thread_id, processed)

    logger.info("thread=%s done processed=%s", thread_id, processed)


if __name__ == "__main__":
    sqs = boto3.client('sqs', region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))

    def _resolve(name):
        return name if name.startswith("https://") else sqs.get_queue_url(QueueName=name)["QueueUrl"]

    queue_url = _resolve(QUEUE_NAME)
    send_queue_url = _resolve(RESULT_QUEUE_NAME)

    pool = ProcessPoolExecutor(max_workers=MAX_WORKERS)
    threads = []
    for tid in range(RECEIVER_THREADS):
        t = threading.Thread(
            target=_receiver_loop,
            args=(tid, pool, sqs, queue_url, send_queue_url),
            daemon=True,
        )
        t.start()
        threads.append(t)

    for t in threads:
        t.join()
    pool.shutdown(wait=True)
    logger.info("all_threads_done")
