# Links this monorepo's working tree to the `agent` infisical project for the
# CLI: with .infisical.json present at the repo root, `infisical run` and
# `infisical secrets` need no --projectId/--env flags anywhere in the tree.
# Gitignored (see monorepo root .gitignore); regenerated on apply.
resource "local_sensitive_file" "infisical_project_config" {
  filename        = "${path.module}/../../.infisical.json"
  file_permission = "0600"
  content = jsonencode({
    workspaceId        = infisical_project.agent.id
    defaultEnvironment = infisical_project_environment.global.slug
  })
}
