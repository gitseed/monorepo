# A read-only IAM user for the agent.
# The access key is stored directly in the agent Infisical project.

data "infisical_projects" "agent" {
  slug = "agent"
}

resource "aws_iam_user" "agent_readonly" {
  name = "agent-readonly"
}

resource "aws_iam_user_policy_attachment" "agent_readonly" {
  user       = aws_iam_user.agent_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_access_key" "agent_readonly" {
  user = aws_iam_user.agent_readonly.name
}

resource "infisical_secret" "aws_access_key_id" {
  name             = "AWS_ACCESS_KEY_ID"
  value_wo         = aws_iam_access_key.agent_readonly.id
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = data.infisical_projects.agent.id
  folder_path      = "/"
}

resource "infisical_secret" "aws_secret_access_key" {
  name             = "AWS_SECRET_ACCESS_KEY"
  value_wo         = aws_iam_access_key.agent_readonly.secret
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = data.infisical_projects.agent.id
  folder_path      = "/"
}
