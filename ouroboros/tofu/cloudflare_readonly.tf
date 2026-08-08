# A read-only Cloudflare API token for the agent.
# Mirrors cloudflare_ouroboros.tf but selects read permissions instead of write.
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

resource "infisical_secret" "cloudflare_readonly_api_token" {
  name             = "CLOUDFLARE_READONLY_API_TOKEN"
  value_wo         = coalesce(cloudflare_api_token.readonly.value, "notset")
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}
