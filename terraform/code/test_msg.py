import boto3,random

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
