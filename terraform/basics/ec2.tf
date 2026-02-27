data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
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

locals {
  ssh_public_key = trimspace(file("/Users/jameswalnum/.ssh/id_ed25519.pub"))
}

resource "aws_instance" "ec2_public_instance_1" {
  ami                         = data.aws_ami.al2023.id
  subnet_id                   = module.vpc["dev"].public_subnets[0]
  instance_type               = "t3.small"
  iam_instance_profile        = aws_iam_instance_profile.private.name
  vpc_security_group_ids      = [aws_security_group.public_instance.id]
  associate_public_ip_address = true
  depends_on                  = [module.vpc["dev"]]
  user_data                   = <<-EOF
    #!/bin/bash
    install -d -m 700 /home/ec2-user/.ssh
    echo "${local.ssh_public_key}" > /home/ec2-user/.ssh/authorized_keys
    chown -R ec2-user:ec2-user /home/ec2-user/.ssh
    chmod 600 /home/ec2-user/.ssh/authorized_keys
  EOF
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  tags = merge(local.tags, { Name = "test-ec2-ldap-1" })
}

resource "aws_instance" "ec2_public_instance_2" {
  ami           = data.aws_ami.al2023.id
  subnet_id     = module.vpc["dev"].public_subnets[0]
  instance_type = "t3.medium"
  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }
  iam_instance_profile        = aws_iam_instance_profile.private.name
  vpc_security_group_ids      = [aws_security_group.public_instance.id]
  associate_public_ip_address = true
  depends_on                  = [module.vpc["dev"]]
  user_data                   = <<-EOF
    #!/bin/bash
    install -d -m 700 /home/ec2-user/.ssh
    echo "${local.ssh_public_key}" > /home/ec2-user/.ssh/authorized_keys
    chown -R ec2-user:ec2-user /home/ec2-user/.ssh
    chmod 600 /home/ec2-user/.ssh/authorized_keys
  EOF
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  tags = merge(local.tags, { Name = "test-ec2-git-2" })
}


resource "aws_iam_instance_profile" "private" {
  name = "cs-terraform-role"
  role = "cs-terraform-role"
}

resource "aws_instance" "ec2_private_instance" {
  ami                    = data.aws_ami.al2023.id
  subnet_id              = module.vpc["dev"].tgw_subnets[0]
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.private.name
  vpc_security_group_ids = [aws_security_group.private_instance.id]
  depends_on             = [module.vpc["dev"]]
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  tags = merge(local.tags, { Name = "test-ec2-priv" })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = "cs-terraform-role"
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "public_instance" {
  name        = "public-default"
  description = "Public instance security group"
  vpc_id      = module.vpc["dev"].vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = [chomp(file("../../ip.txt"))]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [chomp(file("../../ip.txt"))]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "private_instance" {
  name        = "private-default"
  description = "Private instance security group"
  vpc_id      = module.vpc["dev"].vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

}
