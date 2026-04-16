terraform {
  backend "s3" {
    encrypt      = true
    key          = "ecs-mt/state.tfstate"
    bucket       = "csx4-use1-terraform-state"
    use_lockfile = true
    region       = "us-east-1"
  }
}
