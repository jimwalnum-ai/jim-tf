output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "tgw_subnets" {
  value = aws_subnet.inspection_vpc_tgw_subnet
}

output "public_subnets" {
  value = aws_subnet.inspection_vpc_public_subnet
}

output "firewall_subnets" {
  value = aws_subnet.inspection_vpc_firewall_subnet
}

output "nat_gateways" {
  value = aws_nat_gateway.inspection_vpc_nat_gw
}

output "igw_id" {
  value = aws_internet_gateway.inspection_vpc_igw.id
}

output "vpc_cidr" {
  value = aws_vpc.vpc.cidr_block
}