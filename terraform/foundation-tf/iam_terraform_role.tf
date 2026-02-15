resource "aws_iam_role" "terraform_role" {
  name                  = "cs-terraform-role"
  description           = "Role for allowing terraform actions on AWS"
  assume_role_policy    = data.template_file.assume_role_policy.rendered
  tags 			= local.tags
}

data "template_file" "terraform_policy" {
  template = "${file("./templates/terraform_policy.json.tpl")}"
}

resource "aws_iam_policy" "role_terraform_policy" {
  name        = "terraform-aws-policy"
  description = "The policy for IAM allowing terraform to change AWS resouces"
  policy      = data.template_file.terraform_policy.rendered
}

resource "aws_iam_role_policy_attachment" "role_terraform_policy" {
  role        = aws_iam_role.terraform_role.name
  policy_arn  = aws_iam_policy.role_terraform_policy.arn
}

