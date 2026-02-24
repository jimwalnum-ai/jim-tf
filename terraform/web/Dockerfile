FROM python:3.11-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends gcc libpq-dev \
  && rm -rf /var/lib/apt/lists/*

COPY server.py /app/server.py
COPY index.html /app/index.html

RUN pip install --no-cache-dir psycopg2-binary

ENV PORT=8000
EXPOSE 8000

CMD ["python", "/app/server.py"]
