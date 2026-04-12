variable "ssh_public_key" {
  description = "SSH public key for ec2-user on EC2 instances. Set via TF_VAR_ssh_public_key for apply; leave empty for validate."
  type        = string
  sensitive   = true
  default     = ""
}

resource "aws_secretsmanager_secret" "ssh_public_key" {
  name                    = "cs/ec2/ssh-public-key"
  description             = "SSH public key for ec2-user on EC2 instances"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "ssh_public_key" {
  count         = var.ssh_public_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ssh_public_key.id
  secret_string = var.ssh_public_key

  lifecycle {
    # Allow the key to be rotated outside of Terraform without triggering a replace
    ignore_changes = [secret_string]
  }
}

output "ssh_public_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the EC2 SSH public key."
  value       = aws_secretsmanager_secret.ssh_public_key.arn
}
