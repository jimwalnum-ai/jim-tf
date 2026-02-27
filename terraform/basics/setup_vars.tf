locals {
  base_network           = "10.0.0.0"
  base_cidr              = "${local.base_network}/16"
  vpc_name               = "cs-basics"
  tgw_cidr_block         = local.base_cidr
  regional_cidr          = "${local.base_network}/18"
  internal_ingress_cidrs = ["${local.base_network}/8"]

  spoke_vpcs = {
    dev = {
      env                   = "dev"
      region                = "us-east-1"
      ipv4_netmask_length   = 22
      private_subnets_count = 3
      public_subnets_count  = 2
      create_tgw_routes     = true
      test                  = true
      tgw_subnet_tags = {
        "kubernetes.io/cluster/eks-cluster-dev" = "shared"
        "kubernetes.io/role/internal-elb"       = "1"
      }
    }
    prd = {
      env                   = "prd"
      region                = "us-east-1"
      ipv4_netmask_length   = 22
      private_subnets_count = 3
      public_subnets_count  = 0
      create_tgw_routes     = true
      test                  = false
      tgw_subnet_tags = {
        "kubernetes.io/cluster/eks-cluster-prd" = "shared"
        "kubernetes.io/role/internal-elb"       = "1"
      }
    }
  }

  inspect_vpc = {
    env                    = "inspect"
    region                 = "us-east-1"
    ipv4_netmask_length    = 22
    tgw_subnet_cidr_offset = 6
    super_cidr_block       = local.regional_cidr
  }

  blackhole_pairs = {
    for pair in flatten([
      for src_key, src in local.spoke_vpcs : [
        for dst_key, dst in local.spoke_vpcs : {
          src_key = src_key
          dst_key = dst_key
        } if src_key != dst_key
      ]
    ]) : "${pair.src_key}-to-${pair.dst_key}" => pair
  }
}
