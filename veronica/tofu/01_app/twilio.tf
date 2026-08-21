# The number predates this root (it survived the GCP era — releasing a
# number is permanent, so it is never destroyed and recreated); the import
# block adopts it into this state on the first apply and is a no-op after.
import {
  to = twilio_api_accounts_incoming_phone_numbers.voice
  id = "PN382b81adf03939edab2e79cc7a9eddf3"
}

resource "twilio_api_accounts_incoming_phone_numbers" "voice" {
  area_code     = local.workspace.voice_area_code
  friendly_name = "veronica-${tofu.workspace}"
  voice_method  = "POST"
  voice_url     = "https://${local.workspace.voice_hostname}/twiml"

  # Destroying this resource releases the phone number back to Twilio,
  # which is not reversible. The area code only matters at purchase time
  # and the API never echoes it back, so an import leaves it null — ignore
  # it or every plan after an import wants to buy a replacement number.
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [area_code]
  }
}
