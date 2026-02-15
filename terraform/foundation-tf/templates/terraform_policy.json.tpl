{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowTerraformActions",
            "Effect": "Allow",
            "Action": [
                "s3:*",
                "ec2:*",
		"iam:*",
		"sqs:*",
		"dynamodb:*",
		"secretsmanager:*",
		"rds:*",
		"ecr:*",
		"ecs:*",
		"eks:*"
            ],
	    "Resource":"*"
        }
   ]
}