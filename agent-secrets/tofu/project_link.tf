# Set "agent" project as the default for cli calls made from this repo.
resource "local_sensitive_file" "infisical_project_config" {
  filename        = "${path.module}/../../.infisical.json"
  file_permission = "0600"
  content = jsonencode({
    workspaceId        = infisical_project.agent.id
    defaultEnvironment = infisical_project_environment.global.slug
  })
}
