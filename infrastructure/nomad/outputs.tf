output "server_public_ips" {
  value       = aws_instance.server[*].public_ip
  description = "Public IPs of the Nomad/Consul servers."
}

output "server_private_ips" {
  value       = aws_instance.server[*].private_ip
  description = "Private IPs of the Nomad/Consul servers."
}

output "nomad_ui_url" {
  value       = "http://${aws_lb.nomad.dns_name}:4646"
  description = "Nomad UI URL (via ALB)."
}

output "consul_ui_url" {
  value       = "http://${aws_lb.nomad.dns_name}:8500"
  description = "Consul UI URL (via ALB)."
}

output "alb_dns_name" {
  value       = aws_lb.nomad.dns_name
  description = "DNS name of the Nomad/Consul ALB."
}

output "ssh_commands_server" {
  value       = [for ip in aws_instance.server[*].public_ip : "ssh ec2-user@${ip}"]
  description = "SSH commands to reach each server node."
}

output "client_asg_name" {
  value       = aws_autoscaling_group.clients.name
  description = "Name of the Nomad client ASG."
}
