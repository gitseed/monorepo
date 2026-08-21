locals {
  workspace = local.workspaces[tofu.workspace]
  workspaces = {
    veronica = {
      project_id            = "untrusted-agent"
      region                = "us-central1"
      cloudflare_account_id = "287cae24e46a0aeed1dbc2942fc58dd7"
    }
  }
}
