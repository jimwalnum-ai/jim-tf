data "aws_vpc" "dev" {
  filter {
    name   = "tag:Name"
    values = ["vpc-cs-basics-dev"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:scope"
    values = ["public"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev.id]
  }
}

resource "aws_security_group" "nomad_cluster" {
  name        = "${local.name_prefix}-cluster"
  description = "Nomad and Consul cluster traffic"
  vpc_id      = data.aws_vpc.dev.id

  # SSH from home
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.home_ip]
  }

  # Nomad HTTP API + UI
  ingress {
    description = "Nomad HTTP"
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = [local.home_ip]
  }

  # Consul UI
  ingress {
    description = "Consul HTTP"
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = [local.home_ip]
  }

  # All traffic within the security group (Nomad RPC/serf, Consul RPC/serf/DNS)
  ingress {
    description = "Intra-cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # VPC internal
  ingress {
    description = "VPC internal"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.dev.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-cluster" })
}
