locals {
  web_src_dir  = "${path.module}/../web"
  web_src_hash = sha256(join("", [
    filesha256("${local.web_src_dir}/Dockerfile"),
    filesha256("${local.web_src_dir}/server.py"),
    filesha256("${local.web_src_dir}/index.html"),
  ]))
}

variable "web_db_name" {
  type        = string
  description = "Database name for the web service."
  default     = "factors"
}
