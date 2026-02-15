output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "protected_subnets" {
  value = aws_subnet.protected_subnets.*.id
}

output "tgw_subnets" {
  value = aws_subnet.tgw_subnets.*.id
}

output "public_subnets" {
  value = aws_subnet.public_subnets.*.id
}

output "vpc_cidr" {
  value = aws_vpc.vpc.cidr_block
}

output "vpc_list" {
  value = [aws_vpc.vpc.id,aws_vpc.vpc.id,aws_vpc.vpc.id]
}