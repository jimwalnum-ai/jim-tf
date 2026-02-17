{
   "Version": "2012-10-17",
   "Id": "Queue1_Policy",
   "Statement": [{
      "Sid":"Queue1_AllActions",
      "Effect": "Allow",
      "Principal": {
         "AWS": [ "${allowed_role}" ]
      },
      "Action": "sqs:*",
      "Resource": "arn:aws:sqs:us-east-1:${acct}:SQS*"
   }]
}