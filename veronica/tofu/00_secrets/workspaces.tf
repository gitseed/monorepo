locals {
  workspace = local.workspaces[tofu.workspace]

  # Mirrors 01_app/workspaces.tf; only the settings this layer consumes.
  workspaces = {
    veronica = {
      project_id = "untrusted-agent"
      region     = "us-central1"

      # The API token is a user token with access to several accounts, so
      # every account-scoped lookup must name the one it means.
      cloudflare_account_id = "287cae24e46a0aeed1dbc2942fc58dd7"
    }
  }
}
