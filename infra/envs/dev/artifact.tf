resource "google_artifact_registry_repository" "app" {
  location      = local.region
  repository_id = "${local.artifact_repository_id}-${local.environment}"
  description   = "Application container images"
  format        = "DOCKER"

  labels = {
    environment = local.environment
  }

}