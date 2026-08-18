resource "google_container_cluster" "assignment" {
  name     = "${local.environment}-${local.gke_cluster_name}"
  location = local.region

  enable_autopilot    = true
  deletion_protection = false

  resource_labels = {
    environment = local.environment
  }

}