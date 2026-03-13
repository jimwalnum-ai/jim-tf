{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid" : "AllowUsersTFBucket",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["${tf_user_arn}"]
      },
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ]
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
