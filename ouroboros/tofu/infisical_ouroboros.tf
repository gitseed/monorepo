# The very same machine identity that we are using tofu with!
resource "infisical_identity" "ouroboros" {
  name   = "ouroboros"
  role   = "admin"
  org_id = local.org_id
}

resource "infisical_identity_aws_auth" "ouroboros" {
  identity_id                 = infisical_identity.ouroboros.id
  sts_endpoint                = "https://sts.amazonaws.com/"
  allowed_account_ids         = [local.aws_account_id] # TODO
  allowed_principal_arns      = ["arn:aws:sts::${local.aws_account_id}:assumed-role/${data.aws_iam_role.admin.name}"]
  access_token_ttl            = 86400 # 1 day
  access_token_max_ttl        = 86400 # 1 day
  access_token_num_uses_limit = 0
  access_token_trusted_ips = [
    {
      ip_address = "0.0.0.0/0"
    },
    {
      ip_address = "::/0"
    },
  ]
}
