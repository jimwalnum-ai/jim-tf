data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  state_bucket_name = "${local.prefix}-use1-terraform-state"
  prefix            = "csz3"
  tagmap            = fileexists("./tags.csv") ? csvdecode(file("../tags.csv")) : {}
  dir_tags          = { for rg in local.tagmap : rg.tag => rg.value }
  top_tagmap        = csvdecode(file("../top_level_tags.csv"))
  top_tags          = { for rg in local.top_tagmap : rg.tag => rg.value }
  date_tag          = { "create_date" : formatdate("MM-DD-YYYY hh:mm:ssZ", time_static.date.rfc3339) }
  ws                = split("/", "${path.cwd}")
  app               = element(local.ws, length(local.ws) - 1)
  tf_src            = format("%s/%s", element(local.ws, length(local.ws) - 2), element(local.ws, length(local.ws) - 1))
  extra_tags        = { "application" : local.app, "source" : local.tf_src }
  all_tags          = merge(local.extra_tags, local.date_tag, local.top_tags, local.dir_tags)
  # Can define a specific local.tf in the directory to set application, other tags
  acct_name = element(local.ws, length(local.ws) - 2)
  acct_id   = data.aws_caller_identity.current.account_id
  tags      = local.all_tags
}

resource "time_static" "date" {}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "=5.6.2"
    }
    awscc = {
      source = "hashicorp/awscc"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}


