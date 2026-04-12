################################################################################
# Remote State References
################################################################################

data "terraform_remote_state" "basics" {
  backend = "s3"
  config = {
    bucket = "csx3-use1-terraform-state"
    key    = "basics/state.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "app_east" {
  backend = "s3"
  config = {
    bucket = "csx3-use1-terraform-state"
    key    = "app/state.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "app_west" {
  backend = "s3"
  config = {
    bucket = "csx3-use1-terraform-state"
    key    = "app-west/state.tfstate"
    region = "us-east-1"
  }
}

################################################################################
# Route 53 Health Checks
#
# Health checks are always created in us-east-1 (Route 53 requirement).
################################################################################

resource "aws_route53_health_check" "app_east" {
  fqdn              = data.terraform_remote_state.app_east.outputs.app_url
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "flask-app-east-health-check"
  }
}

resource "aws_route53_health_check" "app_west" {
  fqdn              = data.terraform_remote_state.app_west.outputs.app_url
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "flask-app-west-health-check"
  }
}

################################################################################
# Route 53 Latency-Based Routing (Hot-Hot)
#
# Sends users to the closest healthy region. If one region fails its health
# check, all traffic is automatically routed to the surviving region.
################################################################################

resource "aws_route53_record" "app_east" {
  zone_id = data.terraform_remote_state.basics.outputs.public_zone_id
  name    = "app.crimsonscallion.com"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "app-east"

  latency_routing_policy {
    region = "us-east-1"
  }

  health_check_id = aws_route53_health_check.app_east.id
  records         = [data.terraform_remote_state.app_east.outputs.app_url]
}

resource "aws_route53_record" "app_west" {
  zone_id = data.terraform_remote_state.basics.outputs.public_zone_id
  name    = "app.crimsonscallion.com"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "app-west"

  latency_routing_policy {
    region = "us-west-2"
  }

  health_check_id = aws_route53_health_check.app_west.id
  records         = [data.terraform_remote_state.app_west.outputs.app_url]
}

################################################################################
# Security Dashboard — Latency-Based Routing
################################################################################

resource "aws_route53_health_check" "dashboard_east" {
  fqdn              = data.terraform_remote_state.app_east.outputs.security_dashboard_url_hostname
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "security-dashboard-east-health-check"
  }
}

resource "aws_route53_health_check" "dashboard_west" {
  fqdn              = data.terraform_remote_state.app_west.outputs.security_dashboard_url_hostname
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "security-dashboard-west-health-check"
  }
}

resource "aws_route53_record" "dashboard_east" {
  zone_id = data.terraform_remote_state.basics.outputs.public_zone_id
  name    = "security.crimsonscallion.com"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "dashboard-east"

  latency_routing_policy {
    region = "us-east-1"
  }

  health_check_id = aws_route53_health_check.dashboard_east.id
  records         = [data.terraform_remote_state.app_east.outputs.security_dashboard_url_hostname]
}

resource "aws_route53_record" "dashboard_west" {
  zone_id = data.terraform_remote_state.basics.outputs.public_zone_id
  name    = "security.crimsonscallion.com"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "dashboard-west"

  latency_routing_policy {
    region = "us-west-2"
  }

  health_check_id = aws_route53_health_check.dashboard_west.id
  records         = [data.terraform_remote_state.app_west.outputs.security_dashboard_url_hostname]
}

################################################################################
# realhandsonlabs.net — Flask App Latency-Based Routing
################################################################################

data "aws_route53_zone" "lab" {
  name         = "${data.aws_caller_identity.current.account_id}.realhandsonlabs.net."
  private_zone = false
}

locals {
  lab_zone_id = data.aws_route53_zone.lab.zone_id
  lab_domain  = "${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
}

resource "aws_route53_record" "lab_app_east" {
  zone_id = local.lab_zone_id
  name    = "app.${local.lab_domain}"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "app-east"

  latency_routing_policy {
    region = "us-east-1"
  }

  health_check_id = aws_route53_health_check.app_east.id
  records         = [data.terraform_remote_state.app_east.outputs.app_url]
}

resource "aws_route53_record" "lab_app_west" {
  zone_id = local.lab_zone_id
  name    = "app.${local.lab_domain}"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "app-west"

  latency_routing_policy {
    region = "us-west-2"
  }

  health_check_id = aws_route53_health_check.app_west.id
  records         = [data.terraform_remote_state.app_west.outputs.app_url]
}

################################################################################
# realhandsonlabs.net — Security Dashboard Latency-Based Routing
################################################################################

resource "aws_route53_record" "lab_dashboard_east" {
  zone_id = local.lab_zone_id
  name    = "security.${local.lab_domain}"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "dashboard-east"

  latency_routing_policy {
    region = "us-east-1"
  }

  health_check_id = aws_route53_health_check.dashboard_east.id
  records         = [data.terraform_remote_state.app_east.outputs.security_dashboard_url_hostname]
}

resource "aws_route53_record" "lab_dashboard_west" {
  zone_id = local.lab_zone_id
  name    = "security.${local.lab_domain}"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "dashboard-west"

  latency_routing_policy {
    region = "us-west-2"
  }

  health_check_id = aws_route53_health_check.dashboard_west.id
  records         = [data.terraform_remote_state.app_west.outputs.security_dashboard_url_hostname]
}

################################################################################
# Outputs
################################################################################

output "app_fqdn" {
  value       = "app.crimsonscallion.com"
  description = "Global FQDN for the Flask app (latency-routed across both regions)"
}

output "security_dashboard_fqdn" {
  value       = "security.crimsonscallion.com"
  description = "Global FQDN for the security dashboard (latency-routed across both regions)"
}

output "lab_app_fqdn" {
  value       = "app.${local.lab_domain}"
  description = "Global FQDN for the Flask app via realhandsonlabs.net"
}

output "lab_security_dashboard_fqdn" {
  value       = "security.${local.lab_domain}"
  description = "Global FQDN for the security dashboard via realhandsonlabs.net"
}
