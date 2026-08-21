output "contacts_namespace_id" {
  value       = cloudflare_workers_kv_namespace.contacts.id
  description = "Paste into app/wrangler.jsonc as the CONTACTS binding's id."
}

output "contacts_console_url" {
  value       = "https://dash.cloudflare.com/${local.workspace.cloudflare_account_id}/workers/kv/namespaces/${cloudflare_workers_kv_namespace.contacts.id}"
  description = "Edit the callers' phone numbers here (E.164, for example +15125551234)."
}

output "driver_image" {
  value       = local.driver_image
  description = "The content-addressed image tag the rendered wrangler.jsonc deploys."
}

output "twilio_phone_number" {
  value       = twilio_api_accounts_incoming_phone_numbers.voice.phone_number
  description = "The purchased number; give it to the allowed callers."
}

output "openai_webhook_url" {
  value       = "https://${local.workspace.voice_hostname}/openai-webhook"
  description = "Configure this as the realtime.call.incoming webhook endpoint on platform.openai.com; the hostname is fixed, so this is write-once."
}
