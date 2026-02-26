# Stress Test App

A lightweight Python app that generates CPU and memory load on demand via REST API. Designed for testing Kubernetes autoscaling (HPA, Cluster Autoscaler).

## API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/stress?cpu=80&memory=512&duration=120` | Start a stress test |
| `GET` | `/stress` | Check current stress status |
| `DELETE` | `/stress` | Stop the running stress test |
| `GET` | `/health` | Health check |
| `GET` | `/metrics` | Current resource utilization |

### Parameters

| Param | Type | Default | Range | Description |
|-------|------|---------|-------|-------------|
| `cpu` | int | 0 | 0-100 | Target CPU usage as a percentage |
| `memory` | int | 0 | >= 0 | Memory to allocate in MB |
| `duration` | int | 60 | 1-3600 | How long to run in seconds |

## Run Locally

```bash
pip install -r requirements.txt
python app.py
```

Then trigger a stress test:

```bash
# Spike CPU to ~80% and allocate 512MB for 2 minutes
curl -X POST "http://localhost:8080/stress?cpu=80&memory=512&duration=120"

# Check status
curl http://localhost:8080/stress

# View metrics
curl http://localhost:8080/metrics

# Stop early
curl -X DELETE http://localhost:8080/stress
```

## Docker

```bash
docker build -t stress-test .
docker run -p 8080:8080 stress-test
```

## Deploy to Kubernetes

1. Build and push the image to your container registry (e.g. ECR):

```bash
# Replace with your ECR URI
ECR_URI=123456789.dkr.ecr.us-east-1.amazonaws.com/stress-test

docker build -t $ECR_URI:latest .
docker push $ECR_URI:latest
```

2. Update `k8s/deployment.yaml` with your image URI, then apply:

```bash
kubectl apply -f k8s/
```

3. Port-forward to test:

```bash
kubectl port-forward svc/stress-test 8080:80
curl -X POST "http://localhost:8080/stress?cpu=80&memory=512&duration=120"
```

4. Watch the HPA react:

```bash
kubectl get hpa stress-test --watch
```

## How It Works

- **CPU**: Spawns worker processes proportional to the requested percentage. Each worker runs a tight math loop that pins a CPU core near 100%.
- **Memory**: Allocates a `bytearray` of the requested size and touches every page to ensure the OS actually commits the memory.
- **Duration**: A background timer automatically stops the test after the specified duration. You can also stop it early via `DELETE /stress`.
