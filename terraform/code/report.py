import boto3,json,os,psycopg2
from psycopg2 import sql

sec = boto3.client('secretsmanager',region_name="us-east-1")
response = sec.get_secret_value(
    SecretId='cs-factor-credentials',
)

sec_data = json.loads(response["SecretString"])

db_name = os.getenv("FACTOR_DB_NAME", sec_data.get("database", "factors"))

def _build_conn_params(secret_data):
    host = secret_data["host"]
    port = secret_data.get("port")
    if host and ":" in host:
        host_part, host_port = host.rsplit(":", 1)
        if host_port.isdigit():
            host = host_part
            if not port:
                port = host_port
    params = {
        "user": secret_data["username"],
        "password": secret_data["password"],
        "host": host,
    }
    if port:
        params["port"] = int(port)
    return params

def _connect_db(params, name):
    return psycopg2.connect(**params, dbname=name)

def _ensure_db(params, name):
    try:
        return _connect_db(params, name)
    except psycopg2.OperationalError as exc:
        if f'database "{name}" does not exist' not in str(exc):
            raise
        admin_db = os.getenv("POSTGRES_ADMIN_DB", "postgres")
        admin_conn = _connect_db(params, admin_db)
        admin_conn.autocommit = True
        with admin_conn.cursor() as admin_cur:
            admin_cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(name)))
        admin_conn.close()
        return _connect_db(params, name)

conn_params = _build_conn_params(sec_data)
conn = _ensure_db(conn_params, db_name)
cursor = conn.cursor()
  
sql1 = '''select * from factors where json_array_length("data"::json -> 'result') = 1'''
cursor.execute(sql1)
for i in cursor.fetchall():
    print(i)
  
conn.close()
