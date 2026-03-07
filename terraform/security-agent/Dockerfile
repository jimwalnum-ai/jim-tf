FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY agent.py .

USER 65534:65534

ENTRYPOINT ["python", "-u", "agent.py"]
