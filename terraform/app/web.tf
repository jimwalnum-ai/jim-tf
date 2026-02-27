locals {
  web_src_dir = "${path.module}/../web"
  web_src_hash = sha256(join("", [
    filesha256("${local.web_src_dir}/Dockerfile"),
    filesha256("${local.web_src_dir}/server.py"),
    filesha256("${local.web_src_dir}/index.html"),
  ]))
}

resource "terraform_data" "flask_app_image" {
  triggers_replace = [local.web_src_hash]

  provisioner "local-exec" {
    working_dir = local.web_src_dir
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      aws ecr get-login-password --region ${data.aws_region.current.id} \
        | docker login --username AWS --password-stdin ${aws_ecr_repository.flask_app.repository_url}
      docker build -t ${aws_ecr_repository.flask_app.repository_url}:latest .
      docker push ${aws_ecr_repository.flask_app.repository_url}:latest
    EOT
  }
}
