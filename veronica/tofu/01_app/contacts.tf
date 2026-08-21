resource "cloudflare_workers_kv_namespace" "contacts" {
  account_id = local.workspace.cloudflare_account_id
  title      = "${tofu.workspace}-contacts"
}

resource "cloudflare_workers_kv" "contact" {
  for_each = local.contact_names
  account_id   = local.workspace.cloudflare_account_id
  namespace_id = cloudflare_workers_kv_namespace.contacts.id
  key_name     = each.value
  value        = ""
  lifecycle {
    ignore_changes = [value]
  }
}
