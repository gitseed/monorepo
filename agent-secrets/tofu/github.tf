locals {
  # Paste the real token, apply, revert. value_wo never reaches state, and
  # both secrets derive from this one paste point so they rotate together.
  github_pat         = "paste github token here"
  github_pat_version = 1
}

resource "infisical_secret" "github_classic_pat" {
  name             = "GITHUB_TOKEN"
  value_wo         = local.github_pat
  value_wo_version = local.github_pat_version
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}

# github.com's git smart-HTTP endpoints only accept Basic auth, and envoy's
# credential injector can't base64 -- so the encoded form is its own secret.
resource "infisical_secret" "github_classic_pat_basic" {
  name             = "GITHUB_TOKEN_BASIC"
  value_wo         = base64encode("x-access-token:${local.github_pat}")
  value_wo_version = local.github_pat_version
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
