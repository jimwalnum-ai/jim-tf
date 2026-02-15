
data "aws_subnet" "tgw"{
filter {
    name   = "tag:type"    
    values = ["tgw"]
  }
}


resource "aws_ec2_transit_gateway_route_table" "spoke_route_table" {
  transit_gateway_id = var.tgw_id
  tags = {
    Name = "cs-spoke-route-table"
  }
}

resource "aws_ec2_transit_gateway_route_table" "inspection_route_table" {
  transit_gateway_id = var.tgw_id
  tags = {
    Name = "cs-inspection-route-table"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke_tgw_attachment_rt_association" {
  count = length(var.spoke_subnets)
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke_tgw_attachment[count.index].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "inspection_vpc_tgw_attachment" {
  subnet_ids                                      = var.inspection_tgw_subnets
  transit_gateway_id                              = var.tgw_id
  vpc_id                                          = var.inspection_vpc_id
  transit_gateway_default_route_table_association = false
  appliance_mode_support                          = "enable"
  tags = {
    Name = "inspection-vpc-attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_tgw_attachment" {
  count = length(var.spoke_subnets)
  subnet_ids                                      = var.spoke_subnets
  transit_gateway_id                              = var.tgw_id
  vpc_id                                          = var.spoke_vpc_ids[count.index]
  transit_gateway_default_route_table_association = false
  tags = {
    Name = "spoke-each.value-attachment"
  }
}


resource "aws_ec2_transit_gateway_route" "spoke_route_table_default_route" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection_vpc_tgw_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table.id
  destination_cidr_block         = "0.0.0.0/0"

}

resource "aws_ec2_transit_gateway_route_table_association" "inspection_vpc_tgw_attachment_rt_association" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection_vpc_tgw_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection_route_table.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "inspection_route_table_propagate_spoke" {
  count = length(var.spoke_subnets)
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke_tgw_attachment[count.index].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection_route_table.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_route_table_propagate_inspection_vpc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection_vpc_tgw_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table.id
}