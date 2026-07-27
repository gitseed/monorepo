# The same AWS identity that we are using tofu with!
data "aws_ssoadmin_instances" "main" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
  sso_instance_id   = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  aws_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_identitystore_user" "ouroboros" {
  identity_store_id = local.identity_store_id
  display_name      = local.workspace.human_name
  user_name         = replace(lower(local.workspace.human_name), " ", "_")
  name {
    given_name  = split(" ", local.workspace.human_name)[0]
    family_name = split(" ", local.workspace.human_name)[1]
  }
  emails {
    primary = true
    type    = "personal"
    value   = data.infisical_secrets.ouroboros.secrets.EMAIL_ADDRESS.value
  }
}

resource "aws_identitystore_group" "admin" {
  display_name      = "admin"
  description       = "admin"
  identity_store_id = local.identity_store_id
}

resource "aws_identitystore_group_membership" "ouroboros_admin" {
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.admin.group_id
  member_id         = aws_identitystore_user.ouroboros.user_id
}

resource "aws_ssoadmin_account_assignment" "admin" {
  instance_arn       = local.sso_instance_id
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  principal_id       = aws_identitystore_group.admin.group_id
  principal_type     = "GROUP"
  target_id          = data.aws_caller_identity.current.account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_permission_set" "admin" {
  name             = "admin"
  description      = "admin"
  instance_arn     = local.sso_instance_id
  session_duration = "PT12H" # A full working day
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.sso_instance_id
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
}

resource "time_sleep" "waitfor_accountrole" {
  depends_on = [aws_ssoadmin_account_assignment.admin]
  create_duration = "10s"
}

data "aws_iam_roles" "admin" {
  path_prefix = "/aws-reserved/sso.amazonaws.com/${data.aws_region.current.region}/"
  name_regex  = "AWSReservedSSO_admin_.*"
  depends_on = [time_sleep.waitfor_accountrole]
}

data "aws_iam_role" "admin" {
  name = one(data.aws_iam_roles.admin.names)
}

