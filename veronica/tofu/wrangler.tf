# The workspace's wrangler config: the versioned template in app/ plus
# this workspace's values (worker name, hostname, contacts namespace,
# persona). The rendered file is gitignored — switching workspaces means
# applying that workspace, which re-renders it. Nothing in it is secret;
# the two real credentials go straight to the Worker with `wrangler secret
# put`.
resource "local_file" "wrangler_config" {
  filename        = "${path.module}/../app/wrangler.jsonc"
  file_permission = "0644"

  content = templatefile("${path.module}/../app/wrangler.template.jsonc", {
    workspace             = tofu.workspace
    account_id            = local.workspace.cloudflare_account_id
    voice_hostname        = local.workspace.voice_hostname
    contacts_namespace_id = cloudflare_workers_kv_namespace.contacts.id
    driver_image          = local.driver_image
    openai_project_id     = local.workspace.openai_project_id
    voice_model           = local.workspace.voice_model
    voice_voice              = local.workspace.voice_voice
    voice_greeting           = local.workspace.voice_greeting
    voice_greeting_settle_ms = tostring(local.workspace.voice_greeting_settle_ms)
    voice_instructions       = trimspace(local.workspace.voice_instructions)
  })

  # Never render a config that names an image the registry doesn't hold
  # yet: the build blocks the apply until the tag is pullable.
  depends_on = [terraform_data.image]

  lifecycle {
    precondition {
      condition     = can(regex("^proj_[A-Za-z0-9]+$", local.workspace.openai_project_id))
      error_message = "Set openai_project_id in workspace.tf to the OpenAI project id (proj_...) the calls should be handed to."
    }
  }
}
