variable "key_name" {
  type = string
  description = "Key Name (alias)"
}

variable "write_roles" {
  type = list
  description = "Write Roles"
}

variable "readonly_roles" {
  type = list
  description = "Read Roles"
}

variable "tags"  {
  type = map(string)
  description = "Tags for key (opt)"
  default = {}
}