output "server_public_ip" {
  value       = aws_instance.server.public_ip
  description = "Public IP of the Nomad/Consul server."
}

output "server_private_ip" {
  value       = aws_instance.server.private_ip
  description = "Private IP of the Nomad/Consul server."
}

output "nomad_ui_url" {
  value       = "http://${aws_instance.server.public_ip}:4646"
  description = "Nomad UI URL."
}

output "consul_ui_url" {
  value       = "http://${aws_instance.server.public_ip}:8500"
  description = "Consul UI URL."
}

output "ssh_command_server" {
  value       = "ssh ec2-user@${aws_instance.server.public_ip}"
  description = "SSH to the server node."
}

output "client_asg_name" {
  value       = aws_autoscaling_group.clients.name
  description = "Name of the Nomad client ASG."
}
