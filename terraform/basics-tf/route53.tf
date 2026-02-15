module "private_hosted_zone" {
  source      = "../modules/route53"
  domain      = "crimsonscallion.com"
  description = "R53 Terraform"
  vpc_id = module.vpc-dev.vpc_id
  vpc_region = "us-east-1"
  
  tags = {
    environment = "development"
  }
}

resource "aws_route53_record" "git" {
  zone_id = module.private_hosted_zone.zone_id
  name    = "git.crimsonscallion.com"
  type    = "A"
  ttl     = 300
  records = [aws_instance.ec2_public_instance_2.private_ip]
}

resource "aws_route53_record" "ldap" {
  zone_id = module.private_hosted_zone.zone_id
  name    = "ldap.crimsonscallion.com"
  type    = "A"
  ttl     = 300
  records = [aws_instance.ec2_public_instance_1.private_ip]
}


