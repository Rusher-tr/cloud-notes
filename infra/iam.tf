# ----------------------------------------------------------------------------
# IAM - two roles, each with only what it needs
#   1. EC2 instance role   : pull images, read ONE secret, write logs, be managed by SSM
#   2. GitHub Actions role : push images, trigger the deploy command. Assumed via
#                            OIDC, so no long-lived AWS keys are stored in GitHub.
# ----------------------------------------------------------------------------

# ===================== 1. EC2 instance role =====================
resource "aws_iam_role" "instance" {
  name = "${local.name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM agent: lets the pipeline run the deploy command, and gives shell access
# through Session Manager - so no SSH port, key pair or bastion host is needed.
resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "instance" {
  name = "${local.name}-instance-policy"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # this action does not support resource-level permissions
      },
      {
        Sid      = "EcrPullOnly"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = [for r in aws_ecr_repository.repo : r.arn]
      },
      {
        Sid      = "ReadDbSecretOnly"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = local.db_secret_arn
      },
      {
        Sid      = "WriteContainerLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "${aws_cloudwatch_log_group.containers.arn}:*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.instance.name
}

# ===================== 2. GitHub Actions (OIDC) role =====================
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

locals {
  github_owner     = split("/", var.github_repo)[0]
  github_repo_name = split("/", var.github_repo)[1]

  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "${local.name}-github-actions-role"

  # Only workflows running on the main branch of YOUR repository can assume this role.
  # GitHub may send the subject in the classic form   repo:owner/name:ref:refs/heads/main
  # or with immutable IDs                              repo:owner@123/name@456:ref:refs/heads/main
  # so both forms are accepted (owner, repo name and branch are still fixed).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:ref:refs/heads/main",
            "repo:${local.github_owner}@*/${local.github_repo_name}@*:ref:refs/heads/main",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "${local.name}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPushToOurReposOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [for r in aws_ecr_repository.repo : r.arn]
      },
      {
        Sid      = "FindInstances"
        Effect   = "Allow"
        Action   = "autoscaling:DescribeAutoScalingGroups"
        Resource = "*" # describe actions do not support resource-level permissions
      },
      {
        Sid      = "RunShellScriptDocument"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"
      },
      {
        Sid      = "OnlyOnOurTaggedInstances"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/*"
        Condition = {
          StringEquals = { "ssm:resourceTag/DeployGroup" = local.name }
        }
      },
      {
        Sid      = "ReadCommandResults"
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
        Resource = "*"
      }
    ]
  })
}
