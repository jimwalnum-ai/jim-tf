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
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= max(var.private_subnets_count, var.public_subnets_count)
    error_message = "availability_zones must be empty or contain at least max(private_subnets_count, public_subnets_count) entries."
  }
}

variable "flow_log_bucket" {
  type        = string
  description = "Flow log bucket arn"
}

variable "endpoint_access_role" {
  type        = string
  description = "Role arn for that can access endpoints"
}

variable "test" {
  type    = string
  default = false
}

variable "endpoint_list" {
  type        = list(string)
  description = "List of VPC endpoints to create, s3 endpoint is automatic (opt)"
  default     = ["ecr.api", "ecr.dkr", "logs", "ec2", "sts", "eks", "sqs", "ssm", "ssmmessages", "ec2messages"]
}

variable "endpoint_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for interface VPC endpoints (defaults to TGW subnets)."
  default     = []
}

variable "domain_name_servers" {
  type        = list(string)
  description = "Domain name servers for VPC (opt)"
  default     = []
}

variable "private_subnets_count" {
  type        = number
  description = "Number of private subnets (opt)"
  default     = 2
}

variable "public_subnets_count" {
  type        = number
  description = "Number of public subnets (opt)"
  default     = 0
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

variable "create_nat" {
  type        = bool
  description = "Create and attach NAT to private subnets (opt)"
  default     = false
}

variable "create_igw" {
  type        = bool
  description = "Create and attach IGW to publice subnets (opt)"
  default     = false
}

variable "transit_gateway" {
  type        = string
  description = "Transit gateway id (opt)"
  default     = ""
}

variable "create_tgw_routes" {
  type        = bool
  description = "Create TGW route tables and associations"
  default     = false
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

variable "tags" {
  type        = map(string)
  description = "Tags (opt)"
  default     = {}
}

variable "tgw_subnet_tags" {
  type        = map(string)
  description = "Additional tags for TGW subnets (opt)"
  default     = {}
}



