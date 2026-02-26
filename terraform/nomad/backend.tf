terraform {
  backend "s3" {
    encrypt      = true
    key          = "nomad/state.tfstate"
    bucket       = "csx8-use1-terraform-state"
    use_lockfile = true
    region       = "us-east-1"
  }
}
