{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "ReadWriteAccess",
      "Effect": "Allow",
      "Principal": {
                "AWS": ["${user}"]
            },
      "Action": "*",
      "Resource": "*"
    }
  ]
}