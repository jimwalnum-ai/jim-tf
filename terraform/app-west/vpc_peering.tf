################################################################################
# Data sources — east VPC, route tables, and RDS security group
################################################################################

data "aws_vpc" "dev-vpc-east" {
  provider = aws.east

  filter {
    name   = "tag:Name"
    values = ["vpc-cs-basics-dev"]
  }
}

data "aws_subnets" "east_private" {
  provider = aws.east

  filter {
    name   = "tag:scope"
    values = ["private"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev-vpc-east.id]
  }
}

data "aws_route_tables" "east_private" {
  provider = aws.east

  filter {
    name   = "association.subnet-id"
    values = data.aws_subnets.east_private.ids
  }
}

data "aws_route_tables" "west_private" {
  filter {
    name   = "association.subnet-id"
    values = data.aws_subnets.private_selected.ids
  }
}

data "aws_security_group" "east_rds" {
  provider = aws.east

  name   = "vpc_only"
  vpc_id = data.aws_vpc.dev-vpc-east.id
}

################################################################################
# VPC Peering — us-west-2 ↔ us-east-1
################################################################################

resource "aws_vpc_peering_connection" "west_to_east" {
  vpc_id      = data.aws_vpc.dev-vpc-west.id
  peer_vpc_id = data.aws_vpc.dev-vpc-east.id
  peer_region = "us-east-1"

  tags = merge(local.tags, {
    Name = "west-to-east-peering"
  })
}

resource "aws_vpc_peering_connection_accepter" "east_accept" {
  provider                  = aws.east
  vpc_peering_connection_id = aws_vpc_peering_connection.west_to_east.id
  auto_accept               = true

  tags = merge(local.tags, {
    Name = "west-to-east-peering"
  })
}

################################################################################
# Routes — west private subnets → east VPC CIDR via peering
################################################################################

resource "aws_route" "west_to_east" {
  for_each = toset(data.aws_route_tables.west_private.ids)

  route_table_id            = each.value
  destination_cidr_block    = data.aws_vpc.dev-vpc-east.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.west_to_east.id
}

################################################################################
# Routes — east private subnets → west VPC CIDR via peering
################################################################################

resource "aws_route" "east_to_west" {
  provider = aws.east
  for_each = toset(data.aws_route_tables.east_private.ids)

  route_table_id            = each.value
  destination_cidr_block    = data.aws_vpc.dev-vpc-west.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.west_to_east.id
}

################################################################################
# Security group rule — allow west VPC CIDR into east RDS on PostgreSQL port
################################################################################

resource "aws_vpc_security_group_ingress_rule" "east_rds_from_west" {
  provider = aws.east

  security_group_id = data.aws_security_group.east_rds.id
  description       = "PostgreSQL from west VPC via peering"
  cidr_ipv4         = data.aws_vpc.dev-vpc-west.cidr_block
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"

  tags = local.tags
}
