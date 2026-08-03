data "infisical_secrets" "agent" {
  env_slug     = tofu.workspace
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}
