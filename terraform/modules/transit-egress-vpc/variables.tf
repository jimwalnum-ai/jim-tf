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

variable "vpc_attach_cidrs" {
  type = list(string)
  description = "List of spoke vpc's cidr blocks"
}

variable "transit_gateway" {
  type = string
  description = "Transit gateway id" 
}

variable "firewall_endpoint" {
  type = string
  description = "Firewall endpintsync states"
  default = ""
}

variable "flow_log_bucket" {
  type = string
  description = "Flow log bucket"
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

variable "domain_name_servers" {
  type = list(string) 
  description = "Domain name servers for VPC (opt)"
  default = []
}

# Default to 2 for HA NAT
variable "private_subnets_count" {
  type = number
  description = "Number of private subnets (opt)"
  default = 2
}
# Default to 2 for HA IGW
variable "public_subnets_count" {
  type = number
  description = "Number of public subnets (opt)"
  default = 2
}

variable "tags" {
  type = map(string)
  description = "Tags (opt)"
  default = {}
}



