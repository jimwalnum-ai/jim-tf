import boto3,json,psycopg2
from datetime import datetime
from ast import literal_eval

queue_url = 'SQS_FACTOR_RESULT_DEV'
done = False
# connect to database
sqs = boto3.client('sqs',region_name="us-east-1")
sec = boto3.client('secretsmanager',region_name="us-east-1")
response = sec.get_secret_value(
    SecretId='cs-factor-credentials',
)
print(response)
sec_data = json.loads(response["SecretString"])

conn_string = 'postgresql://' + sec_data['username'] + ":" + sec_data["password"] +"@" + sec_data["host"] + '/factors'
  
conn = psycopg2.connect(conn_string)
conn.autocommit = True
cur = conn.cursor()

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
    VisibilityTimeout=0,
    WaitTimeSeconds=0
 )

 try:
   message = response['Messages'][0]
 except: break
 receipt_handle = message['ReceiptHandle']
 msg_json = message["MessageAttributes"]
 print(msg_json)

 process_time = int(message["Attributes"]["SentTimestamp"])
 scheme = int(msg_json["Scheme"]["StringValue"])
 sequence = msg_json["Sequence"]["StringValue"]
 ms = int(msg_json["ms"]["StringValue"])
 result =  literal_eval(msg_json["Result"]["StringValue"])
 data = {"factor":int(msg_json["Factor"]["StringValue"]),"result":result,"scheme":scheme,"ms":ms}

 cur.execute('INSERT INTO factors VALUES (%s, %s)', (sequence, json.dumps(data)) )
 conn.commit() 
 
 sqs.delete_message(
    QueueUrl=queue_url,
    ReceiptHandle=receipt_handle
 )
