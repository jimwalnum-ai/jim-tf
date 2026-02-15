terraform {
  backend "s3" {
    encrypt = true
    key = "2_the_next_basics/state.tfstate"
    bucket = "cs-use1-terraform-state"
    workspace_key_prefix = "infra"
    dynamodb_table = "terraform-lock-dynamo"
    region = "us-east-1"
    role_arn =  "arn:aws:iam::274812015548:role/cs-terraform-role"
    session_name = "terraform"
  }
}

