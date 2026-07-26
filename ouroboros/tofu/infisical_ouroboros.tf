# The very same machine identity that we are authenticating with in opentofu!
resource "infisical_identity" "ouroboros" {
  name   = "ouroboros"
  role   = "admin"
  org_id = local.org_id
}

resource "infisical_identity_aws_auth" "ouroboros" {
  identity_id                 = infisical_identity.ouroboros.id
  sts_endpoint                = "https://sts.amazonaws.com/"
  allowed_account_ids         = ["593941967609"]                                                                 # TODO
  allowed_principal_arns      = ["arn:aws:sts::593941967609:assumed-role/AWSReservedSSO_admin_5784f67a3f101be8"] # TODO
  access_token_ttl            = 86400
  access_token_max_ttl        = 86400
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
