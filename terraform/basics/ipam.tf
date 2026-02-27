resource "aws_vpc_ipam" "cs-main" {
  description = "cs-ipam"
  operating_regions {
    region_name = data.aws_region.current.id
  }
}

resource "aws_vpc_ipam_pool" "top_level" {
  description    = "top-level-pool"
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.cs-main.private_default_scope_id
}

# provision CIDR to the top-level pool
resource "aws_vpc_ipam_pool_cidr" "top_level" {
  ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  cidr         = "10.0.0.0/16"
}

resource "aws_vpc_ipam_pool" "regional" {
  description         = "${data.aws_region.current.id}-1-pool"
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.cs-main.private_default_scope_id
  locale              = data.aws_region.current.id
  source_ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  depends_on          = [aws_vpc_ipam_pool.top_level]
}

resource "aws_vpc_ipam_pool_cidr" "us-east-1" {
  ipam_pool_id = aws_vpc_ipam_pool.regional.id
  cidr         = "10.0.0.0/18"
}


