terraform {
  backend "s3" {
    encrypt              = true
    key                  = "basics/state.tfstate"
    bucket               = "csx7-use1-terraform-state"
    workspace_key_prefix = "basics"
    use_lockfile         = true
    region               = "us-east-1"
  }
}

