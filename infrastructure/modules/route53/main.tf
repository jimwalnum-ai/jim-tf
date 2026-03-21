resource "aws_route53_zone" "this" {
  name    = var.domain
  comment = var.description

  vpc {
    vpc_id     = var.vpc_id
    vpc_region = var.vpc_region
  }

  tags = var.tags
}

