import boto3, datetime, time
from concurrent.futures import ThreadPoolExecutor, as_completed

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

queue_url = 'SQS_FACTOR_DEV'
send_queue_url = 'SQS_FACTOR_RESULT_DEV'
MAX_WORKERS = 8

def _build_entries(index, message):
    start = time.perf_counter()
    factor = int(message["MessageAttributes"]["Factor"]["StringValue"])
    scheme = int(message["MessageAttributes"]["Scheme"]["StringValue"])
    sent_time = int(message["Attributes"]["SentTimestamp"])
    seq = message["MessageId"]
    factor_list = do_factor(factor)
    ms = int((time.perf_counter() - start) * 1000)

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
        print(i)
    response = sqs.receive_message(
        QueueUrl=queue_url,
        AttributeNames=[
            'All'
        ],
        MaxNumberOfMessages=10,
        MessageAttributeNames=[
            'All'
        ],
        VisibilityTimeout=0,
        WaitTimeSeconds=20
    )

    messages = response.get('Messages', [])
    if not messages:
        break

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
    sqs.send_message_batch(
        QueueUrl=send_queue_url,
        Entries=send_entries
    )

    # Delete received messages from queue (batch)
    sqs.delete_message_batch(
        QueueUrl=queue_url,
        Entries=delete_entries
    )
