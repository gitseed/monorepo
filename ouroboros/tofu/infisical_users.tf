data "infisical_identity_details" "self" {
}

locals {
  org_id = data.infisical_identity_details.self.organization.id
}

resource "infisical_identity" "user_lister" {
  name   = "user_lister"
  role   = "member"
  org_id = local.org_id
}

resource "infisical_identity_token_auth" "user_lister" {
  identity_id = infisical_identity.user_lister.id
}

resource "infisical_identity_token_auth_token" "user_lister" {
  identity_id = infisical_identity.user_lister.id
  name        = "user-list"
  depends_on  = [infisical_identity_token_auth.user_lister]
}

data "http" "user_list" {
  url = "https://us.infisical.com/api/v2/organizations/${local.org_id}/memberships"
  request_headers = {
    Authorization = "Bearer ${infisical_identity_token_auth_token.user_lister.token}"
  }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Status code was not 200"
    }
  }
}

locals {
  user_list_raw = jsondecode(nonsensitive(data.http.user_list.response_body))
  user_list_parsed = {
    for user in local.user_list_raw["users"] :
    user.user.username => {
      id   = user.user.id
      role = user.role
    }
  }
  org_admins = {
    for k, v in local.user_list_parsed : k => v if v.role == "admin"
  }
}

# infisical_project_identity manages machine identities, not human users.
# Invite each organization admin through Infisical's project-user API instead.
resource "restapi_object" "homelab_org_admin" {
  provider = restapi.infisical_project_memberships
  for_each = local.org_admins

  path      = "/projects/${infisical_project.homelab.id}/memberships"
  object_id = each.value.id

  data = jsonencode({
    emails    = []
    usernames = [each.key]
    roleSlugs = ["admin"]
  })

  # The collection endpoint is the only GET that can refresh these records.
  # Search it by immutable user ID and adopt the membership ID it returns.
  id_attribute = "id"
  read_path    = "/projects/${infisical_project.homelab.id}/memberships"
  read_search = {
    results_key  = "memberships"
    search_key   = "user/id"
    search_value = each.value.id
  }

  # Infisical removes project users by username in a DELETE request body.
  destroy_path = "/projects/${infisical_project.homelab.id}/memberships"
  destroy_data = jsonencode({
    emails    = []
    usernames = [each.key]
  })

  # Invite and read payloads have different shapes. Continue checking that the
  # membership exists, but do not try to PUT the read response back to Infisical.
  ignore_all_server_changes = true
  force_new = [
    infisical_project.homelab.id,
    each.value.id,
    each.key,
    "admin",
  ]

  depends_on = [infisical_project_identity.user_lister]
}
