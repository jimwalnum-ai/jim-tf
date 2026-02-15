resource "aws_key_pair" "ec2" {
    key_name = "cs_key_pair"
    public_key  = file("../../../.ssh/id_rsa.pub")
}

data "aws_subnets" "private_selected" {
  filter {
    name   = "tag:scope"
    values = ["private"] 
  }
  filter {
    name   = "vpc-id"
    values = [module.vpc-dev.vpc_id]
  }
}

data "aws_subnets" "public_selected" {
  filter {
    name   = "tag:scope"
    values = ["public"] 
  }
  filter {
    name   = "vpc-id"
    values = [module.vpc-dev.vpc_id]
  }
}

resource "aws_instance" "ec2_public_instance_1" {
    ami = "ami-090e0fc566929d98b"
    subnet_id = data.aws_subnets.public_selected.ids[0]
    instance_type = "t3.small"
    iam_instance_profile = aws_iam_instance_profile.private.name
    key_name = aws_key_pair.ec2.key_name
    vpc_security_group_ids = [aws_security_group.public_instance.id]
    associate_public_ip_address = true
    tags = "${merge(local.tags,{Name="test-ec2-ldap-1"})}"
}

resource "aws_instance" "ec2_public_instance_2" {
    ami = "ami-090e0fc566929d98b"
    subnet_id = data.aws_subnets.public_selected.ids[0]
    instance_type = "t3.medium"
    iam_instance_profile = aws_iam_instance_profile.private.name
    key_name = aws_key_pair.ec2.key_name
    vpc_security_group_ids = [aws_security_group.public_instance.id]
    associate_public_ip_address = true
    tags = "${merge(local.tags,{Name="test-ec2-git-2"})}"
}


resource "aws_iam_instance_profile" "private" {
  name = "cs-terraform-role"
  role = "cs-terraform-role"
}

resource "aws_instance" "ec2_private_instance" {
    ami = "ami-090e0fc566929d98b"
    subnet_id = data.aws_subnets.private_selected.ids[0]
    instance_type = "t3.micro"
    iam_instance_profile = aws_iam_instance_profile.private.name
    key_name = aws_key_pair.ec2.key_name
    vpc_security_group_ids = [aws_security_group.private_instance.id]
    tags = "${merge(local.tags,{Name="test-ec2-priv"})}"
}

resource "aws_security_group" "public_instance" {
  name        = "public-default"
  description = "Public instance security group"
  vpc_id      = module.vpc-dev.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
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
  vpc_id      = module.vpc-dev.vpc_id

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
