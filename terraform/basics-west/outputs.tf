output "vpc_id" {
  value = module.vpc["dev-west"].vpc_id
}

output "vpc_cidr" {
  value = module.vpc["dev-west"].vpc_cidr
}
