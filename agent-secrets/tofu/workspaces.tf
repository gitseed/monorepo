locals {
  workspace = local.workspaces[tofu.workspace]
  workspaces = {
    global = {
      google_project_id = "untrusted-agent"
      google_region     = "us-central1"
    }
  }
}
