# Twilio IAM API requires application/x-www-form-urlencoded POST data.
# When Policy is invalid or permissions do not exist, Twilio returns 400 with a detailed JSON error body.
locals {
  twilio_readonly_policy = {
    allow = [
      "/twilio/phone-numbers/active-numbers/read",
      "/twilio/phone-numbers/incoming-phone-numbers/read",
      "/twilio/billing/usage/read",
    ]
  }
}

ephemeral "local_command" "twilio_readonly_key" {
  command = "curl"
  arguments = [
    "-sS",
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
  value_wo_version = 2
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}

resource "infisical_secret" "twilio_api_secret" {
  name             = "TWILIO_API_SECRET"
  value_wo         = local.twilio_key_response.secret
  value_wo_version = 2
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
