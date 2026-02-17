data "aws_vpc" "dev-vpc" {
  filter {
    name   = "tag:Name"
    values = ["vpc-cs-basics-dev"]
  }
}

data "aws_subnets" "private_selected" {
  filter {
    name   = "tag:scope"
    values = ["private"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev-vpc.id]
  }
}

resource "random_password" "master_password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "cs_rds_credentials" {
  name = "cs-factor-credentials"
}

resource "aws_secretsmanager_secret_version" "cs_rds_credentials" {
  secret_id     = aws_secretsmanager_secret.cs_rds_credentials.id
  secret_string = <<EOF
{
  "username": "${aws_db_instance.factor.username}",
  "password": "${random_password.master_password.result}",
  "engine": "postgres",
  "host": "${aws_db_instance.factor.endpoint}",
  "port": "${aws_db_instance.factor.port}"
}
EOF
}

resource "aws_security_group" "vpc_only" {
  name        = "vpc_only"
  description = "Allow only VPC"
  vpc_id      = data.aws_vpc.dev-vpc.id

  ingress {
    description = "From VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.dev-vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.dev-vpc.cidr_block]
  }
  tags = {
    Name = "RDS Sec Group"
  }
}

resource "aws_db_subnet_group" "factor" {
  name       = "factor"
  subnet_ids = data.aws_subnets.private_selected.ids
  tags       = local.tags
}

resource "aws_db_instance" "factor" {
  identifier             = "factor"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "17.2"
  username               = "fadmin"
  password               = random_password.master_password.result
  db_subnet_group_name   = aws_db_subnet_group.factor.name
  vpc_security_group_ids = [aws_security_group.vpc_only.id]
  parameter_group_name   = aws_db_parameter_group.factor.name
  publicly_accessible    = false
  skip_final_snapshot    = true
}

resource "aws_db_parameter_group" "factor" {
  name   = "factor"
  family = "postgres17"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}
