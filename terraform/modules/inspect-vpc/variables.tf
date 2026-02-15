variable "name" {
  type = string
  description = "Name for the VPC"
}

variable "env" {
  type = string
  description = "Evironment (dev,uat,prod)"
}

variable "region" {
  type = string
  description = "VPC Region"
}

variable "flow_log_bucket" {
  type = string
  description = "Flow log bucket arn"
}

variable "transit_gateway" {
  type = string
  description = "Transit gateway id (opt)"
  default = ""
}

variable super_cidr_block {
  type = string
}

variable "ipv4_ipam_pool_id" {
  type = string
  description = "IPAM Pool Id"
}

variable "ipv4_netmask_length" {
  type = number
  description = "Netmask for PVC"
  default = 24
}

variable "tags" {
  type = map(string)
  description = "Tags (opt)"
  default = {}
}



