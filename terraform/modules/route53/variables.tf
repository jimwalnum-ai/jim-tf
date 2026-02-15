variable "domain" {
  type        = string
  description = "The domain name of the hosted zone"
}

variable "description" {
  type        = string
  default     = null
  description = "The description for the hosted zone. Defaults to 'Managed by Terraform'"
}

variable "vpc_id" {
  type        = string
  description = "vpc"
}

variable "vpc_region" {
  type        = string
  description = "region"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A map of tags to assign to the zone"
}