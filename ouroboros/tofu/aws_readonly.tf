# A read-only IAM user for the agent.
# The access key is stored in Infisical and consumed by the credentials
# proxy's aws_request_signing filter via environment variables.

resource "aws_iam_user" "agent_readonly" {
  name = "agent-readonly"
}

# A comprehensive read-only policy.  This grants read access to all
# AWS services the agent might need to inspect, without any write
# permissions.
resource "aws_iam_user_policy" "agent_readonly" {
  name   = "ReadOnlyAccess"
  user   = aws_iam_user.agent_readonly.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:Get*",
          "s3:Get*",
          "s3:List*",
          "s3:Describe*",
          "iam:Get*",
          "iam:List*",
          "iam:GenerateCredentialReport",
          "iam:SimulatePrincipalPolicy",
          "sts:GetCallerIdentity",
          "sts:Get*",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricStream",
          "cloudwatch:List*",
          "logs:Describe*",
          "logs:Get*",
          "logs:List*",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "lambda:Get*",
          "lambda:List*",
          "dynamodb:Describe*",
          "dynamodb:List*",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "rds:Describe*",
          "rds:List*",
          "sns:List*",
          "sns:Get*",
          "sqs:List*",
          "sqs:Get*",
          "sqs:ReceiveMessage",
          "elasticache:Describe*",
          "elasticache:List*",
          "ecs:Describe*",
          "ecs:List*",
          "eks:Describe*",
          "eks:List*",
          "kms:Describe*",
          "kms:List*",
          "kms:Get*",
          "secretsmanager:List*",
          "secretsmanager:Describe*",
          "ssm:Describe*",
          "ssm:Get*",
          "ssm:List*",
          "cloudformation:Describe*",
          "cloudformation:List*",
          "cloudformation:Get*",
          "cloudformation:ValidateTemplate",
          "elasticloadbalancing:Describe*",
          "route53:List*",
          "route53:Get*",
          "acm:Describe*",
          "acm:List*",
          "waf:List*",
          "waf:Get*",
          "wafv2:List*",
          "wafv2:Describe*",
          "wafv2:Get*",
          "organizations:Describe*",
          "organizations:List*",
          "pricing:DescribeServices",
          "pricing:GetProducts",
          "cur:Describe*",
          "cur:Get*",
          "cur:List*",
          "cur:Validate*",
          "ce:Get*",
        "ce:List*",
        "ce:Describe*"
      ],
      Resource = "*"
      }
    ]
  })
}

# The access key.  value_wo keeps it out of the plan; it only becomes
# real after `tofu apply` stores it in Infisical.
resource "aws_iam_access_key" "agent_readonly" {
  user = aws_iam_user.agent_readonly.name
}

resource "infisical_secret" "aws_access_key_id" {
  name             = "AWS_ACCESS_KEY_ID"
  value_wo         = aws_iam_access_key.agent_readonly.id
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}

resource "infisical_secret" "aws_secret_access_key" {
  name             = "AWS_SECRET_ACCESS_KEY"
  value_wo         = aws_iam_access_key.agent_readonly.secret
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}
