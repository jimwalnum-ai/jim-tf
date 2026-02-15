{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid" : "AllowUsersTFBucket",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["${tf_user_arn}"]
      },
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::${bucket_name}"]
    },
    {
     "Sid" : "RequireSSL",
     "Action": "s3:*",
     "Effect": "Deny",
     "Principal": "*",
     "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ],
     "Condition": {
       "Bool": { "aws:SecureTransport": false }
     }
    }
  ]
}
