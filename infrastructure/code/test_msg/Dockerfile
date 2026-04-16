FROM python:3.11-slim

RUN pip install --no-cache-dir \
    boto3==1.42.49 \
    botocore==1.42.49 \
    "urllib3<2.0" \
    psycopg2-binary

WORKDIR /app
COPY test_msg.py run.py

CMD ["python", "run.py"]
