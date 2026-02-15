terraform {
  backend "s3" {
    encrypt        = true
    key            = "app/state.tfstate"
    bucket         = "csz1-use1-terraform-state"
    dynamodb_table = "terraform-lock-dynamo"
    region         = "us-east-1"
  }
}

