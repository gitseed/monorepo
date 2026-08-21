# The credentials proxy signs AWS API requests with these access keys.
resource "aws_iam_user" "credentials_proxy" {
  name = "credentials-proxy"
  path = "/service/"
}

resource "aws_iam_user_policy_attachment" "readonly" {
  user       = aws_iam_user.credentials_proxy.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_access_key" "credentials_proxy" {
  user = aws_iam_user.credentials_proxy.name
}

resource "infisical_secret" "aws_access_key_id" {
  name         = "AWS_ACCESS_KEY_ID"
  value        = aws_iam_access_key.credentials_proxy.id
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}

resource "infisical_secret" "aws_secret_access_key" {
  name             = "AWS_SECRET_ACCESS_KEY"
  value_wo         = aws_iam_access_key.credentials_proxy.secret
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
