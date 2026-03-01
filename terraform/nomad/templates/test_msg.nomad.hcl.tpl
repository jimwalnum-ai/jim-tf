job "factor-test-msg" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "batch"

  periodic {
    crons            = ["*/2 * * * *"]
    prohibit_overlap = true
  }

  group "test-msg" {
    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    task "test-msg" {
      driver = "docker"

      config {
        image   = "${docker_image}"
        command = "/bin/sh"
        args    = ["-c", "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 'urllib3<2.0' && python /local/test_msg.py"]
      }

      template {
        destination = "local/test_msg.py"
        data        = <<PYEOF
${test_msg_py}
PYEOF
      }

      env {
        AWS_DEFAULT_REGION = "us-east-1"
        FACTOR_QUEUE_NAME  = "${factor_queue_name}"
      }

      resources {
        cpu    = 256
        memory = 512
      }
    }
  }
}
