# A read-only Cloudflare API token for the agent.
# Uses the admin Cloudflare token from ouroboros to create a scoped
# read-only token, stored directly in the agent Infisical project.

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
  cf_perm_groups = {
    for k, v in local.cf_perms_scope_to_ids :
    k => {
      for id in v :
      local.cf_perms_ids_to_names[id] => id
    }
  }
}

resource "cloudflare_api_token" "readonly" {
  name = "agent-readonly"

  policies = [
    for permission_group_name, permission_group_data in local.cf_perm_groups : {
      effect = "allow"
      permission_groups = [
        for k, v in permission_group_data : {
          id = v
        } if strcontains(lower(k), "read")
      ]
      resources = permission_group_name == "com.cloudflare.api.user" ? jsonencode(
        { "${permission_group_name}.${data.cloudflare_user.me.id}" = "*" }
        ) : jsonencode(
        { "${permission_group_name}.*" = "*" }
        )
    }
    if anytrue([for k, _ in permission_group_data : strcontains(lower(k), "read")])
  ]
}

resource "infisical_secret" "cloudflare_api_token" {
  name             = "CLOUDFLARE_API_TOKEN"
  value_wo         = coalesce(cloudflare_api_token.readonly.value, "notset")
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
