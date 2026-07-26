locals {
  workspace = local.workspaces[tofu.workspace]
  workspaces = {
    global = {
      human_name = "Paul Dejean"
      aws_region = "us-east-2"
    }
  }
}
