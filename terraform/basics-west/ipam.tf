resource "aws_vpc_ipam" "cs-west" {
  description = "cs-ipam-west"
  operating_regions {
    region_name = "us-west-2"
  }
}

resource "aws_vpc_ipam_pool" "top_level" {
  description    = "top-level-pool-west"
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.cs-west.private_default_scope_id
}

resource "aws_vpc_ipam_pool_cidr" "top_level" {
  ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  cidr         = local.base_cidr
}

resource "aws_vpc_ipam_pool" "regional" {
  description         = "us-west-2-pool"
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.cs-west.private_default_scope_id
  locale              = "us-west-2"
  source_ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  depends_on          = [aws_vpc_ipam_pool.top_level]
}

resource "aws_vpc_ipam_pool_cidr" "us-west-2" {
  ipam_pool_id = aws_vpc_ipam_pool.regional.id
  cidr         = local.regional_cidr
}
