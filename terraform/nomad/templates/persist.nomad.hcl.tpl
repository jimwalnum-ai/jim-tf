job "factor-persist" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "service"

  group "persist" {
    count = ${persist_min_count}

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "persist" {
      driver = "docker"

      config {
        image   = "${docker_image}"
        command = "/bin/sh"
        args    = ["-c", "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 'urllib3<2.0' psycopg2-binary && while true; do python /local/persist.py || true; sleep 30; done"]
      }

      template {
        destination = "local/persist.py"
        data        = <<PYEOF
${persist_py}
PYEOF
      }

      env {
        AWS_DEFAULT_REGION       = "us-east-1"
        FACTOR_RESULT_QUEUE_NAME = "${factor_result_queue_name}"
        RDS_SECRET_NAME          = "${rds_secret_name}"
      }

      resources {
        cpu    = 256
        memory = 512
      }

      service {
        name     = "factor-persist"
        provider = "consul"

        check {
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "pgrep -f persist.py"]
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
