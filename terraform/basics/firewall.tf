resource "aws_networkfirewall_firewall" "inspection_vpc_fw" {
  name                = "NetworkFirewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.fw_policy.arn
  vpc_id              = module.vpc-inspect.vpc_id
  subnet_mapping {
    subnet_id = module.vpc-inspect.firewall_subnets[0].id
  }
  subnet_mapping {
    subnet_id = module.vpc-inspect.firewall_subnets[1].id
  }
  depends_on = [module.vpc-inspect]
}

resource "aws_networkfirewall_firewall_policy" "fw_policy" {
  name = "firewall-policy"
  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateless_rule_group_reference {
      priority     = 20
      resource_arn = aws_networkfirewall_rule_group.drop_icmp.arn
    }
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.block_domains.arn
    }
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.block_cross_vpc.arn
    }
  }
}

resource "aws_networkfirewall_rule_group" "drop_icmp" {
  capacity = 1
  name     = "drop-icmp"
  type     = "STATELESS"
  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 1
          rule_definition {
            actions = ["aws:drop"]
            match_attributes {
              protocols = [1]
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_networkfirewall_rule_group" "block_domains" {
  capacity = 100
  name     = "block-domains"
  type     = "STATEFUL"
  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = ["10.0.0.0/8"]
        }
      }
    }
    rules_source {
      rules_source_list {
        generated_rules_type = "DENYLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = [".facebook.com", ".twitter.com"]
      }
    }
  }
}

resource "aws_networkfirewall_rule_group" "block_cross_vpc" {
  capacity = 10
  name     = "block-cross-vpc-traffic"
  type     = "STATEFUL"
  rule_group {
    rules_source {
      stateful_rule {
        action = "DROP"
        header {
          destination      = module.vpc["prd"].vpc_cidr
          destination_port = "ANY"
          direction        = "ANY"
          protocol         = "IP"
          source           = module.vpc["dev"].vpc_cidr
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["1000001"]
        }
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "fw_alert_log_group" {
  name              = "/aws/network-firewall/alert"
  retention_in_days = 365
}

resource "aws_s3_bucket" "fw_flow_bucket" {
  bucket        = "${local.prefix}-use1-network-firewall-flow-bucket-1"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cs-fw-encrypt" {
  bucket = aws_s3_bucket.fw_flow_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "fw_flow_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.fw_flow_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "fw_flow_bucket_retention" {
  bucket = aws_s3_bucket.fw_flow_bucket.id

  rule {
    id     = "retain-1y"
    status = "Enabled"

    expiration {
      days = 365
    }
  }
}

resource "aws_networkfirewall_logging_configuration" "fw_alert_logging_configuration" {
  firewall_arn = aws_networkfirewall_firewall.inspection_vpc_fw.arn
  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.fw_alert_log_group.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }
    log_destination_config {
      log_destination = {
        bucketName = aws_s3_bucket.fw_flow_bucket.bucket
      }
      log_destination_type = "S3"
      log_type             = "FLOW"
    }
  }
}