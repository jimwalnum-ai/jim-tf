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
      DOCKER_CFG=$(mktemp -d)
      trap 'rm -rf "$DOCKER_CFG"' EXIT
      TOKEN=$(aws ecr get-login-password --region ${data.aws_region.current.id})
      AUTH=$(printf 'AWS:%s' "$TOKEN" | base64)
      printf '{"auths":{"%s":{"auth":"%s"}}}' \
        "${aws_ecr_repository.flask_app.repository_url}" "$AUTH" \
        > "$DOCKER_CFG/config.json"
      docker --config "$DOCKER_CFG" buildx build --platform linux/arm64 \
        -t ${aws_ecr_repository.flask_app.repository_url}:latest \
        --push .
    EOT
  }
}
