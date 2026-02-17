{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "s3:Put*",
                "s3:List*",
                "s3:Get*",
                "s3:Delete*"
            ],
            "Resource": [
                "${bucket}/*",
                "${bucket}"
            ]
        },
	{
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "dynamodb:*"
            ],
            "Resource": ["arn:aws:dynamodb:*:*:table/${dynamodb}"]
        }
   ]
}