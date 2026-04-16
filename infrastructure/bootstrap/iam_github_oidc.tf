################################################################################
# GitHub Actions OIDC Provider
################################################################################

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint — stable, rotated by GitHub with advance notice
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.tags
}

################################################################################
# IAM Role — assumed by GitHub Actions via OIDC
################################################################################

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to pushes on the main branch of this repo only
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:jimwalnum-ai/jim-tf:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-ecr-push"
  description        = "Assumed by GitHub Actions via OIDC to build and push images to ECR"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  tags               = local.tags
}

################################################################################
# ECR Push Policy
################################################################################

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken is account-level, not resource-scoped
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Scope image push/pull to the specific repos used by CI
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/flask-app",
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/factor-worker",
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/factor-process",
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/factor-persist",
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/factor-test-msg",
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/cilium-security-agent",
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/cilium-security-dashboard",
      "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.id}:${local.acct_id}:repository/observability-dashboard",
    ]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "github-actions-ecr-push-policy"
  description = "Allows GitHub Actions to push images to the CI-managed ECR repositories"
  policy      = data.aws_iam_policy_document.ecr_push.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

################################################################################
# GitHub Secret — keep AWS_OIDC_ROLE_ARN in sync automatically
################################################################################

resource "github_actions_secret" "oidc_role_arn" {
  repository      = "jim-tf"
  secret_name     = "AWS_OIDC_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions.arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC."
  value       = aws_iam_role.github_actions.arn
}
