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

# Twilio IAM API requires application/x-www-form-urlencoded POST data.
ephemeral "local_command" "twilio_readonly_key" {
  command = "curl"
  arguments = [
    "-sS",
    "-f",
    "-X", "POST",
    "https://iam.twilio.com/v1/Keys",
    "--data-urlencode", "FriendlyName=monorepo-agent-readonly",
    "--data-urlencode", "AccountSid=${nonsensitive(data.infisical_secrets.ouroboros.secrets.TWILIO_API_KEY.value)}",
    "--data-urlencode", "KeyType=restricted",
    "--data-urlencode", "Policy=${jsonencode(local.twilio_readonly_policy)}",
    "-u", "${data.infisical_secrets.ouroboros.secrets.TWILIO_API_KEY.value}:${data.infisical_secrets.ouroboros.secrets.TWILIO_API_SECRET.value}",
  ]
}

locals {
  twilio_key_response = jsondecode(ephemeral.local_command.twilio_readonly_key.stdout)
}

resource "infisical_secret" "twilio_api_key" {
  name             = "TWILIO_API_KEY"
  value_wo         = local.twilio_key_response.sid
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}

resource "infisical_secret" "twilio_api_secret" {
  name             = "TWILIO_API_SECRET"
  value_wo         = local.twilio_key_response.secret
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
