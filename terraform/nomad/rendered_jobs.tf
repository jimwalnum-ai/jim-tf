resource "local_file" "autoscaler_job" {
  filename = "${path.module}/jobs/autoscaler.nomad.hcl"
  content = templatefile("${path.module}/templates/autoscaler.nomad.hcl.tpl", {
    autoscaler_version = var.nomad_autoscaler_version
    region             = "us-east-1"
    asg_name           = aws_autoscaling_group.clients.name
    client_min_count   = var.client_min_count
    client_max_count   = var.client_max_count
  })
}

resource "local_file" "sqs_scaler_job" {
  filename = "${path.module}/jobs/sqs_scaler.nomad.hcl"
  content = templatefile("${path.module}/templates/sqs_scaler.nomad.hcl.tpl", {
    docker_image             = var.docker_tasks_image
    factor_queue_name        = var.factor_queue_name
    factor_result_queue_name = var.factor_result_queue_name
    process_min_count        = var.process_min_count
    process_max_count        = var.process_max_count
    persist_min_count        = var.persist_min_count
    persist_max_count        = var.persist_max_count
    msgs_per_instance        = var.msgs_per_instance
  })
}

resource "local_file" "process_job" {
  filename = "${path.module}/jobs/process.nomad.hcl"
  content = templatefile("${path.module}/templates/process.nomad.hcl.tpl", {
    docker_image             = var.docker_tasks_image
    factor_queue_name        = var.factor_queue_name
    factor_result_queue_name = var.factor_result_queue_name
    process_min_count        = var.process_min_count
  })
}

resource "local_file" "persist_job" {
  filename = "${path.module}/jobs/persist.nomad.hcl"
  content = templatefile("${path.module}/templates/persist.nomad.hcl.tpl", {
    docker_image             = var.docker_tasks_image
    factor_result_queue_name = var.factor_result_queue_name
    rds_secret_name          = var.rds_secret_name
    persist_min_count        = var.persist_min_count
  })
}
