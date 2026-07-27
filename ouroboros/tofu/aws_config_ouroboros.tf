# The very aws config file that we're using to authenticate to AWS!
# And also the very aws config file that we're using to authenticate to r2 for the state!
resource "local_sensitive_file" "aws_config" {
  content = templatefile("${path.module}/templates/aws_config.tftpl", {
    aws_account_id                           = local.aws_account_id
    aws_region                               = local.workspace.aws_region
    aws_identity_center_managing_instance_id = split("/", one(data.aws_ssoadmin_instances.main.arns))[1]
    r2_access_key_id                         = data.infisical_secrets.ouroboros.secrets.R2_ACCESS_KEY_ID.value
    r2_secret_access_key                     = data.infisical_secrets.ouroboros.secrets.R2_SECRET_ACCESS_KEY.value
    cf_account_id                            = local.cf_account_id
  })
  filename = pathexpand("~/.aws/config")
}
