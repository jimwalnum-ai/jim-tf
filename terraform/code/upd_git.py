#! /usr/local/bin python3 
import subprocess,boto3
import sys

# main
url= sys.argv[1]


cmd = "ssh ec2-user@"  + url +  "  mkdir -p gitlab "
resp = subprocess.call(cmd,shell=True)

cmd = "scp ./gitlab/* ec2-user@"  + url +  ":/home/ec2-user/gitlab/."
resp = subprocess.call(cmd,shell=True)

cmd = "ssh ec2-user@"  + url +  " /bin/bash < ./upd_git.sh "
resp = subprocess.call(cmd,shell=True)
