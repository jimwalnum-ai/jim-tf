#! /usr/local/bin python3 
import subprocess,boto3
import sys

# main
url= sys.argv[1]


cmd = "scp *.py ec2-user@"  + url +  ":/home/ec2-user/."
resp = subprocess.call(cmd,shell=True)

cmd = "scp ./docker/cs*  ec2-user@"  + url +  ":/home/ec2-user/."
resp = subprocess.call(cmd,shell=True)

cmd = "scp ./docker/docker-compose.yaml ec2-user@"  + url +  ":/home/ec2-user/."
resp = subprocess.call(cmd,shell=True)

cmd = "ssh ec2-user@"  + url +  " /bin/bash < ./upd.sh "
resp = subprocess.call(cmd,shell=True)
