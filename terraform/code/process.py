import boto3,datetime

def do_factor(in_num):
    o_list = []
    for i in range(1, in_num):
       if in_num % i == 0: o_list.append(i)
    return(o_list)

# Create SQS client
sqs      = boto3.client('sqs',region_name="us-east-1")
sqs_send = boto3.client('sqs',region_name="us-east-1")

queue_url = 'SQS_FACTOR_DEV'
send_queue_url = 'SQS_FACTOR_RESULT_DEV'

done = False
# Receive message from SQS queue
i = 0
while not done:
 i += 1
 a = datetime.datetime.now()
 if divmod(i,1000)[1] == 0: print(i)
 response = sqs.receive_message(
    QueueUrl=queue_url,
    AttributeNames=[
        'All'
    ],
    MaxNumberOfMessages=1,
    MessageAttributeNames=[
        'All'
    ],
    VisibilityTimeout=0,
    WaitTimeSeconds=0
 )

 try: 
   message = response['Messages'][0]
 except: break  

 receipt_handle = message['ReceiptHandle']
 factor = int(message["MessageAttributes"]["Factor"]["StringValue"])
 scheme = int(message["MessageAttributes"]["Scheme"]["StringValue"])
 sent_time = int(message["Attributes"]["SentTimestamp"])
 seq = message["MessageId"]
 factor_list = do_factor(factor)
 b = datetime.datetime.now()
 delta = b - a
 ms =  int(delta.total_seconds() * 1000) # milliseconds

 # Send results to persist
 sqs_send.send_message(
    QueueUrl=send_queue_url,
    DelaySeconds=0,
    MessageAttributes={
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
            'StringValue': ms
        }
    },
    MessageBody=(
      'Factor'
    )
 )
 
 # Delete received message from queue
 sqs.delete_message(
    QueueUrl=queue_url,
    ReceiptHandle=receipt_handle
 )
