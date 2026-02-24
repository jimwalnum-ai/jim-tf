resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Transit Gateway"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags                            = merge(var.tags, { "Name" : "tgw-${var.env}" })
}

resource "aws_flow_log" "tgw_flow_log" {
  log_destination          = "${var.flow_log_bucket}/tgw-flow-logs"
  log_destination_type     = "s3"
  max_aggregation_interval = 60
  traffic_type             = "ALL"
  transit_gateway_id       = aws_ec2_transit_gateway.tgw.id
  tags                     = var.tags
}

resource "aws_ec2_transit_gateway_route_table" "vpc_route_table" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    Name = "cs-tgw-vpc-route-table"
  }
}

resource "aws_ec2_transit_gateway_route_table" "inspection_route_table" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    Name = "cs-tgw-inspection-route-table"
  }
}



