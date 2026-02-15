resource "aws_iam_role" "role" {
  name               = "cs-terraform-backend-role"
  description        = "Role for allowing s3 backend for terraform"
  assume_role_policy = data.template_file.assume_role_policy.rendered
  tags               = local.tags
}

data "template_file" "assume_role_policy" {
  template = file("./templates/backend_assume_policy.json.tpl")
  vars = {
    acct_id = local.acct_id
  }
}

data "template_file" "backend_allow_policy" {
  template = file("./templates/backend_allow_policy.json.tpl")
  vars = {
    bucket   = module.s3.bucket_arn
    dynamodb = aws_dynamodb_table.dynamodb-terraform-state-lock.name
  }
}

resource "aws_iam_policy" "role_allow_policy" {
  name        = "terraform-s3-backend-policy"
  description = "The policy for IAM allowing access to terraform s3 backend"
  policy      = data.template_file.backend_allow_policy.rendered
}

resource "aws_iam_role_policy_attachment" "role_policy" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.role_allow_policy.arn
}

