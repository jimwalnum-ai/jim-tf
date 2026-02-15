terraform {
  backend "s3" {
    encrypt              = true
    key                  = "basics/state.tfstate"
    bucket               = "csz1-use1-terraform-state"
    workspace_key_prefix = "infra"
    dynamodb_table       = "terraform-lock-dynamo"
    region               = "us-east-1"
  }
}

