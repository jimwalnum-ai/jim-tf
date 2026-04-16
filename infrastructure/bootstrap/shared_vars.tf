data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

variable "enable_ecs" {
  description = "Set to false to disable all ECS factor resources."
  type        = bool
  default     = true
}

variable "enable_ldap" {
  description = "Create the LDAP EC2 instance and spin up the OpenLDAP container."
  type        = bool
  default     = false
}

variable "enable_gitlab" {
  description = "Create the GitLab EC2 instance, ALB, and associated resources."
  type        = bool
  default     = false
}

variable "enable_eks" {
  description = "Set to false to destroy all EKS cluster resources (cluster, node groups, add-ons, Helm releases, Kubernetes manifests, and supporting IAM/KMS)."
  type        = bool
  default     = false
}

variable "enable_nomad" {
  description = "Deploy the Nomad/Consul cluster (servers, clients, ALB, IAM, jobs). Set to false to destroy all Nomad resources."
  type        = bool
  default     = false
}

variable "enable_private_ec2" {
  description = "Create the always-on private EC2 instance in the foundation workspace."
  type        = bool
  default     = false
}

locals {
  state_bucket_name  = "${local.prefix}-use1-terraform-state"
  prefix             = "csx3"
  enable_ecs         = var.enable_ecs
  enable_eks         = var.enable_eks
  enable_ecs_web     = var.enable_ecs && !var.enable_eks
  enable_nomad       = var.enable_nomad
  enable_private_ec2 = var.enable_private_ec2
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
  acct_name         = element(local.ws, length(local.ws) - 2)
  acct_id           = data.aws_caller_identity.current.account_id
  tags              = local.all_tags
}

resource "time_static" "date" {}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
