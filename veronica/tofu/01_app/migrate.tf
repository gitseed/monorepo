import {
  to = google_project_service.services["artifactregistry.googleapis.com"]
  id = "artifactregistry.googleapis.com"
}
# one more per service: cloudbuild, iam, logging, storage

import {
  to = google_artifact_registry_repository.voice
  id = "projects/untrusted-agent/locations/us-central1/repositories/veronica"
}

import {
  to = google_service_account.build
  id = "voice-build-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = google_project_iam_member.build_builds
  id = "untrusted-agent roles/cloudbuild.builds.builder serviceAccount:voice-build-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = google_artifact_registry_repository_iam_member.build_pushes
  id = "projects/untrusted-agent/locations/us-central1/repositories/veronica roles/artifactregistry.writer serviceAccount:voice-build-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = google_artifact_registry_repository_iam_member.cloudflare_pulls
  id = "projects/untrusted-agent/locations/us-central1/repositories/veronica roles/artifactregistry.reader serviceAccount:voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = cloudflare_workers_kv_namespace.contacts
  id = "<namespace id>"
}

import {
  to = cloudflare_zone_setting.voice_ssl
  id = "<zone id>/ssl"
}
