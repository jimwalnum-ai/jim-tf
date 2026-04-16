################################################################################
# Remote state: pull the primary RDS connection info from us-east-1
################################################################################

data "terraform_remote_state" "app_east" {
  backend = "s3"
  config = {
    bucket = "csx4-use1-terraform-state"
    key    = "app/state.tfstate"
    region = "us-east-1"
  }
}

################################################################################
# VPC lookup
################################################################################

data "aws_vpc" "dev-vpc-west" {
  filter {
    name   = "tag:Name"
    values = ["vpc-cs-basics-dev-west"]
  }
}

data "aws_subnets" "private_selected" {
  filter {
    name   = "tag:scope"
    values = ["private"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev-vpc-west.id]
  }
}

################################################################################
# Store primary RDS connection info in Secrets Manager (us-west-2)
################################################################################

resource "aws_secretsmanager_secret" "cs_rds_credentials_west" {
  name = "cs-factor-credentials-west"
}

resource "aws_secretsmanager_secret_version" "cs_rds_credentials_west" {
  secret_id = aws_secretsmanager_secret.cs_rds_credentials_west.id
  secret_string = jsonencode({
    username = data.terraform_remote_state.app_east.outputs.rds_username
    password = data.terraform_remote_state.app_east.outputs.rds_password
    engine   = "postgres"
    host     = data.terraform_remote_state.app_east.outputs.rds_host
    port     = tostring(data.terraform_remote_state.app_east.outputs.rds_port)
  })
}
