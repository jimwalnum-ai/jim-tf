resource "aws_route53_zone" "crimsonscallion_public" {
  name    = "crimsonscallion.com"
  comment = "R53 Terraform"

  tags = local.tags
}

module "private_hosted_zone" {
  source      = "../modules/route53"
  domain      = "crimsonscallion.com"
  description = "R53 Terraform"
  vpc_id      = module.vpc["dev"].vpc_id
  vpc_region  = "us-east-1"

  tags = {
    environment = "development"
  }

  depends_on = [module.vpc["dev"]]
}

resource "aws_route53_record" "git" {
  count   = var.enable_gitlab ? 1 : 0
  zone_id = module.private_hosted_zone.zone_id
  name    = "git.crimsonscallion.com"
  type    = "A"
  ttl     = 300
  records = [aws_instance.gitlab[0].private_ip]
}

resource "aws_route53_record" "ldap" {
  count   = var.enable_ldap ? 1 : 0
  zone_id = module.private_hosted_zone.zone_id
  name    = "ldap.crimsonscallion.com"
  type    = "A"
  ttl     = 300
  records = [aws_instance.ec2_public_instance_1[0].private_ip]
}


