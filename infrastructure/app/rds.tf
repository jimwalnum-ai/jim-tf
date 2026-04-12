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
  name                    = "cs-factor-credentials"
  recovery_window_in_days = 0
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
  identifier              = "factor"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  max_allocated_storage   = 100
  engine                  = "postgres"
  engine_version          = "17.2"
  db_name                 = var.web_db_name
  username                = "fadmin"
  password                = random_password.master_password.result
  db_subnet_group_name    = aws_db_subnet_group.factor.name
  vpc_security_group_ids  = [aws_security_group.vpc_only.id]
  parameter_group_name    = aws_db_parameter_group.factor.name
  publicly_accessible     = false
  storage_encrypted       = true
  deletion_protection     = true
  skip_final_snapshot     = true
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"
}

resource "aws_db_parameter_group" "factor" {
  name   = "factor"
  family = "postgres17"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

################################################################################
# Outputs for cross-region references (app-west, global)
################################################################################

output "rds_instance_arn" {
  value       = aws_db_instance.factor.arn
  description = "ARN of the primary RDS instance (used by cross-region read replica)"
}

output "rds_username" {
  value       = aws_db_instance.factor.username
  description = "Master username for the primary RDS instance"
}

output "rds_password" {
  value       = random_password.master_password.result
  sensitive   = true
  description = "Master password for the primary RDS instance"
}

output "rds_host" {
  value       = aws_db_instance.factor.address
  description = "Hostname of the primary RDS instance"
}

output "rds_port" {
  value       = aws_db_instance.factor.port
  description = "Port of the primary RDS instance"
}
