
sudo sh -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
sudo yum install emacs -y
pip3 install boto3
pip3 install psycopg2-binary
sudo dnf update -y

     # Docker
     sudo dnf install -y docker
     sudo systemctl enable --now docker
     sudo usermod -aG docker ec2-user

     # Git
     sudo dnf install -y git

     # Docker Compose (plugin)
     sudo dnf install -y docker-compose-plugin
     docker compose version

sudo yum install -y git

sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

if [ -f /etc/profile.d/ldap.sh ]; then
  . /etc/profile.d/ldap.sh
fi

cd ~/gitlab
sudo docker-compose up -d



