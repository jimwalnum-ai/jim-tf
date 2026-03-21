variable "tgw_id" {
  type = string
}

variable "inspection_tgw_subnets" {
  type = list(string)
}

variable "spoke_subnets" {
  type = list(string)
}

variable "spoke_vpc_ids" {
  type = list(string)
}

variable "inspection_vpc_id" {
  type = string
}

