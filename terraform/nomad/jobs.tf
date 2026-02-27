# ── Wait for Nomad to be reachable via ALB ──────────────────────────
resource "terraform_data" "wait_for_nomad" {
  depends_on = [
    aws_instance.server,
    aws_autoscaling_group.clients,
    aws_lb_target_group_attachment.nomad,
    aws_lb_listener.nomad,
  ]

  triggers_replace = aws_lb.nomad.dns_name

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Nomad at ${aws_lb.nomad.dns_name}:4646 ..."
      for i in $(seq 1 60); do
        if curl -sf "http://${aws_lb.nomad.dns_name}:4646/v1/agent/health" >/dev/null 2>&1; then
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
  triggers_replace = local_file.autoscaler_job.content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run ${local_file.autoscaler_job.filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad.dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_factor_process" {
  triggers_replace = local_file.process_job.content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run ${local_file.process_job.filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad.dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_factor_persist" {
  triggers_replace = local_file.persist_job.content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run ${local_file.persist_job.filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad.dns_name}:4646"
    }
  }
}

resource "terraform_data" "job_sqs_scaler" {
  triggers_replace = local_file.sqs_scaler_job.content

  depends_on = [terraform_data.wait_for_nomad]

  provisioner "local-exec" {
    command = "nomad job run ${local_file.sqs_scaler_job.filename}"
    environment = {
      NOMAD_ADDR = "http://${aws_lb.nomad.dns_name}:4646"
    }
  }
}
