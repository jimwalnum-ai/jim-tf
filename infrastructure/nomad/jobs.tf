# ── Wait for Nomad to be reachable via ALB ──────────────────────────
resource "terraform_data" "wait_for_nomad" {
  count = local.enabled

  depends_on = [
    aws_instance.server,
    aws_autoscaling_group.clients,
    aws_lb_target_group_attachment.nomad,
    aws_lb_listener.nomad,
  ]

  triggers_replace = aws_lb.nomad[0].dns_name

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Nomad at ${aws_lb.nomad[0].dns_name}:4646 ..."
      for i in $(seq 1 60); do
        if curl -sf "http://${aws_lb.nomad[0].dns_name}:4646/v1/agent/health" >/dev/null 2>&1; then
          echo "Nomad is healthy (attempt $i)"
          exit 0
        fi
        echo "  attempt $i/60 – not ready yet, retrying in 10s"
        sleep 10
      done
      echo "ERROR: timed out after 10 minutes waiting for Nomad"
      exit 1
    EOT
  }
}

# ── Submit jobs via CLI ─────────────────────────────────────────────

resource "terraform_data" "job_autoscaler" {
  count            = local.enabled
  triggers_replace = local_file.autoscaler_job[0].content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${local_file.autoscaler_job[0].filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_factor_process" {
  count            = local.enabled
  triggers_replace = local_file.process_job[0].content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${local_file.process_job[0].filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_factor_persist" {
  count            = local.enabled
  triggers_replace = local_file.persist_job[0].content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${local_file.persist_job[0].filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_sqs_scaler" {
  count            = local.enabled
  triggers_replace = local_file.sqs_scaler_job[0].content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${local_file.sqs_scaler_job[0].filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_factor_test_msg" {
  count            = local.enabled
  triggers_replace = local_file.test_msg_job[0].content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${local_file.test_msg_job[0].filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}

# ── TypeScript jobs ──────────────────────────────────────────────────

resource "terraform_data" "job_factor_process_ts" {
  count            = local.enabled
  triggers_replace = filemd5("${path.module}/jobs/process_ts.nomad.hcl")

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${path.module}/jobs/process_ts.nomad.hcl"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_factor_persist_ts" {
  count            = local.enabled
  triggers_replace = filemd5("${path.module}/jobs/persist_ts.nomad.hcl")

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${path.module}/jobs/persist_ts.nomad.hcl"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_factor_test_msg_ts" {
  count            = local.enabled
  triggers_replace = filemd5("${path.module}/jobs/test_msg_ts.nomad.hcl")

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run -detach ${path.module}/jobs/test_msg_ts.nomad.hcl"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad[0].dns_name}:4646"
    }
  }
}
