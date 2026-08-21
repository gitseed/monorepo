import {
  to = google_service_account.image_pull
  id = "voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = google_service_account_key.image_pull
  id = "projects/untrusted-agent/serviceAccounts/voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com/keys/<key id — gcloud iam service-accounts keys list --iam-account=voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com>"
}

import {
  to = cloudflare_account_token.registry
  id = "<token id — Cloudflare dashboard, Account API Tokens>"
}

import {
  to = cloudflare_secrets_store_secret.gar_key
  id = "<account id>/<store id>/veronica-gar-pull"
}

import {
  to = restapi_object.gar_registry
  id = "us-central1-docker.pkg.dev"
}
