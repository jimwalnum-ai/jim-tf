variable "env" {
  type = string
  description = "Env"
}

variable "tags" {
  type = map(string)
  description = "Tags"
  default = {}
}