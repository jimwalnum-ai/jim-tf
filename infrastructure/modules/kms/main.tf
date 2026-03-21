locals {
  access_roles = concat(var.write_roles)
}

data "aws_region" "current" {}

resource "aws_kms_key" "kms_key" {
  description             = var.key_name
  deletion_window_in_days = 7
  policy                  = data.template_file.kms_key_policy.rendered
  depends_on              = [data.template_file.kms_key_policy]
}

resource "aws_kms_alias" "kms_key_alias" {
  name          = "alias/${var.key_name}"
  target_key_id = aws_kms_key.kms_key.key_id
}

data "template_file" "kms_key_policy" {
  template = file("${path.module}/templates/kms_key_policy.json.tpl")
  vars = {
    write_resources                      = "${jsonencode(local.access_roles)}"
    allowed_resources                    = "${jsonencode(concat(var.readonly_roles, local.access_roles))}"
    region                               = data.aws_region.current.id
    autoscaling_service_role_arn_pattern = jsonencode(var.autoscaling_service_role_arn_pattern)
    eks_node_role_arn_pattern            = jsonencode(var.eks_node_role_arn_pattern)
  }
}



