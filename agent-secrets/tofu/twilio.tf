# RestAPI provider configuration for Twilio IAM API (using ouroboros admin credentials).
provider "restapi" {
  alias                = "twilio"
  uri                  = "https://iam.twilio.com"
  write_returns_object = true
  id_attribute         = "sid"
  username             = data.infisical_secrets.ouroboros.secrets.TWILIO_API_KEY.value
  password             = data.infisical_secrets.ouroboros.secrets.TWILIO_API_SECRET.value
}

locals {
  # Granular read-only permissions for agent inspection (phone numbers, usage, voice, etc.)
  twilio_readonly_policy = {
    allow = [
      "/twilio/billing/usage/read",
      "/twilio/phone-numbers/active-numbers/read",
      "/twilio/phone-numbers/available-phone-numbers/read",
      "/twilio/phone-numbers/bundle-copies/read",
      "/twilio/phone-numbers/regulatory-compliance.end-users/read",
      "/twilio/phone-numbers/regulatory-compliance.supporting-document-types/read",
      "/twilio/phone-numbers/regulatory-compliance.supporting-documents/read",
      "/twilio/voice/byoc-trunks/read",
      "/twilio/voice/connection-policies/read",
      "/twilio/voice/ip-records/read",
      "/twilio/voice/sip-domains/read",
      "/twilio/voice/source-ip-mappings/read",
    ]
  }
}

resource "restapi_object" "twilio_readonly_key" {
  provider  = restapi.twilio
  path      = "/v1/Keys"
  read_path = "/v1/Keys/{id}"
  data = jsonencode({
    AccountSid   = nonsensitive(data.infisical_secrets.ouroboros.secrets.TWILIO_API_KEY.value)
    FriendlyName = "monorepo-agent-readonly"
    KeyType      = "restricted"
    Policy       = jsonencode(local.twilio_readonly_policy)
  })
}

resource "infisical_secret" "twilio_api_key" {
  name         = "TWILIO_API_KEY"
  value        = restapi_object.twilio_readonly_key.id
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}

resource "infisical_secret" "twilio_api_secret" {
  name             = "TWILIO_API_SECRET"
  value_wo         = restapi_object.twilio_readonly_key.api_data.secret
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
