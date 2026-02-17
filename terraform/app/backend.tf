terraform {
  backend "s3" {
    encrypt      = true
    key          = "app/state.tfstate"
    bucket       = "csz3-use1-terraform-state"
    use_lockfile = true
    region       = "us-east-1"
  }
}

