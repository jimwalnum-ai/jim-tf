variable "name" {
  type        = string
  description = "Name prefix for Aurora cluster resources"
}

variable "env" {
  type        = string
  description = "Environment name (e.g. dev, prd)"
}

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version. Leave empty to automatically use the latest available version."
  default     = ""
}

variable "instance_class" {
  type        = string
  description = "Aurora instance class"
  default     = "db.t3.medium"
}

variable "instance_count" {
  type        = number
  description = "Number of Aurora cluster instances"
  default     = 1
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DB subnet group"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the cluster will be deployed"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to connect to the cluster"
  default     = []
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to connect to the cluster"
  default     = []
}

variable "database_name" {
  type        = string
  description = "Name of the default database"
  default     = "appdb"
}

variable "master_username" {
  type        = string
  description = "Master DB username"
  default     = "dbadmin"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for storage encryption"
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection on the cluster"
  default     = false
}

variable "backup_retention_period" {
  type        = number
  description = "Days to retain automated backups"
  default     = 7
}

variable "preferred_backup_window" {
  type        = string
  description = "Daily time range for automated backups (UTC)"
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  type        = string
  description = "Weekly time range for maintenance (UTC)"
  default     = "sun:05:00-sun:06:00"
}

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately rather than during the next maintenance window"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}
