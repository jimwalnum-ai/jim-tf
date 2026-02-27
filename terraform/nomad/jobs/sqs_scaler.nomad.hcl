job "sqs-scaler" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "batch"

  periodic {
    crons            = ["* * * * *"]
    prohibit_overlap = true
  }

  group "scaler" {
    count = 1

    restart {
      attempts = 2
      interval = "5m"
      delay    = "10s"
      mode     = "fail"
    }

    task "scale" {
      driver = "docker"

      config {
        image   = "python:3.11-slim"
        command = "/bin/sh"
        args    = ["-c", "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 'urllib3<2.0' && python /local/sqs_scaler.py"]
      }

      template {
        destination = "local/nomad.env"
        env         = true
        data        = <<ENVEOF
NOMAD_ADDR=http://{{ env "attr.unique.network.ip-address" }}:4646
ENVEOF
      }

      template {
        destination = "local/sqs_scaler.py"
        data        = <<PYEOF
import boto3, json, math, os, logging
from urllib.request import Request, urlopen
from urllib.error import URLError

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("sqs-scaler")

NOMAD_ADDR = os.getenv("NOMAD_ADDR", "http://localhost:4646")
REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")

SCALING_RULES = [
    {
        "queue": "SQS_FACTOR_DEV",
        "job": "factor-process",
        "group": "process",
        "min": 2,
        "max": 6,
        "msgs_per_instance": 100,
    },
    {
        "queue": "SQS_FACTOR_RESULT_DEV",
        "job": "factor-persist",
        "group": "persist",
        "min": 2,
        "max": 4,
        "msgs_per_instance": 100,
    },
]

sqs = boto3.client("sqs", region_name=REGION)

def get_queue_depth(queue_name):
    url = sqs.get_queue_url(QueueName=queue_name)["QueueUrl"]
    attrs = sqs.get_queue_attributes(
        QueueUrl=url,
        AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"],
    )["Attributes"]
    visible = int(attrs.get("ApproximateNumberOfMessages", 0))
    in_flight = int(attrs.get("ApproximateNumberOfMessagesNotVisible", 0))
    return visible + in_flight

def get_current_count(job, group):
    req = Request(f"{NOMAD_ADDR}/v1/job/{job}")
    try:
        with urlopen(req, timeout=10) as resp:
            spec = json.loads(resp.read())
        for tg in spec.get("TaskGroups", []):
            if tg["Name"] == group:
                return tg["Count"]
    except (URLError, KeyError) as exc:
        logger.warning("failed to read job %s: %s", job, exc)
    return None

def scale_job(job, group, count):
    payload = json.dumps({"Count": count, "Target": {"Group": group}}).encode()
    req = Request(f"{NOMAD_ADDR}/v1/job/{job}/scale", data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    with urlopen(req, timeout=10) as resp:
        return resp.status

for rule in SCALING_RULES:
    depth = get_queue_depth(rule["queue"])
    desired = min(rule["max"], max(rule["min"], math.ceil(depth / rule["msgs_per_instance"])))
    current = get_current_count(rule["job"], rule["group"])

    if current is None:
        logger.warning("job=%s group=%s not found, skipping", rule["job"], rule["group"])
        continue

    logger.info(
        "queue=%s depth=%d current=%d desired=%d",
        rule["queue"], depth, current, desired,
    )

    if desired != current:
        status = scale_job(rule["job"], rule["group"], desired)
        logger.info("scaled job=%s group=%s %d -> %d (http %s)", rule["job"], rule["group"], current, desired, status)
    else:
        logger.info("job=%s group=%s no change needed", rule["job"], rule["group"])
PYEOF
      }

      env {
        AWS_DEFAULT_REGION = "us-east-1"
      }

      resources {
        cpu    = 128
        memory = 256
      }
    }
  }
}
