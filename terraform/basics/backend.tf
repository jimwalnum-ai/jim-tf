terraform {
  backend "s3" {
    encrypt              = true
    key                  = "basics/state.tfstate"
    bucket               = "csz3-use1-terraform-state"
    workspace_key_prefix = "infra"
    use_lockfile         = true
    region               = "us-east-1"
  }
}

