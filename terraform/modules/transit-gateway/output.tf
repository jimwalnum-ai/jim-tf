output "id" {
   value = aws_ec2_transit_gateway.tgw.id
}

output "vpc_route_table" {
   value = aws_ec2_transit_gateway_route_table.vpc_route_table
}

output "inspection_route_table" {
   value = aws_ec2_transit_gateway_route_table.inspection_route_table
}