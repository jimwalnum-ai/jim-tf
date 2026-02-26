mock_provider "aws" {}

override_resource {
  target = aws_vpc.vpc
  values = {
    cidr_block = "10.0.4.0/22"
    tags       = { "Name" = "test-spoke-vpc", "Spoke" = "true", "env" = "test" }
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

run "tgw_route_table_created_when_enabled" {
  command = plan

  variables {
    name                 = "test"
    env                  = "test"
    region               = "us-east-1"
    flow_log_bucket      = "arn:aws:s3:::test-bucket"
    transit_gateway      = "tgw-test123"
    create_tgw_routes    = true
    ipv4_ipam_pool_id    = "ipam-pool-test123"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    endpoint_access_role = "arn:aws:iam::123456789012:role/test-role"
  }

  assert {
    condition     = length(aws_route_table.tgw_subnets) == 1
    error_message = "Should create exactly 1 TGW route table when create_tgw_routes is true"
  }

  assert {
    condition     = length(aws_route_table_association.tgw_subnets) == 2
    error_message = "TGW route table should be associated with all TGW subnets (2)"
  }

  assert {
    condition     = length(aws_subnet.tgw_subnets) == 2
    error_message = "Should create 2 TGW subnets"
  }

  assert {
    condition     = length(aws_subnet.protected_subnets) == 2
    error_message = "Should create 2 protected subnets"
  }
}

run "no_tgw_routes_when_disabled" {
  command = plan

  variables {
    name                 = "test"
    env                  = "test"
    region               = "us-east-1"
    flow_log_bucket      = "arn:aws:s3:::test-bucket"
    transit_gateway      = ""
    create_tgw_routes    = false
    ipv4_ipam_pool_id    = "ipam-pool-test123"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    endpoint_access_role = "arn:aws:iam::123456789012:role/test-role"
  }

  assert {
    condition     = length(aws_route_table.tgw_subnets) == 0
    error_message = "Should not create TGW route table when create_tgw_routes is false"
  }

  assert {
    condition     = length(aws_route_table_association.tgw_subnets) == 0
    error_message = "Should not associate TGW route table when create_tgw_routes is false"
  }
}
