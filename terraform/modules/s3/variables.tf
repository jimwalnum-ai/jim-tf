# Bucket names must be between 3 (min) and 63 (max) characters long.
# Bucket names can consist only of lowercase letters, numbers, dots (.), and hyphens (-).
# Bucket names must begin and end with a letter or number.

variable "bucket_name" {
   description = "Name for bucket"
   type = string 
}

variable "bucket_policy" {
   description = "Bucket policy"
   type = string
   default = ""
}

variable "kms_key" {
   description = "Kms key, will use AES256 if not defined (opt)"
   type = string
   default = ""
}

variable "versioning" {
   description = "Should bucket use versioning. (opt)"
   type = string
   default = "Suspended"
   validation {
    condition     = contains(["Disabled", "Enabled", "Suspended"], var.versioning)
    error_message = "Valid values for versioning  are (Disabled, Enabled, Suspended)."
  } 
}

variable "life_cycle_term"  {
   description = "Pick life cycle rule"
   type = string
   default = "long-term"
   validation {
    condition     = contains(["short-term", "medium-term", "long-term"], var.life_cycle_term)
    error_message = "Valid values for life_cycle_term are short-term, medium-term, long-term"
  } 
}

variable "tags" {
   description = "Tags for all bucket resources in this module (opt)"
   type = map(string)
   default = {}
}

variable "is_flow_log" {
  description = "Boolean to indicate if bucket is for a flow log (opt)"
  type = bool
  default = false
}

variable "logging_bucket" {
   description = "Name of s3 access log bucket (opt)"
   type = list
   default = []
}

variable "logging_perfix" {
   description = "Prefix for logs in bucket (opt)"
   type = string
   default = "/log"
}