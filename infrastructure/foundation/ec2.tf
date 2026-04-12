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
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    dnf update -y
    dnf install -y docker emacs openldap-clients
    pip3 install boto3 psycopg2-binary

    systemctl enable --now docker
    usermod -aG docker ec2-user

    curl -sL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    cat > /etc/profile.d/ldap.sh <<'PROFILE'
    export LDAP_HOST='ldap.crimsonscallion.com'
    export LDAP_BASE='dc=crimsonscallion,dc=com'
    export LDAP_PORT='389'
    export LDAP_UID='uid'
    export LDAP_METHOD='plain'
    export LDAP_BIND_DN='cn=admin,dc=crimsonscallion,dc=com'
    export LDAP_PASSWORD='admin'
    PROFILE

    mkdir -p /home/ec2-user/ldap

    cat > /home/ec2-user/ldap/docker-compose.yaml <<'COMPOSE'
    version: '2'
    services:
      ldap:
        image: osixia/openldap:latest
        container_name: ldap
        environment:
          - LDAP_ORGANISATION=crimsonscallion
          - LDAP_DOMAIN=crimsonscallion.com
          - LDAP_BASE_DN=dc=crimsonscallion,dc=com
        ports:
          - 389:389
          - 636:636
    COMPOSE

    cat > /home/ec2-user/ldap/cs.ldif <<'LDIF'
    dn: uid=onion1,dc=crimsonscallion,dc=com
    uid: onion1
    cn: onion1
    sn: 3
    objectClass: top
    objectClass: posixAccount
    objectClass: inetOrgPerson
    loginShell: /bin/bash
    homeDirectory: /home/onion1
    uidNumber: 14583102
    gidNumber: 14564100
    userPassword: {SHA}fvTv8tCmdMjIDvytzl8qREDwTPA=
    mail: onion@crimsonscallion.com
    gecos: Head Onion
    LDIF

    chown -R ec2-user:ec2-user /home/ec2-user/ldap
    cd /home/ec2-user/ldap
    /usr/local/bin/docker-compose up -d

    for i in $(seq 1 30); do
      ldapadd -x -H ldap://localhost -D "cn=admin,dc=crimsonscallion,dc=com" \
        -w admin -f /home/ec2-user/ldap/cs.ldif && break
      sleep 5
    done
  EOF
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  tags = merge(local.tags, { Name = "test-ec2-ldap-1" })
}

resource "aws_instance" "gitlab" {
  ami           = data.aws_ami.al2023.id
  subnet_id     = module.vpc["dev"].tgw_subnets[0]
  instance_type = "t3.medium"
  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }
  iam_instance_profile        = aws_iam_instance_profile.private.name
  vpc_security_group_ids      = [aws_security_group.gitlab_instance.id]
  depends_on                  = [module.vpc["dev"]]
  user_data                   = <<-EOF
    #!/bin/bash
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    dnf update -y
    dnf install -y docker git emacs
    pip3 install boto3 psycopg2-binary

    systemctl enable --now docker
    usermod -aG docker ec2-user

    curl -sL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    cat > /etc/profile.d/ldap.sh <<'PROFILE'
    export LDAP_HOST='ldap.crimsonscallion.com'
    export LDAP_BASE='dc=crimsonscallion,dc=com'
    export LDAP_PORT='389'
    export LDAP_UID='uid'
    export LDAP_METHOD='plain'
    export LDAP_BIND_DN='cn=admin,dc=crimsonscallion,dc=com'
    export LDAP_PASSWORD='admin'
    PROFILE

    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/local-ipv4)

    mkdir -p /home/ec2-user/gitlab

    cat > /home/ec2-user/gitlab/docker-compose.yml <<COMPOSE
    version: '3.7'
    services:
      gitlab:
        image: 'gitlab/gitlab-ce:15.11.13-ce.0'
        container_name: 'my-gitlab'
        restart: always
        hostname: 'localhost'
        network_mode: 'host'
        environment:
          GITLAB_OMNIBUS_CONFIG: |
            external_url 'http://$PRIVATE_IP'
            nginx['listen_port'] = 80
            nginx['listen_https'] = false
            puma['worker_processes'] = 0
            sidekiq['max_concurrency'] = 5
            prometheus_monitoring['enable'] = false
            grafana['enable'] = false
            gitlab_pages['enable'] = false
            alertmanager['enable'] = false
            gitlab_rails['gitlab_shell_ssh_port'] = 222
            gitlab_sshd['enable'] = true
            gitlab_sshd['listen_address'] = '[::]:222'
            gitlab_rails['ldap_enabled'] = true
            gitlab_rails['ldap_host'] = 'ldap.crimsonscallion.com'
            gitlab_rails['ldap_base'] = 'dc=crimsonscallion,dc=com'
            gitlab_rails['ldap_port'] = 389
            gitlab_rails['ldap_uid'] = 'uid'
            gitlab_rails['ldap_method'] = 'plain'
            gitlab_rails['ldap_bind_dn'] = 'cn=admin,dc=crimsonscallion,dc=com'
            gitlab_rails['ldap_password'] = 'admin'
            gitlab_rails['ldap_allow_username_or_email_login'] = true
        volumes:
          - './gitlab-data/config:/etc/gitlab'
          - './gitlab-data/logs:/var/log/gitlab'
          - './gitlab-data/data:/var/opt/gitlab'
    COMPOSE

    chown -R ec2-user:ec2-user /home/ec2-user/gitlab
    cd /home/ec2-user/gitlab
    /usr/local/bin/docker-compose up -d
  EOF
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  tags = merge(local.tags, { Name = "gitlab" })
}


resource "aws_iam_role" "ec2_workload" {
  name = "cs-ec2-workload"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ec2_workload_ssm" {
  role       = aws_iam_role.ec2_workload.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "private" {
  name = "cs-ec2-workload"
  role = aws_iam_role.ec2_workload.name
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

###########################
# GitLab ALB
###########################

resource "aws_security_group" "gitlab_alb" {
  name        = "gitlab-alb"
  description = "Security group for GitLab ALB"
  vpc_id      = module.vpc["dev"].vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "gitlab_instance" {
  name        = "gitlab-instance"
  description = "Security group for GitLab EC2 behind ALB"
  vpc_id      = module.vpc["dev"].vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab_alb.id]
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
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "gitlab" {
  name               = "gitlab-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.gitlab_alb.id]
  subnets            = module.vpc["dev"].public_subnets
  tags               = merge(local.tags, { Name = "gitlab-alb" })
}

resource "aws_lb_target_group" "gitlab" {
  name     = "gitlab-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc["dev"].vpc_id

  health_check {
    path                = "/-/health"
    protocol            = "HTTP"
    port                = "80"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.tags, { Name = "gitlab-tg" })
}

resource "aws_lb_target_group_attachment" "gitlab" {
  target_group_arn = aws_lb_target_group.gitlab.arn
  target_id        = aws_instance.gitlab.id
  port             = 80
}

resource "aws_lb_listener" "gitlab_http" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab.arn
  }
}

output "gitlab_alb_dns" {
  value = aws_lb.gitlab.dns_name
}
