output "node_group_id" {
  description = "EKS GPU managed node group ID."
  value       = module.gpu_node_group.node_group_id
}

output "node_group_arn" {
  description = "ARN of the EKS GPU managed node group."
  value       = module.gpu_node_group.node_group_arn
}

output "node_group_status" {
  description = "Status of the EKS GPU managed node group."
  value       = module.gpu_node_group.node_group_status
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to GPU nodes."
  value       = module.gpu_node_group.iam_role_arn
}

output "iam_role_name" {
  description = "Name of the IAM role attached to GPU nodes."
  value       = module.gpu_node_group.iam_role_name
}
