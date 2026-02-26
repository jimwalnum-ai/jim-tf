data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_key_pair" "nomad" {
  key_name   = "${local.name_prefix}-key"
  public_key = local.ssh_public_key
  tags       = local.tags
}

resource "aws_instance" "server" {
  ami                         = data.aws_ami.al2023_arm.id
  instance_type               = var.server_instance_type
  subnet_id                   = data.aws_subnets.public.ids[0]
  vpc_security_group_ids      = [aws_security_group.nomad_cluster.id]
  iam_instance_profile        = aws_iam_instance_profile.nomad_node.name
  key_name                    = aws_key_pair.nomad.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = templatefile("${path.module}/templates/server_userdata.sh.tpl", {
    nomad_version       = var.nomad_version
    consul_version      = var.consul_version
    cni_plugins_version = var.cni_plugins_version
    server_count        = 1
    datacenter          = "dc1"
    region              = "us-east-1"
  })

  user_data_replace_on_change = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-server" })
}
