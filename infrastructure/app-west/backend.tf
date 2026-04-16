terraform {
  backend "s3" {
    encrypt      = true
    key          = "app-west/state.tfstate"
    bucket       = "csx5-use1-terraform-state"
    use_lockfile = true
    region       = "us-east-1"
  }
}
