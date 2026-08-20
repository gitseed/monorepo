# Don't want to hardcode the cloudflare account id even though it's not a secret.
resource "infisical_secret" "cloudflare_account" {
  name             = "CLOUDFLARE_ACCOUNT_ID"
  value_wo         = "00000000000000000000000000000000"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}

locals {
  cf_account_id = nonsensitive(data.infisical_secrets.ouroboros.secrets.CLOUDFLARE_ACCOUNT_ID.value)
}

data "cloudflare_user" "me" {}

data "cloudflare_api_token_permission_groups_list" "all" {}

locals {
  cf_perms_scope_to_ids = transpose({
    for group in data.cloudflare_api_token_permission_groups_list.all.result :
    group.id => group.scopes
  })
  cf_perms_ids_to_names = {
    for group in data.cloudflare_api_token_permission_groups_list.all.result :
    group.id => group.name
  }

  # User tokens cannot reference permission groups with granular resource
  # scopes (Cloudflare API error 1001: "User tokens cannot reference roles
  # with granular resource scopes"), e.g. the per-app Flagship scopes.
  cf_user_token_excluded_scopes = [
    "com.cloudflare.api.account.flagship.app",
  ]

  cf_perm_groups = {
    for k, v in local.cf_perms_scope_to_ids :
    k => {
      for id in v :
      local.cf_perms_ids_to_names[id] => id
    }
    if !contains(local.cf_user_token_excluded_scopes, k)
  }
}

# The very same cloudflare API token that we are using tofu with!
# This MUST be created with the supposedly legacy "global api key" or by being logged into the console.
# However it can be modified by itself!
resource "cloudflare_api_token" "ouroboros" {
  name = "ouroboros"

  policies = [
    for permission_group_name, permission_group_data in local.cf_perm_groups : {
      effect = "allow"
      permission_groups = [
        for k, v in permission_group_data : {
          id = v
        } if strcontains(lower(k), "write")
      ]
      resources = permission_group_name == "com.cloudflare.api.user" ? jsonencode(
        { "${permission_group_name}.${data.cloudflare_user.me.id}" = "*" }
        ) : jsonencode(
        { "${permission_group_name}.*" = "*" }
      )
    }
  ]
}

resource "infisical_secret" "cloudflare_api_token" {
  name             = "CLOUDFLARE_API_TOKEN"
  value_wo         = coalesce(cloudflare_api_token.ouroboros.value, "notset")
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}
