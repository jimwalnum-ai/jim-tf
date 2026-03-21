locals {
  use_transit_gateway    = false
  base_network           = "10.1.0.0"
  base_cidr              = "${local.base_network}/16"
  vpc_name               = "cs-basics"
  regional_cidr          = "${local.base_network}/18"
  internal_ingress_cidrs = ["10.0.0.0/8"]

  spoke_vpcs = {
    dev-west = {
      env                   = "dev-west"
      region                = "us-west-2"
      ipv4_netmask_length   = 22
      private_subnets_count = 3
      public_subnets_count  = 2
      create_tgw_routes     = false
      test                  = true
      tgw_subnet_tags = {
        "kubernetes.io/cluster/eks-cluster-west" = "shared"
        "kubernetes.io/role/internal-elb"        = "1"
      }
    }
  }
}
