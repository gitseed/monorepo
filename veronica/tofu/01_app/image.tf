# The driver's container image: built by Cloud Build (kicked off from the
# apply itself, no local Docker anywhere) into Artifact Registry, where
# Cloudflare pulls it from — the officially supported alternative to
# wrangler's build-locally-and-push flow. Images are tagged with the source
# hash, so every tag is immutable and the rendered wrangler config pins
# exactly what was built.
#
# The required Google APIs are enabled by 00_secrets, which always applies
# first.

resource "google_artifact_registry_repository" "voice" {
  repository_id = tofu.workspace
  format        = "DOCKER"
  description   = "Veronica's session driver images, built by ${tofu.workspace}'s tofu apply."
}

# Builds run as a per-workspace SA (the compute default SA would work but is
# shared project-wide, and each workspace must own its own IAM members).
resource "google_service_account" "build" {
  account_id   = "voice-build-${tofu.workspace}"
  display_name = "Veronica session image build"
}

resource "google_project_iam_member" "build_builds" {
  project = local.workspace.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.build.email}"
}

# The builder role's Artifact Registry access is project-dependent; grant the
# push on the repository explicitly so the build never races policy quirks.
resource "google_artifact_registry_repository_iam_member" "build_pushes" {
  repository = google_artifact_registry_repository.voice.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.build.email}"
}

# Cloudflare's pull identity lives in 00_secrets (with its key); this
# grant reaches it by name only, so the layers never touch each other's
# state.
locals {
  pull_sa_email = "voice-pull-${tofu.workspace}@${local.workspace.project_id}.iam.gserviceaccount.com"
}

resource "google_artifact_registry_repository_iam_member" "cloudflare_pulls" {
  repository = google_artifact_registry_repository.voice.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${local.pull_sa_email}"
}

# A build kicked off seconds after the grants above loses the IAM propagation
# race (observed on untrusted-agent twice: "Access to bucket ... denied" in
# the 01_session_image era, and storage.objects.get denied on the source
# tarball when this root first applied — 5s was not enough). Sleeping only
# on grant creation keeps steady-state applies free.
resource "time_sleep" "build_iam_propagation" {
  create_duration = "20s"
  triggers = {
    builder = google_project_iam_member.build_builds.id
    pusher  = google_artifact_registry_repository_iam_member.build_pushes.id
  }
}

locals {
  image_repository = "${local.workspace.region}-docker.pkg.dev/${local.workspace.project_id}/${google_artifact_registry_repository.voice.repository_id}/driver"

  # Any change to the driver's source replaces the build resource below,
  # which re-runs the provisioner. Each path is hashed alongside its
  # content so a pure rename (same bytes, new location) still rebuilds.
  driver_source_hash = sha1(join("", [
    for f in sort(fileset("${path.module}/../../app/driver", "**")) :
    "${f}=${filesha1("${path.module}/../../app/driver/${f}")}"
  ]))

  # The content-addressed tag the rendered wrangler config deploys.
  driver_image = "${local.image_repository}:${local.driver_source_hash}"
}

# The image is built by Cloud Build, triggered from the apply itself: gcloud
# builds submit uploads app/driver and blocks until the build succeeds, so
# when this apply finishes the tag in the rendered wrangler.jsonc is
# pullable.
resource "terraform_data" "image" {
  triggers_replace = [local.driver_image]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud builds submit ${path.module}/../../app/driver \
        --project ${local.workspace.project_id} \
        --config ${path.module}/../../app/driver/cloudbuild.yaml \
        --substitutions _IMAGE=${local.driver_image} \
        --service-account projects/${local.workspace.project_id}/serviceAccounts/${google_service_account.build.email}
    EOT
  }

  depends_on = [time_sleep.build_iam_propagation]
}
