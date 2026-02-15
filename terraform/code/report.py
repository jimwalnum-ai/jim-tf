import psycopg2,boto3,json

sec = boto3.client('secretsmanager',region_name="us-east-1")
response = sec.get_secret_value(
    SecretId='cs-factor-credentials',
)

sec_data = json.loads(response["SecretString"])

conn_string = 'postgresql://' + sec_data['username'] + ":" + sec_data["password"] +"@" + sec_data["host"] + '/factors'

conn = psycopg2.connect(conn_string)
cursor = conn.cursor()
  
sql1 = '''select * from factors where json_array_length("data"::json -> 'result') = 1'''
cursor.execute(sql1)
for i in cursor.fetchall():
    print(i)
  
conn.close()
