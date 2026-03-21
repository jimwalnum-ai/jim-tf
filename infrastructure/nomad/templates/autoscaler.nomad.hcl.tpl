job "nomad-autoscaler" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "service"

  group "autoscaler" {
    count = 1

    network {
      port "http" {
        static = 8080
      }
    }

    task "autoscaler" {
      driver = "docker"

      config {
        image   = "hashicorp/nomad-autoscaler:${autoscaler_version}"
        command = "nomad-autoscaler"
        args = [
          "agent",
          "-config", "$${NOMAD_TASK_DIR}/config.hcl",
          "-policy-dir", "$${NOMAD_TASK_DIR}/policies/",
          "-http-bind-address", "0.0.0.0",
          "-http-bind-port", "8080",
        ]
        ports = ["http"]
      }

      template {
        destination = "$${NOMAD_TASK_DIR}/config.hcl"
        data        = <<CFGEOF
log_level = "INFO"

nomad {
  address = "http://{{ env "attr.unique.network.ip-address" }}:4646"
}

apm "nomad-apm" {
  driver = "nomad-apm"
}

target "aws-asg" {
  driver = "aws-asg"
  config = {
    aws_region = "${region}"
  }
}

strategy "target-value" {
  driver = "target-value"
}

policy_eval {
  workers = {
    cluster    = 2
    horizontal = 2
  }
}
CFGEOF
      }

      template {
        destination = "$${NOMAD_TASK_DIR}/policies/cluster.hcl"
        data        = <<CLUSTEREOF
scaling "cluster_policy" {
  enabled = true
  min     = ${client_min_count}
  max     = ${client_max_count}

  policy {
    cooldown            = "2m"
    evaluation_interval = "30s"

    check "cpu_allocated" {
      source = "nomad-apm"
      query  = "percentage-allocated_cpu"

      strategy "target-value" {
        target = 70
      }
    }

    check "mem_allocated" {
      source = "nomad-apm"
      query  = "percentage-allocated_memory"

      strategy "target-value" {
        target = 70
      }
    }

    target "aws-asg" {
      dry-run             = "false"
      aws_asg_name        = "${asg_name}"
      node_drain_deadline = "5m"
      node_class          = "auto"
    }
  }
}
CLUSTEREOF
      }

      resources {
        cpu    = 256
        memory = 256
      }

      service {
        name     = "nomad-autoscaler"
        port     = "http"
        provider = "consul"

        check {
          type     = "http"
          path     = "/v1/health"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}
