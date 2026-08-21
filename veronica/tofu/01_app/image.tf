resource "google_artifact_registry_repository" "voice" {
  repository_id = tofu.workspace
  format        = "DOCKER"
  description   = "Veronica's session driver images, built by ${tofu.workspace}'s tofu apply."
}

resource "google_service_account" "build" {
  account_id   = "voice-build-${tofu.workspace}"
  display_name = "Veronica session image build"
}

resource "google_project_iam_member" "build_builds" {
  project = local.workspace.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.build.email}"
}

resource "google_artifact_registry_repository_iam_member" "build_pushes" {
  repository = google_artifact_registry_repository.voice.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.build.email}"
}

locals {
  pull_sa_email = "voice-pull-${tofu.workspace}@${local.workspace.project_id}.iam.gserviceaccount.com"
}

resource "google_artifact_registry_repository_iam_member" "cloudflare_pulls" {
  repository = google_artifact_registry_repository.voice.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${local.pull_sa_email}"
}

# A build kicked off seconds after the grants above loses the IAM propagation race.
resource "time_sleep" "build_iam_propagation" {
  create_duration = "20s"
  triggers = {
    builder = google_project_iam_member.build_builds.id
    pusher  = google_artifact_registry_repository_iam_member.build_pushes.id
  }
}

locals {
  image_repository = "${local.workspace.region}-docker.pkg.dev/${local.workspace.project_id}/${google_artifact_registry_repository.voice.repository_id}/driver"

  # Any change to the driver's source replaces the build resource below which re-runs the provisioner.
  driver_source_hash = sha1(join("", [
    for f in sort(fileset("${path.module}/../../app/driver", "**")) :
    "${f}=${filesha1("${path.module}/../../app/driver/${f}")}"
  ]))

  # The content-addressed tag the rendered wrangler config deploys.
  driver_image = "${local.image_repository}:${local.driver_source_hash}"
}

# The image is built by Cloud Build, triggered from an apply.
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
