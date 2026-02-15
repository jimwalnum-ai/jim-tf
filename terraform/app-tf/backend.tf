terraform {
  backend "s3" {
    encrypt = true
    key = "3_the_app/state.tfstate"
    bucket = "cs-use1-terraform-state"
    dynamodb_table = "terraform-lock-dynamo"
    region = "us-east-1"
    role_arn =   "arn:aws:iam::419277227138:role/cs-terraform-role"
    session_name = "terraform"
  }
}

