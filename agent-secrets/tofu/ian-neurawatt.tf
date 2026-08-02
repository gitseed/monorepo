resource "infisical_secret" "ian_neurawatt_api_token" {
  name         = "IAN_NEURAWATT_API_TOKEN"
  value        = "paste-real-key-here"
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
  lifecycle {
    ignore_changes = [value]
  }
}
