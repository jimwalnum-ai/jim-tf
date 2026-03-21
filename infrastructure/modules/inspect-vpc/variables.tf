variable "name" {
  type        = string
  description = "Name for the VPC"
}

variable "env" {
  type        = string
  description = "Evironment (dev,uat,prod)"
}

variable "region" {
  type        = string
  description = "VPC Region"
}

variable "availability_zones" {
  type        = list(string)
  description = "Optional ordered list of AZs to use (defaults to available zones in provider region)"
  default     = []
  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "availability_zones must be empty or contain at least 2 entries."
  }
}

variable "flow_log_bucket" {
  type        = string
  description = "Flow log bucket arn"
}

variable "transit_gateway" {
  type        = string
  description = "Transit gateway id (opt)"
  default     = ""
}

variable "super_cidr_block" {
  type = string
}

variable "ipv4_ipam_pool_id" {
  type        = string
  description = "IPAM Pool Id"
}

variable "ipv4_netmask_length" {
  type        = number
  description = "Netmask for PVC"
  default     = 24
}

variable "tgw_subnet_cidr_offset" {
  type        = number
  description = "Index offset for TGW subnet CIDRs within the VPC CIDR"
  default     = 4
}

variable "public_ingress_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to access public subnets (SSH/HTTPS)"
  default     = []
}

variable "internal_ingress_cidrs" {
  type        = list(string)
  description = "Internal CIDRs allowed for east-west traffic"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags (opt)"
  default     = {}
}



