This creates a role that allows access to the terraform backend s3 bucket and to a dynamo db
table that manages locking for terraform applies. The locking is important as only one update
should be allowed at a time.

The assume role policy allows another user/role (in this case the use /cloud_user) to assume this
backend role.

This role has accesss to the s3 bucket holding the terraform state files. These files
can hold plain text secrets so their access must be protected. 

```
resource "aws_iam_role" "role" {
  name                  = "cs-terraform-backend-role"
  description           = "Role for allowing s3 backend for terraform"
  assume_role_policy    = data.template_file.assume_role_policy.rendered
  tags 			= local.tags
}
```

Template file of the assume role policy. Takes an argument of the current account number. 

```
data "template_file" "assume_role_policy" {
  template = "${file("./templates/backend_assume_policy.json.tpl")}"
  vars = {
    acct_id = local.acct_id
  }
}
```

This is the policy the controls the access to the s3 bucket holding the terraform state files
and the dynanmo db table that controls update locking

```
data "template_file" "backend_allow_policy" {
  template = "${file("./templates/backend_allow_policy.json.tpl")}"
  vars = {
    bucket   = module.s3.bucket_arn
    dynamodb = aws_dynamodb_table.dynamodb-terraform-state-lock.name
  }
}
```
Policy for controlling terraform backend actions

```
resource "aws_iam_policy" "role_allow_policy" {
  name        = "terraform-s3-backend-policy"
  description = "The policy for IAM allowing access to terraform s3 backend"
  policy      = data.template_file.backend_allow_policy.rendered
}
```

Attach the policy to the backend role 
```
resource "aws_iam_role_policy_attachment" "role_policy" {
  role        = aws_iam_role.role.name
  policy_arn  = aws_iam_policy.role_allow_policy.arn
}
```

