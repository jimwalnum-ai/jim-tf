mock_provider "aws" {}

override_resource {
  target = aws_vpc.vpc
  values = {
    cidr_block = "10.0.0.0/22"
    tags       = { "Name" = "test-inspect-vpc" }
  }
}

run "inspect_vpc_creates_expected_subnets" {
  command = plan

  variables {
    name               = "test"
    env                = "test"
    region             = "us-east-1"
    flow_log_bucket    = "arn:aws:s3:::test-bucket"
    transit_gateway    = "tgw-test123"
    super_cidr_block   = "10.0.0.0/18"
    ipv4_ipam_pool_id  = "ipam-pool-test123"
    availability_zones = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = length(aws_subnet.inspection_vpc_tgw_subnet) == 2
    error_message = "Expected 2 TGW subnets in inspect VPC"
  }

  assert {
    condition     = length(aws_subnet.inspection_vpc_firewall_subnet) == 2
    error_message = "Expected 2 firewall subnets in inspect VPC"
  }

  assert {
    condition     = length(aws_subnet.inspection_vpc_public_subnet) == 2
    error_message = "Expected 2 public subnets in inspect VPC"
  }

  assert {
    condition     = length(aws_nat_gateway.inspection_vpc_nat_gw) == 2
    error_message = "Expected 2 NAT gateways for egress"
  }

}
