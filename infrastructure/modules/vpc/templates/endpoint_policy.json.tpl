{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "ReadWriteAccess",
      "Effect": "Allow",
      "Principal": {
                "AWS": ["${user}", "arn:aws:iam::${account_id}:root"]
            },
      "Action": "*",
      "Resource": "*"
    }
  ]
}