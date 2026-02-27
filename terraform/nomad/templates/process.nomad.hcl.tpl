job "factor-process" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "service"

  group "process" {
    count = ${process_min_count}

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "process" {
      driver = "docker"

      config {
        image   = "${docker_image}"
        command = "/bin/sh"
        args    = ["-c", "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 'urllib3<2.0' && while true; do python /local/process.py || true; sleep 30; done"]
      }

      template {
        destination = "local/process.py"
        data        = <<PYEOF
${process_py}
PYEOF
      }

      env {
        AWS_DEFAULT_REGION       = "us-east-1"
        FACTOR_QUEUE_NAME        = "${factor_queue_name}"
        FACTOR_RESULT_QUEUE_NAME = "${factor_result_queue_name}"
      }

      resources {
        cpu    = 256
        memory = 512
      }

      service {
        name     = "factor-process"
        provider = "consul"

        check {
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "pgrep -f process.py"]
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
