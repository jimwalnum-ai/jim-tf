
sudo sh -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
sudo yum install emacs -y
pip3 install boto3
pip3 install psycopg2-binary
sudo amazon-linux-extras install epel -y
sudo amazon-linux-extras install postgresql14 

sudo amazon-linux-extras install docker
sudo service docker start
sudo usermod -a -G docker ec2-user
sudo chmod 666 /var/run/docker.sock
sudo yum install -y git

sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

cd ~/gitlab
docker-compose up -d



