locals {
  env_name = "vpc-${var.name}-${var.env}-cs"
  flow_log_bucket_name = "vpc-${var.name}-${var.env}-flow-logs"
  tag_name = lookup(aws_vpc.vpc.tags, "Name")
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  ipv4_ipam_pool_id   = var.ipv4_ipam_pool_id
  ipv4_netmask_length = var.ipv4_netmask_length
  enable_dns_hostnames = true
  tags = merge(var.tags, {"Name":"${local.env_name}-vpc"})
}

resource "aws_subnet" "inspection_vpc_firewall_subnet" {
  count                   = 2
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 4, count.index)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  tags = "${merge(var.tags,{Name="${local.env_name}-firewall-subnet-${data.aws_availability_zones.available.names[count.index]}",scope="private"})}"
}

resource "aws_subnet" "inspection_vpc_public_subnet" {
  count                   = 2
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 4, 2 + count.index)
  depends_on              = [aws_internet_gateway.inspection_vpc_igw]
  tags = "${merge(var.tags,{Name="${local.env_name}-public-subnet-${data.aws_availability_zones.available.names[count.index]}",scope="public"})}"

}
resource "aws_subnet" "inspection_vpc_tgw_subnet" {
  count                   = 2
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 4, 4 + count.index)
  tags = "${merge(var.tags,{Name="${local.env_name}-tgw-subnet-${data.aws_availability_zones.available.names[count.index]}",scope="private"})}"
}

resource "aws_internet_gateway" "inspection_vpc_igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "inspection-vpc/internet-gateway"
  }
}
resource "aws_eip" "inspection_vpc_nat_gw_eip" {
  count = 2
}

resource "aws_nat_gateway" "inspection_vpc_nat_gw" {
  count         = 2
  depends_on    = [aws_internet_gateway.inspection_vpc_igw, aws_subnet.inspection_vpc_public_subnet]
  allocation_id = aws_eip.inspection_vpc_nat_gw_eip[count.index].id
  subnet_id     = aws_subnet.inspection_vpc_public_subnet[count.index].id
  tags = {
    Name = "inspection-vpc/${data.aws_availability_zones.available.names[count.index]}/nat-gateway"
  }
}

resource "aws_route_table" "inspection_vpc_firewall_subnet_route_table" {
  count  = 2
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block         = var.super_cidr_block
    transit_gateway_id = var.transit_gateway
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.inspection_vpc_nat_gw[count.index].id
  }
  tags = {
    Name = "inspection-vpc/${data.aws_availability_zones.available.names[count.index]}/firewall-subnet-route-table"
  }
}

resource "aws_route_table_association" "inspection_vpc_firewall_subnet_route_table_association" {
  count          = 2
  route_table_id = aws_route_table.inspection_vpc_firewall_subnet_route_table[count.index].id
  subnet_id      = aws_subnet.inspection_vpc_firewall_subnet[count.index].id
}



