resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Transit Gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags                            = merge(var.tags, { "Name" : "tgw-${var.env}" })
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



