data "aws_region" "current" {}

data "aws_rds_engine_version" "aurora_postgresql" {
  engine             = "aurora-postgresql"
  preferred_versions = ["16.6", "16.4", "15.8", "15.6", "14.13"]
}

locals {
  cluster_id     = "${var.name}-${var.env}"
  engine_version = var.engine_version != "" ? var.engine_version : data.aws_rds_engine_version.aurora_postgresql.version
  major_version  = split(".", local.engine_version)[0]
}

resource "aws_db_subnet_group" "this" {
  name        = "${local.cluster_id}-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for Aurora cluster ${local.cluster_id}"
  tags        = merge(var.tags, { Name = "${local.cluster_id}-subnet-group" })
}

resource "aws_security_group" "aurora" {
  name        = "${local.cluster_id}-aurora-sg"
  description = "Security group for Aurora cluster ${local.cluster_id}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #trivy:ignore:AVD-AWS-0104
  }

  tags = merge(var.tags, { Name = "${local.cluster_id}-aurora-sg" })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${local.cluster_id}-cluster-pg"
  family      = "aurora-postgresql${local.major_version}"
  description = "Cluster parameter group for ${local.cluster_id}"
  tags        = merge(var.tags, { Name = "${local.cluster_id}-cluster-pg" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${local.cluster_id}-instance-pg"
  family      = "aurora-postgresql${local.major_version}"
  description = "Instance parameter group for ${local.cluster_id}"
  tags        = merge(var.tags, { Name = "${local.cluster_id}-instance-pg" })
}

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "aurora_master" {
  name                    = "${local.cluster_id}/aurora/master-credentials"
  description             = "Aurora master credentials for ${local.cluster_id}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
  tags                    = merge(var.tags, { Name = "${local.cluster_id}-aurora-secret" })
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  secret_id = aws_secretsmanager_secret.aurora_master.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "aurora-postgresql"
    host     = aws_rds_cluster.this.endpoint
    port     = 5432
    dbname   = var.database_name
  })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = local.cluster_id
  engine                          = "aurora-postgresql"
  engine_version                  = local.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = random_password.master.result
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = true
  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  apply_immediately               = var.apply_immediately

  tags = merge(var.tags, { Name = local.cluster_id })
}

resource "aws_rds_cluster_instance" "this" {
  count                      = var.instance_count
  identifier                 = "${local.cluster_id}-${count.index}"
  cluster_identifier         = aws_rds_cluster.this.id
  instance_class             = var.instance_class
  engine                     = aws_rds_cluster.this.engine
  engine_version             = aws_rds_cluster.this.engine_version
  db_subnet_group_name       = aws_db_subnet_group.this.name
  db_parameter_group_name    = aws_db_parameter_group.this.name
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  tags = merge(var.tags, { Name = "${local.cluster_id}-${count.index}" })
}
