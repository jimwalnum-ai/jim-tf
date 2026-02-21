sudo sh -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
sudo yum install emacs -y
pip3 install boto3
pip3 install psycopg2-binary
sudo dnf update -y

     # Docker                                                                                                                                                                                           
     sudo dnf install -y docker
     sudo systemctl enable --now docker
     sudo usermod -aG docker ec2-user

     # Docker Compose (plugin)                                                                                                                                                                          
     sudo dnf install -y docker-compose-plugin
     docker compose version

sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

sudo yum install -y openldap openldap-clients openldap-servers
sudo tee /etc/profile.d/ldap.sh >/dev/null <<'EOF'
export LDAP_HOST='ldap.crimsonscallion.com'
export LDAP_BASE='dc=crimsonscallion,dc=com'
export LDAP_PORT='389'
export LDAP_UID='uid'
export LDAP_METHOD='plain'
export LDAP_BIND_DN='cn=admin,dc=crimsonscallion,dc=com'
export LDAP_PASSWORD='admin'
EOF
docker-compose up -d

sleep 10
ldapadd -x -W -D "cn=admin,dc=crimsonscallion,dc=com" -f ./cs.ldif
admin
ldapwhoami -vvv -h localhost -D "uid=onion1,dc=crimsonscallion,dc=com" -x -w onion1
ldapsearch -D "cn=admin,dc=crimsonscallion,dc=com" -W -p 389 -h localhost -b "dc=crimsonscallion,dc=com" -s sub -x "(objectclass=*)"
admin


