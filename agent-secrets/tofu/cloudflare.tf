# Bridge the read-only Cloudflare API token from the ouroboros project
# into the agent project, where up.bash loads it via `infisical run`.
resource "infisical_secret" "cloudflare_api_token" {
  name         = "CLOUDFLARE_API_TOKEN"
  value        = data.infisical_secrets.ouroboros.secrets.CLOUDFLARE_READONLY_API_TOKEN.value
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}
