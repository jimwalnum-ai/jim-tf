{
    "Version": "2012-10-17",
    "Statement":  [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Sid":    "AssumeRole",
        "Principal": {
          "Service":"ec2.amazonaws.com"
        }
      },
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Sid":    "AssumeRoleTerraform",
        "Principal": {
           "AWS" :"arn:aws:iam::${acct_id}:user/cloud_user"
        }
      }
    ]
}