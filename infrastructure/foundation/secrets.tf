resource "aws_secretsmanager_secret" "ssh_public_key" {
  name                    = "cs/ec2/ssh-public-key"
  description             = "SSH public key for ec2-user on EC2 instances"
  recovery_window_in_days = 0
  tags                    = local.tags
}

output "ssh_public_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the EC2 SSH public key."
  value       = aws_secretsmanager_secret.ssh_public_key.arn
}
