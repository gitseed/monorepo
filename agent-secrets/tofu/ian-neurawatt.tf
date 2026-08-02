# Ian's Neurawatt API token (https://api.neuralwatt.com, OpenAI-compatible
# gateway). Unlike openrouter.tf there is no provider that mints this key,
# so tofu only CLAIMS the slot:
#
#   1. tofu apply                (creates the secret with a placeholder)
#   2. paste the real key into infisical by hand
#
# ...and then never lets tofu overwrite what was pasted.
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
