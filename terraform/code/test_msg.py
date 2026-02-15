import random
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

# Send message to SQS queue
for i in range(5000):
 if divmod(i,1000)[1] == 0: print(i) 
 response = sqs.send_message(
    QueueUrl=queue_url,
    DelaySeconds=0,
    MessageAttributes={
        'Factor': {
            'DataType': 'Number',
            'StringValue': str(random.randint(4,16000))
        },
        'Scheme': {
            'DataType': 'Number',
            'StringValue': "16000"
        }
    },
    MessageBody=(
        "test"
    )
 )

print(response['MessageId'])
