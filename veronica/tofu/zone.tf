data "cloudflare_zone" "voice" {
  filter = {
    name = local.workspace.voice_zone
  }
}

# The GCP origin days set this to "flexible"; with no origin left, put the
# zone back on full. The Worker custom domain (claimed by wrangler deploy)
# terminates TLS at the edge and ignores this setting either way.
resource "cloudflare_zone_setting" "voice_ssl" {
  zone_id    = data.cloudflare_zone.voice.id
  setting_id = "ssl"
  value      = "full"

  # Zone settings cannot be deleted through the API; on removal, just forget
  # the resource from state instead of attempting a destroy.
  lifecycle {
    destroy = false
  }
}
